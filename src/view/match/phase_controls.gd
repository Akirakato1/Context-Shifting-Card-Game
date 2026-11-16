class_name PhaseControls
extends VBoxContainer

signal intent_requested(kind: StringName, payload: Dictionary)
signal card_target_requested(card_id: StringName)

const CARD_SCENE := preload("res://src/view/match/card_widget.tscn")
const PHASE_START := 1
const PHASE_MAIN_1 := 2
const PHASE_HAND_PLAY := 3
const PHASE_MAIN_2 := 4
const PHASE_END := 5

var _model: Dictionary = {}
var _phase := -1
var _required_halves := 0
var _rendering := false
var _pending: Dictionary = {}
var _after_stage_action: StringName = &""
var _hand_cards: Dictionary = {}
var _hand_order: Array[StringName] = []
var _staged_order: Array[StringName] = []
var _staged: Dictionary = {}
var _orientations: Dictionary = {}
var _card_widgets: Dictionary = {}
var _ability_discards: Array[StringName] = []
var _last_start_request: Dictionary = {}
var _confirmed_start_request: Dictionary = {}
var _input_locked := false
var _targeting := false
var _target_eligible: Array[StringName] = []
var _target_selected: Array[StringName] = []

@onready var _status: Label = $Status
@onready var _timeout_notice: Label = $TimeoutNotice
@onready var _start: VBoxContainer = $StartControls
@onready var _start_a: SpinBox = $StartControls/RequestGrid/A
@onready var _start_b: SpinBox = $StartControls/RequestGrid/B
@onready var _start_c: SpinBox = $StartControls/RequestGrid/C
@onready var _start_total: Label = $StartControls/Total
@onready var _start_confirm: Button = $StartControls/ConfirmButton
@onready var _start_ready: Button = $StartControls/ReadyButton
@onready var _main: HBoxContainer = $MainControls
@onready var _main_ready: Button = $MainControls/ReadyButton
@onready var _hand_play: VBoxContainer = $HandPlayControls
@onready var _shelf_cards: HBoxContainer = $HandPlayControls/SubmissionShelf/Cards
@onready var _hand_cards_node: HBoxContainer = $HandPlayControls/Hand/Cards
@onready var _preview_heading: Label = $HandPlayControls/Preview/Heading
@onready var _preview_details: Label = $HandPlayControls/Preview/Details
@onready var _preview_authority: Label = $HandPlayControls/Preview/Authority
@onready var _invalid_reason: Label = $HandPlayControls/InvalidReason
@onready var _lock_button: Button = $HandPlayControls/ActionRow/LockButton
@onready var _pass_button: Button = $HandPlayControls/ActionRow/PassButton
@onready var _end: VBoxContainer = $EndControls
@onready var _end_required: Label = $EndControls/Required
@onready var _ability_choices: HBoxContainer = $EndControls/AbilityChoices
@onready var _end_confirm: Button = $EndControls/ConfirmButton


func render(model: Dictionary) -> void:
	var next_phase := int(model.get("phase", -1))
	if next_phase != _phase:
		_pending.clear()
		_after_stage_action = &""
		_status.text = ""
		_ability_discards.clear()
		_staged.clear()
		_staged_order.clear()
		if next_phase == PHASE_START:
			_last_start_request.clear()
			_confirmed_start_request.clear()
			_start_a.value = 0
			_start_b.value = 0
			_start_c.value = 0
	_phase = next_phase
	_model = model.duplicate(true)
	_rendering = true
	_start.visible = _phase == PHASE_START
	_main.visible = _phase in [PHASE_MAIN_1, PHASE_MAIN_2]
	_hand_play.visible = _phase == PHASE_HAND_PLAY
	_end.visible = _phase == PHASE_END
	_timeout_notice.text = str(_model.get("timeout_notice", ""))
	_timeout_notice.visible = not _timeout_notice.text.is_empty()
	if _start.visible:
		_render_start()
	if _main.visible:
		var reaction_remaining := maxi(
			int(_model.get("reaction_deadline_msec", -1)) - int(_model.get("now_msec", 0)), 0
		)
		$MainControls/ReactionNotice.text = "Response window  %.1fs" % (reaction_remaining / 1000.0) if reaction_remaining > 0 else ""
		_main_ready.disabled = _input_locked or _pending.has(&"set_ready")
	if _hand_play.visible:
		_render_hand_play()
	if _end.visible:
		_render_end()
	_rendering = false


func click_card(card_id: StringName) -> void:
	if _targeting:
		if card_id in _target_eligible:
			card_target_requested.emit(card_id)
		return
	if _input_locked or _phase != PHASE_HAND_PLAY or _pending.has(&"stage_hand") or _pending.has(&"lock_hand"):
		return
	if _staged.has(card_id):
		_staged.erase(card_id)
		_staged_order.erase(card_id)
	elif _staged_order.size() < 6 and _hand_cards.has(card_id) and _card_is_eligible(_hand_cards[card_id]):
		var card: Dictionary = _hand_cards[card_id]
		_staged_order.append(card_id)
		_staged[card_id] = {
			"card_id": str(card_id),
			"half_index": _default_half_index_for_card(card_id),
			"joker_choices": _default_joker_choices(card),
		}
	_render_hand_play()


func choose_half(card_id: StringName, half_index: int) -> void:
	if not _staged.has(card_id) or half_index < 0 or half_index > 1:
		return
	if not _half_is_eligible(_card_half(_hand_cards[card_id], half_index)):
		return
	_staged[card_id]["half_index"] = half_index
	_render_hand_play()


func set_joker_choice(card_id: StringName, half_index: int, context: int, suit: int) -> void:
	if not _staged.has(card_id):
		return
	var choices: Array = _staged[card_id]["joker_choices"]
	for index in choices.size():
		if int(choices[index].get("half_index", -1)) == half_index:
			choices[index] = {"half_index": half_index, "context": context, "suit": suit}
			_staged[card_id]["joker_choices"] = choices
			_render_hand_play()
			return


func right_click_card(card_id: StringName) -> void:
	if not _hand_cards.has(card_id):
		return
	_orientations[card_id] = not bool(_orientations.get(card_id, false))
	_render_hand_play()


func reorder_hand(card_id: StringName, target_index: int) -> void:
	if card_id not in _hand_order:
		return
	_hand_order.erase(card_id)
	_hand_order.insert(clampi(target_index, 0, _hand_order.size()), card_id)
	_render_hand_play()


func local_hand_order() -> Array[StringName]:
	return _hand_order.duplicate()


func has_staged_card(card_id: StringName) -> bool:
	return _staged.has(card_id)


func staged_selection(card_id: StringName) -> Dictionary:
	return _staged.get(card_id, {}).duplicate(true)


func card_widget(card_id: StringName) -> Variant:
	return _card_widgets.get(card_id)


func set_inputs_locked(locked: bool) -> void:
	_input_locked = locked
	if _phase == PHASE_HAND_PLAY:
		_render_hand_play()
	_refresh_buttons()


func inputs_locked() -> bool:
	return _input_locked


func set_targeting(eligible: Array, selected: Array = []) -> void:
	_targeting = true
	_target_eligible.clear()
	_target_selected.clear()
	for value in eligible:
		_target_eligible.append(StringName(value))
	for value in selected:
		_target_selected.append(StringName(value))
	if _phase == PHASE_HAND_PLAY:
		_render_hand_play()


func clear_targeting() -> void:
	_targeting = false
	_target_eligible.clear()
	_target_selected.clear()
	if _phase == PHASE_HAND_PLAY:
		_render_hand_play()


func toggle_ability_discard(copy_id: StringName, selected: bool) -> void:
	if selected and copy_id not in _ability_discards:
		_ability_discards.append(copy_id)
	elif not selected:
		_ability_discards.erase(copy_id)
	_update_end_button()


func handle_command_result(
	kind: StringName,
	accepted: bool,
	error_code: StringName,
	authoritative_phase: int
) -> void:
	if not _pending.has(kind):
		return
	_pending.erase(kind)
	if authoritative_phase != _phase:
		_after_stage_action = &""
		return
	if not accepted:
		_after_stage_action = &""
		_status.text = "Action rejected: %s" % str(error_code).replace("_", " ")
		_refresh_buttons()
		return
	if kind == &"set_replenishment_request":
		_confirmed_start_request = _last_start_request.duplicate(true)
	if kind == &"stage_hand" and _after_stage_action == &"lock":
		_after_stage_action = &""
		_emit_intent(&"lock_hand", {})
		return
	_refresh_buttons()


func _render_start() -> void:
	_required_halves = int(_model.get(
		"required_half_count", maxi(0, 6 - _model.get("private_hand", []).size()) * 2
	))
	$StartControls/Required.text = "Choose %d half-cards" % _required_halves
	_update_start_total()
	_start_ready.disabled = not _start_ready_allowed()


func _render_hand_play() -> void:
	_load_private_hand()
	_load_authoritative_staging_if_needed()
	_clear_card_nodes()
	var active_context := int(_model.get("active_context", 0))
	var locked := bool(_model.get("private_staging", {}).get("hand_locked", false))
	for card_id in _staged_order:
		if not _hand_cards.has(card_id):
			continue
		_make_card_widget(card_id, active_context, true, locked, _shelf_cards)
	if _staged_order.is_empty():
		var shelf_hint := Label.new()
		shelf_hint.name = "EmptyHint"
		shelf_hint.custom_minimum_size = Vector2(720, 62)
		shelf_hint.text = "No cards staged  ·  click any eligible card below"
		shelf_hint.modulate = Color("718091")
		shelf_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		shelf_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_shelf_cards.add_child(shelf_hint)
	for card_id in _hand_order:
		if card_id in _staged_order or not _hand_cards.has(card_id):
			continue
		_make_card_widget(card_id, active_context, false, locked, _hand_cards_node)
	_render_preview()
	_refresh_buttons()


func _load_private_hand() -> void:
	var cards: Array = _model.get("private_hand", [])
	var current_ids: Array[StringName] = []
	_hand_cards.clear()
	for card in cards:
		if not card is Dictionary:
			continue
		var card_id := StringName(card.get("card_id", ""))
		current_ids.append(card_id)
		_hand_cards[card_id] = card.duplicate(true)
	for existing in _hand_order.duplicate():
		if existing not in current_ids:
			_hand_order.erase(existing)
			_staged.erase(existing)
			_staged_order.erase(existing)
	for card_id in current_ids:
		if card_id not in _hand_order:
			_hand_order.append(card_id)


func _load_authoritative_staging_if_needed() -> void:
	if not _staged.is_empty() or not _staged_order.is_empty():
		return
	var authoritative: Array = _model.get("private_staging", {}).get("staged_submission", [])
	for selection in authoritative:
		if not selection is Dictionary:
			continue
		var card_id := StringName(selection.get("card_id", ""))
		if _hand_cards.has(card_id):
			_staged_order.append(card_id)
			_staged[card_id] = selection.duplicate(true)


func _make_card_widget(
	card_id: StringName,
	active_context: int,
	staged: bool,
	locked: bool,
	parent: Node
):
	var widget = CARD_SCENE.instantiate()
	parent.add_child(widget)
	var selection: Dictionary = _staged.get(card_id, {})
	widget.render(_hand_cards[card_id], active_context, false, {
		"staged": staged,
		"selected_half_index": selection.get("half_index", _default_half_index_for_card(card_id)),
		"joker_choices": selection.get("joker_choices", []),
		"orientation_flipped": bool(_orientations.get(card_id, false)),
		"interaction_disabled": (
			_input_locked or locked or (_targeting and card_id not in _target_eligible)
			or (not _targeting and not staged and not _card_is_eligible(_hand_cards[card_id]))
		),
		"targeting_eligible": _targeting and card_id in _target_eligible,
		"targeting_selected": _targeting and card_id in _target_selected,
	})
	widget.primary_clicked.connect(click_card)
	widget.orientation_requested.connect(right_click_card)
	widget.half_choice_requested.connect(choose_half)
	widget.joker_choice_changed.connect(set_joker_choice)
	_card_widgets[card_id] = widget
	return widget


func _clear_card_nodes() -> void:
	_card_widgets.clear()
	for parent in [_shelf_cards, _hand_cards_node]:
		for child in parent.get_children():
			parent.remove_child(child)
			child.queue_free()


func _render_preview() -> void:
	var preview: Dictionary = _model.get("submission_preview", {})
	_preview_heading.text = "SCORE PREVIEW"
	_preview_authority.text = "Local estimate · host validates on lock"
	if preview.is_empty():
		var base_sum := 0
		for card_id in _staged_order:
			var selection: Dictionary = _staged[card_id]
			var half := _card_half(_hand_cards[card_id], int(selection.half_index))
			base_sum += int(half.get("effective_rank", half.get("rank", 0)))
		_preview_details.text = "Base %d  ·  hand/context multipliers pending final catalogue" % base_sum
		_invalid_reason.text = "" if not _staged_order.is_empty() else "Stage one or more cards, or choose PASS."
		return
	_preview_details.text = "Base %d  ·  %s %s  ·  %s %s  ·  projected %d" % [
		int(preview.get("base_value", 0)), str(preview.get("normal_category", "—")),
		str(preview.get("normal_multiplier", "×1")), str(preview.get("context_category", "No Context Pattern")),
		str(preview.get("context_multiplier", "×1")), int(preview.get("projected_score", 0)),
	]
	_invalid_reason.text = str(preview.get("invalid_reason", ""))


func _render_end() -> void:
	for child in _ability_choices.get_children():
		_ability_choices.remove_child(child)
		child.queue_free()
	var abilities: Array = _model.get("private_abilities", [])
	var required := maxi(abilities.size() - 3, 0)
	_end_required.text = "Choose %d to discard" % required
	for ability in abilities:
		if not ability is Dictionary:
			continue
		var choice := CheckButton.new()
		var copy_id := StringName(ability.get("copy_id", ""))
		choice.text = str(ability.get("ability_id", "Ability")).replace("_", " ").capitalize()
		choice.button_pressed = copy_id in _ability_discards
		choice.disabled = _input_locked
		choice.toggled.connect(func(selected: bool): toggle_ability_discard(copy_id, selected))
		_ability_choices.add_child(choice)
	_update_end_button()


func _update_start_total() -> void:
	if not is_node_ready():
		return
	var total := int(_start_a.value + _start_b.value + _start_c.value)
	_start_total.text = "%d / %d selected" % [total, _required_halves]
	_start_confirm.disabled = _input_locked or (
		total <= 0 or total > _required_halves or _required_halves == 0
		or _pending.has(&"set_replenishment_request")
	)
	_start_ready.disabled = not _start_ready_allowed()


func _update_end_button() -> void:
	var required := maxi(_model.get("private_abilities", []).size() - 3, 0)
	_end_confirm.disabled = _input_locked or _ability_discards.size() != required or _pending.has(&"choose_ability_discards")


func _refresh_buttons() -> void:
	if _phase == PHASE_HAND_PLAY:
		var locked := bool(_model.get("private_staging", {}).get("hand_locked", false))
		var busy := _pending.has(&"stage_hand") or _pending.has(&"lock_hand")
		_lock_button.disabled = _input_locked or locked or busy or _staged_order.is_empty()
		_pass_button.disabled = _input_locked or locked or busy
	elif _phase == PHASE_START:
		_update_start_total()
	elif _phase in [PHASE_MAIN_1, PHASE_MAIN_2]:
		_main_ready.disabled = _input_locked or _pending.has(&"set_ready")
	elif _phase == PHASE_END:
		_update_end_button()


func _on_start_value_changed(_value: float) -> void:
	if not _rendering:
		_update_start_total()


func _on_start_confirm_pressed() -> void:
	if _start_confirm.disabled:
		return
	_last_start_request = {
		0: int(_start_a.value), 1: int(_start_b.value), 2: int(_start_c.value),
	}
	_emit_intent(&"set_replenishment_request", {"request": _last_start_request.duplicate(true)})


func _on_ready_pressed() -> void:
	_emit_intent(&"set_ready", {"ready": true})


func _on_lock_pressed() -> void:
	if _lock_button.disabled:
		return
	_after_stage_action = &"lock"
	_emit_intent(&"stage_hand", {"cards": _canonical_staging()})


func _on_pass_pressed() -> void:
	if _pass_button.disabled:
		return
	_staged.clear()
	_staged_order.clear()
	_after_stage_action = &"lock"
	_emit_intent(&"stage_hand", {"cards": []})
	_render_hand_play()


func _on_end_confirm_pressed() -> void:
	if _end_confirm.disabled:
		return
	var ids: Array = []
	for copy_id in _ability_discards:
		ids.append(str(copy_id))
	_emit_intent(&"choose_ability_discards", {"copy_ids": ids})


func _emit_intent(kind: StringName, payload: Dictionary) -> void:
	if _pending.has(kind):
		return
	_pending[kind] = true
	intent_requested.emit(kind, payload.duplicate(true))
	_refresh_buttons()


func _canonical_staging() -> Array:
	var cards: Array = []
	for card_id in _staged_order:
		cards.append(_staged[card_id].duplicate(true))
	return cards


func _card_is_eligible(card: Dictionary) -> bool:
	return _half_is_eligible(card.get("first", {})) or _half_is_eligible(card.get("second", {}))


func _half_is_eligible(half: Dictionary) -> bool:
	return int(half.get("kind", 0)) == 1 or int(half.get("effective_context", -1)) == int(_model.get("active_context", 0))


func _card_half(card: Dictionary, half_index: int) -> Dictionary:
	return card.get("first", {}) if half_index == 0 else card.get("second", {})


func _default_half_index(card: Dictionary) -> int:
	return 0 if _half_is_eligible(card.get("first", {})) else 1


func _default_half_index_for_card(card_id: StringName) -> int:
	var card: Dictionary = _hand_cards.get(card_id, {})
	if bool(_orientations.get(card_id, false)) and _half_is_eligible(card.get("second", {})):
		return 1
	return _default_half_index(card)


func _default_joker_choices(card: Dictionary) -> Array:
	var choices: Array = []
	for half_index in 2:
		if int(_card_half(card, half_index).get("kind", 0)) == 1:
			choices.append({"half_index": half_index, "context": 0, "suit": 0})
	return choices


func _current_start_request() -> Dictionary:
	return {0: int(_start_a.value), 1: int(_start_b.value), 2: int(_start_c.value)}


func _start_ready_allowed() -> bool:
	if _input_locked or _pending.has(&"set_ready") or _pending.has(&"set_replenishment_request"):
		return false
	if _required_halves == 0:
		return true
	var current := _current_start_request()
	var total := int(current[0]) + int(current[1]) + int(current[2])
	return total == _required_halves and current == _confirmed_start_request
