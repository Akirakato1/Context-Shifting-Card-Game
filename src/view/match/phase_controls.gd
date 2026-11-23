class_name PhaseControls
extends Control

signal intent_requested(kind: StringName, payload: Dictionary)
signal card_target_requested(card_id: StringName)
signal half_target_requested(card_id: StringName, half_index: int)
signal hand_reordered_manually
signal interaction_sound(cue: StringName)

const CARD_SCENE := preload("res://src/view/match/card_widget.tscn")
const ScorePreview := preload("res://src/view/match/score_preview.gd")
const GameTypes := preload("res://src/core/common/game_types.gd")
const CardFactory := preload("res://src/core/cards/card_factory.gd")
const AbilityDeckState := preload("res://src/core/abilities/ability_deck_state.gd")
const Rational := preload("res://src/core/common/rational.gd")
const SCORE_COLORS := {
	"Base": Color("#ffffff"), "Hand": Color("#8ac7ff"), "Context": Color("#ff9393"),
	"Field": Color("#99dfaa"), "Total": Color("#ffffff"),
}
const PHASE_START := 1
const PHASE_MAIN_1 := 2
const PHASE_HAND_PLAY := 3
const PHASE_MAIN_2 := 4
const PHASE_END := 5
const HAND_SLIDE_SECONDS := 0.16
const HAND_SLOT_HEIGHT := 326.0
const STAGED_CARD_LIFT := 20.0

class ScoreValue extends Label:
	var rows: Array = []

	func _make_custom_tooltip(_text: String) -> Object:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", get_theme_stylebox("panel", "TooltipPanel"))
		var table := GridContainer.new()
		table.columns = 2
		table.add_theme_constant_override("h_separation", 18)
		table.add_theme_constant_override("v_separation", 3)
		panel.add_child(table)
		for row: Array in rows:
			var term := Label.new()
			term.text = row[0]
			var value := Label.new()
			value.text = row[1]
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			table.add_child(term)
			table.add_child(value)
			for label in [term, value]:
				label.add_theme_font_override("font", get_theme_font("font"))
				label.add_theme_font_size_override("font_size", 18)
		return panel

var _model: Dictionary = {}
var _phase := -1
var _required_halves := 0
var _pending: Dictionary = {}
var _after_stage_action: StringName = &""
var _hand_lock_acknowledged := false
var _hand_cards: Dictionary = {}
var _hand_order: Array[StringName] = []
var _staged_order: Array[StringName] = []
var _staged: Dictionary = {}
var _orientations: Dictionary = {}
var _card_widgets: Dictionary = {}
var _pending_draws: Dictionary[StringName, bool] = {}
var _ability_discards: Array[StringName] = []
var _discard_acknowledged := false
var _start_counts := {0: 0, 1: 0, 2: 0}
var _start_keypads: Array[VBoxContainer] = []
var _start_keys: Array[Array] = []
var _start_piles: Array[Control] = []
var _last_start_request: Dictionary = {}
var _confirmed_start_request: Dictionary = {}
var _start_ready_requested := false
var _ready_on_host := false
var _input_locked := false
var _targeting := false
var _target_kind: StringName = &""
var _target_eligible: Array = []
var _target_selected: Array = []
var _ability_focus_held := false
var _authoritative_staging_signature := ""
var _score_preview := ScorePreview.new()
var _score_labels: Dictionary[String, Label] = {}
var _score_values: Dictionary = {}
var _sort_key := -2
var _rank_sort_ascending := true
var _hand_drag_card: StringName
var _hand_drag_gap := -1
var _hand_pointer: Vector2
var _hand_drop_accepted := false
var _hand_slide: Tween
@export var table_cockpit := false
@export var score_font: Font
var show_placeholder_guides := true

@onready var _status: Label = $Status
@onready var _timeout_notice: Label = $TimeoutNotice
@onready var _start: VBoxContainer = $StartControls
@onready var _start_grid: HBoxContainer = $StartControls/RequestGrid
@onready var _start_total: Label = $StartControls/Total
@onready var _start_ready: Button = $StartControls/ReadyButton
@onready var _main: HBoxContainer = $MainControls
@onready var _main_ready: Button = $MainControls/ReadyButton
@onready var _hand_play: Control = $HandPlayControls
@onready var _shelf_cards: HBoxContainer = $HandPlayControls/SubmissionShelf/Cards
@onready var _hand_cards_node: HBoxContainer = $HandPlayControls/Hand/Cards
@onready var _preview_heading: Label = $HandPlayControls/Preview/Heading
@onready var _preview_details: Label = $HandPlayControls/Preview/Details
@onready var _preview_factors: HBoxContainer = $HandPlayControls/Preview/Factors
@onready var _preview_authority: Label = $HandPlayControls/Preview/Authority
@onready var _invalid_reason: Label = $HandPlayControls/InvalidReason
@onready var _submit_button: Button = $HandPlayControls/ActionRow/SubmitButton
@onready var _end: VBoxContainer = $EndControls
@onready var _end_required: Label = $EndControls/Required
@onready var _ability_choices: HBoxContainer = $EndControls/AbilityChoices
@onready var _end_confirm: Button = $EndControls/ConfirmButton


func _ready() -> void:
	resized.connect(_position_phase_content)
	_build_start_keypads()
	set_process_input(table_cockpit)
	if table_cockpit:
		$HandPlayControls/SubmissionShelf.hide()
		$HandPlayControls/Preview/Heading.hide()
		$HandPlayControls/Preview/Authority.hide()
		_preview_details.hide()
		_build_score_formula()
		_preview_factors.show()
		$HandPlayControls/Hand/Heading.hide()
		_hand_play.custom_minimum_size.y = 410
		_hand_cards_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_hand_cards_node.add_theme_constant_override("separation", 8)
		_forward_hand_drop(_hand_cards_node)
		_layout_cockpit()
	_position_phase_content()


func _build_start_keypads() -> void:
	for context in _start_counts:
		var context_name := GameTypes.context_name(context)
		var keypad := VBoxContainer.new()
		keypad.name = context_name
		keypad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keypad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		keypad.add_theme_constant_override("separation", 4)
		_start_grid.add_child(keypad)
		_start_keypads.append(keypad)
		var heading := Label.new()
		heading.name = "Heading"
		heading.text = context_name
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		keypad.add_child(heading)

		var keys: Array[Button] = []
		for first_number in range(1, CardFactory.CONTEXT_DRAW_CAP + 1, 3):
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_theme_constant_override("separation", 5)
			keypad.add_child(row)
			for amount in range(first_number, mini(first_number + 3, CardFactory.CONTEXT_DRAW_CAP + 1)):
				var button := Button.new()
				button.name = "Count%d" % amount
				button.text = str(amount)
				button.tooltip_text = "Draw %d from %s" % [amount, context_name]
				button.custom_minimum_size = Vector2(34, 32)
				button.theme_type_variation = &"DrawPileKey"
				button.add_theme_font_override("font", score_font)
				button.toggle_mode = true
				button.pressed.connect(_on_start_number_pressed.bind(context, amount))
				row.add_child(button)
				keys.append(button)
		_start_keys.append(keys)


func attach_start_keypads(piles: Array[Control]) -> void:
	_start_piles = piles
	_start_grid.hide()
	$StartControls/Required.hide()
	for context in _start_counts:
		var keypad := _start_keypads[context]
		keypad.reparent(self, false)
		keypad.get_node("Heading").hide()
		keypad.hide()
		_start_piles[context].item_rect_changed.connect(position_start_keypads, CONNECT_DEFERRED)


func position_start_keypads() -> void:
	if not _start.visible or _start_piles.is_empty():
		return
	var to_local := get_global_transform().affine_inverse()
	for context in _start_counts:
		var keypad := _start_keypads[context]
		var pile := _start_piles[context]
		var bottom_center := (to_local * pile.get_global_transform()) * Vector2(pile.size.x / 2.0, pile.size.y)
		keypad.size = keypad.get_combined_minimum_size()
		keypad.position = bottom_center + Vector2(-keypad.size.x / 2.0, 6.0)


func _notification(what: int) -> void:
	if not table_cockpit:
		return
	if what == NOTIFICATION_DRAG_BEGIN:
		_begin_hand_drag()
	elif what == NOTIFICATION_DRAG_END and not _hand_drag_card.is_empty():
		_finish_hand_drag()


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_hand_pointer = event.position


func _draw() -> void:
	if not show_placeholder_guides:
		return
	if not table_cockpit:
		draw_style_box(get_theme_stylebox("panel"), Rect2(Vector2.ZERO, size))
		return
	for controls: Control in [_start, _main, _end]:
		if controls.visible:
			draw_style_box(get_theme_stylebox("panel"), Rect2(controls.position - Vector2(12, 10), controls.size + Vector2(24, 20)))


func _position_phase_content() -> void:
	var panel_width := minf(size.x - 24, 780.0) if table_cockpit else size.x
	for controls: Control in [_start, _main, _end]:
		if not controls.visible:
			continue
		var height := controls.get_combined_minimum_size().y
		controls.size = Vector2(panel_width, height)
		var top := -height - 16 if table_cockpit else 48.0
		if table_cockpit and controls == _main and _phase == PHASE_MAIN_2:
			top = 49.0
		controls.position = Vector2((size.x - panel_width) / 2.0, top)
	_hand_play.offset_top = 0.0 if table_cockpit else 42.0
	_hand_play.offset_bottom = _hand_play.offset_top + (410.0 if table_cockpit else 478.0)
	_status.position = Vector2(0, -240 if table_cockpit else 0)
	_timeout_notice.position = Vector2(0, -266 if table_cockpit else 24)
	for label: Label in [_status, _timeout_notice]:
		label.size.x = size.x
	position_start_keypads()
	queue_redraw()


func _layout_cockpit() -> void:
	var preview: Control = $HandPlayControls/Preview
	preview.anchor_left = 0.0
	preview.offset_left = 10
	preview.offset_top = 8
	preview.offset_right = -220
	preview.offset_bottom = 52
	var reason: Control = $HandPlayControls/InvalidReason
	reason.anchor_left = 0.0
	reason.offset_left = 10
	reason.offset_top = 53
	reason.offset_right = -10
	reason.offset_bottom = 73
	var hand_ui: Control = $HandPlayControls/Hand
	hand_ui.offset_left = 5
	hand_ui.offset_right = -5
	hand_ui.offset_top = 74
	hand_ui.offset_bottom = hand_ui.offset_top + HAND_SLOT_HEIGHT
	var actions: Control = $HandPlayControls/ActionRow
	actions.anchor_left = 0.0
	actions.offset_top = 2
	actions.offset_bottom = 48
	actions.offset_right = -4
	for label: Label in [_status, _timeout_notice]:
		label.visible = not label.text.is_empty()


func render(model: Dictionary) -> void:
	var next_phase := int(model.get("phase", -1))
	if next_phase != _phase:
		_cancel_hand_drag()
		_pending.clear()
		_after_stage_action = &""
		_hand_lock_acknowledged = false
		_status.text = ""
		_ability_discards.clear()
		_discard_acknowledged = false
		_staged.clear()
		_staged_order.clear()
		_authoritative_staging_signature = ""
		if next_phase == PHASE_START:
			_last_start_request.clear()
			_confirmed_start_request.clear()
			_start_ready_requested = false
			for context in _start_counts:
				_start_counts[context] = 0
	_phase = next_phase
	_model = model.duplicate(true)
	var local_id := str(_model.get("private_player_id", ""))
	_ready_on_host = _model.get("players", []).any(func(player: Dictionary) -> bool:
		return str(player.get("player_id", "")) == local_id and bool(player.get("ready", false))
	)
	queue_redraw()
	_start.visible = _phase == PHASE_START
	for keypad in _start_keypads:
		keypad.visible = _start.visible
	_main.visible = _phase in [PHASE_MAIN_1, PHASE_MAIN_2]
	var hand_playing := _phase == PHASE_HAND_PLAY
	_hand_play.visible = hand_playing or (table_cockpit and _phase not in [PHASE_MAIN_2, PHASE_END])
	if table_cockpit:
		$HandPlayControls/Preview.visible = hand_playing
		$HandPlayControls/ActionRow.visible = hand_playing
		_invalid_reason.visible = hand_playing
	_end.visible = _phase == PHASE_END and (not table_cockpit or _required_ability_discards() == 0)
	_timeout_notice.text = str(_model.get("timeout_notice", ""))
	_timeout_notice.visible = not _timeout_notice.text.is_empty()
	if _start.visible:
		_render_start()
	if _main.visible:
		var reaction_remaining := maxi(
			int(_model.get("reaction_deadline_msec", -1)) - int(_model.get("now_msec", 0)), 0
		)
		$MainControls/ReactionNotice.text = "Response window  %.1fs" % (reaction_remaining / 1000.0) if reaction_remaining > 0 else ""
		_refresh_buttons()
	if _hand_play.visible:
		_render_hand_play()
	if table_cockpit:
		_status.visible = not _status.text.is_empty() and next_phase != PHASE_HAND_PLAY
	if _end.visible:
		_render_end()
	_position_phase_content()


func click_card(card_id: StringName) -> void:
	if _targeting:
		if _target_kind in [&"card", &"full_card"] and str(card_id) in _target_eligible:
			interaction_sound.emit(&"select")
			card_target_requested.emit(card_id)
		return
	if (
		_input_locked or _ability_focus_held or _phase != PHASE_HAND_PLAY
		or _hand_is_locked() or _hand_command_pending()
	):
		interaction_sound.emit(&"invalid")
		return
	if _staged.has(card_id):
		_staged.erase(card_id)
		_staged_order.erase(card_id)
	elif _staged_order.size() < 6 and _hand_cards.has(card_id):
		var card: Dictionary = _hand_cards[card_id]
		if bool(card.get("submission_locked", false)):
			_show_hand_feedback("This card is locked for this round.")
			interaction_sound.emit(&"invalid")
			return
		var half_index := _top_half(card_id) if table_cockpit else _default_half_index_for_card(card_id)
		if not _half_index_is_eligible(card, half_index):
			_show_hand_feedback("The top half is outside the active contexts.")
			interaction_sound.emit(&"invalid")
			return
		_staged_order.append(card_id)
		_staged[card_id] = {
			"card_id": str(card_id),
			"half_index": half_index,
			"joker_choices": _default_joker_choices(card),
		}
	else:
		interaction_sound.emit(&"invalid")
		return
	interaction_sound.emit(&"select")
	_status.text = ""
	_render_hand_play()


func choose_half(card_id: StringName, half_index: int) -> void:
	if _targeting:
		var target := {"card_id": str(card_id), "half_index": half_index}
		if _target_kind == &"half_card" and target in _target_eligible:
			interaction_sound.emit(&"select")
			half_target_requested.emit(card_id, half_index)
		return
	if not _staged.has(card_id) or half_index < 0 or half_index > 1:
		return
	if not _half_index_is_eligible(_hand_cards[card_id], half_index):
		interaction_sound.emit(&"invalid")
		return
	if table_cockpit:
		_orientations[card_id] = half_index == 1
	_staged[card_id]["half_index"] = half_index
	interaction_sound.emit(&"flip")
	_render_hand_play()


func set_joker_choice(card_id: StringName, half_index: int, context: int, suit: int) -> void:
	if (
		not _can_configure_jokers() or _hand_command_pending()
		or not _hand_cards.has(card_id) or half_index not in [0, 1]
		or int(_card_half(_hand_cards[card_id], half_index).get("kind", 0)) != GameTypes.HalfKind.JOKER
	):
		return
	_emit_intent(&"configure_joker", {
		"card_id": str(card_id), "half_index": half_index, "context": context, "suit": suit,
	})
	_render_hand_play()


func _can_configure_jokers() -> bool:
	return (
		_phase in [PHASE_START, PHASE_MAIN_1, PHASE_HAND_PLAY]
		and not (_input_locked or _hand_is_locked() or _targeting or _ability_focus_held)
	)


func right_click_card(card_id: StringName) -> void:
	if not _hand_cards.has(card_id):
		return
	if table_cockpit:
		if _targeting or _ability_focus_held or _hand_is_locked() or _input_locked or _hand_command_pending():
			interaction_sound.emit(&"invalid")
			return
		var incoming_half := 1 - _top_half(card_id)
		if not _half_index_is_eligible(_hand_cards[card_id], incoming_half):
			_show_hand_feedback("That half is outside the active contexts.")
			interaction_sound.emit(&"invalid")
			return
		if _staged.has(card_id):
			_staged[card_id]["half_index"] = incoming_half
	_status.text = ""
	_orientations[card_id] = not bool(_orientations.get(card_id, false))
	interaction_sound.emit(&"flip")
	_render_hand_play()


func sort_hand(context: int = -1) -> bool:
	if not _can_sort_hand():
		return false
	_sort_key = context
	var kept_scoring_half := false
	if _sort_key >= 0:
		for card_id in _hand_order:
			if not _orient_for_context_sort(card_id):
				kept_scoring_half = true
	_apply_hand_sort()
	if kept_scoring_half:
		_show_hand_feedback("Staged cards keep their scoring half if the other half is inactive.")
	return true


func toggle_rank_sort() -> bool:
	if not _can_sort_hand():
		return false
	_rank_sort_ascending = not _rank_sort_ascending
	if _sort_key == -2:
		_sort_key = -1
	_apply_hand_sort()
	return true


func rank_sort_ascending() -> bool:
	return _rank_sort_ascending


func _can_sort_hand() -> bool:
	return not (_input_locked or _ability_focus_held or _targeting or _hand_command_pending() or _hand_is_locked())


func _apply_hand_sort() -> void:
	_sort_hand_order()
	interaction_sound.emit(&"shuffle")
	if table_cockpit or _phase == PHASE_HAND_PLAY:
		_render_hand_play()


func _orient_for_context_sort(card_id: StringName) -> bool:
	var card: Dictionary = _hand_cards[card_id]
	var top := _top_half(card_id)
	var other := 1 - top
	if _half_matches_sort_context(_card_half(card, top)) or not _half_matches_sort_context(_card_half(card, other)):
		return true
	if _staged.has(card_id):
		if not _half_index_is_eligible(card, other):
			return false
		_staged[card_id]["half_index"] = other
	_orientations[card_id] = other == 1
	return true


func _half_matches_sort_context(half: Dictionary) -> bool:
	if int(half.get("kind", 0)) == GameTypes.HalfKind.JOKER:
		return int(half.get("joker_context", -1)) == _sort_key
	return int(half.get("effective_context", half.get("base_context", -1))) == _sort_key


func ordered_hand(cards: Array) -> Array:
	if _sort_key == -2:
		return cards
	var ordered := cards.duplicate()
	var original := {}
	for i in cards.size():
		original[str(cards[i].get("card_id", ""))] = i
	ordered.sort_custom(func(a: Dictionary, b: Dictionary):
		var priority_a := _sort_priority(a)
		var priority_b := _sort_priority(b)
		if priority_a.x != priority_b.x:
			return priority_a.x < priority_b.x
		if priority_a.y != priority_b.y:
			return priority_a.y < priority_b.y
		return original[str(a.card_id)] < original[str(b.card_id)]
	)
	return ordered


func _sort_hand_order() -> void:
	if _sort_key == -2:
		return
	var cards: Array = []
	for id in _hand_order:
		if _hand_cards.has(id): cards.append(_hand_cards[id])
	_hand_order.clear()
	for entry: Dictionary in ordered_hand(cards):
		_hand_order.append(StringName(entry.card_id))


func _sort_priority(card: Dictionary) -> Vector2i:
	var face := _card_half(card, _top_half(StringName(card.get("card_id", ""))))
	var context_group := 1 if _sort_key >= 0 and not _half_matches_sort_context(face) else 0
	var rank := int(face.get("effective_rank", face.get("base_rank", 0)))
	return Vector2i(context_group, rank if _rank_sort_ascending else -rank)


func _top_half(card_id: StringName) -> int:
	return 1 if bool(_orientations.get(card_id, false)) else 0


func _hand_command_pending() -> bool:
	return _pending.has(&"stage_hand") or _pending.has(&"lock_hand") or _pending.has(&"configure_joker")


func _hand_is_locked() -> bool:
	return _hand_lock_acknowledged or bool(_model.get("private_staging", {}).get("hand_locked", false))


func _show_hand_feedback(message: String) -> void:
	if table_cockpit:
		_invalid_reason.text = message


func reorder_hand(card_id: StringName, target_index: int) -> void:
	if card_id not in _hand_order:
		return
	_hand_order.erase(card_id)
	_hand_order.insert(clampi(target_index, 0, _hand_order.size()), card_id)
	_render_hand_play()


func _forward_hand_drop(control: Control) -> void:
	control.set_drag_forwarding(Callable(), _can_drop_hand_card, _drop_hand_card)


func _begin_hand_drag() -> void:
	var data: Variant = get_viewport().gui_get_drag_data()
	if not data is Dictionary or data.get("hand") != _hand_cards_node:
		return
	_hand_drag_card = data.card_id
	_hand_drag_gap = _hand_order.find(_hand_drag_card)
	_update_draw_presentation(_hand_drag_card)
	interaction_sound.emit(&"drag")


func _can_drop_hand_card(_at_position: Vector2, data: Variant) -> bool:
	if (
		_hand_drag_card.is_empty() or not _can_sort_hand()
		or not data is Dictionary or data.get("hand") != _hand_cards_node
	):
		return false
	# Use the input event so hover and drop see the same point as GUI hit testing.
	var pointer := _hand_cards_node.get_global_transform_with_canvas().affine_inverse() * _hand_pointer
	if not Rect2(Vector2.ZERO, _hand_cards_node.size).has_point(pointer):
		return false
	var gap := _hand_drag_gap
	# Use fixed slot centers so moving cards cannot move the drag threshold.
	while gap + 1 < _hand_order.size():
		var center := _hand_slot(gap + 1).get_rect().get_center().x
		if pointer.x < center and not is_equal_approx(pointer.x, center):
			break
		gap += 1
	while gap > 0:
		var center := _hand_slot(gap - 1).get_rect().get_center().x
		if pointer.x > center and not is_equal_approx(pointer.x, center):
			break
		gap -= 1
	if gap != _hand_drag_gap:
		_hand_drag_gap = gap
		var preview_order := _hand_order.duplicate()
		preview_order.erase(_hand_drag_card)
		preview_order.insert(gap, _hand_drag_card)
		_slide_hand_widgets(preview_order, _hand_drag_card)
	return true


func _drop_hand_card(_at_position: Vector2, _data: Variant) -> void:
	_hand_drop_accepted = true


func _finish_hand_drag() -> void:
	var dragged_id := _hand_drag_card
	var dragged: CardWidget = _card_widgets[dragged_id]
	interaction_sound.emit(&"drop" if _hand_drop_accepted else &"invalid")
	var reordered := _hand_drop_accepted and _hand_drag_gap != _hand_order.find(_hand_drag_card)
	if reordered:
		_sort_key = -2
		_hand_order.erase(_hand_drag_card)
		_hand_order.insert(_hand_drag_gap, _hand_drag_card)
	_hand_drag_card = &""
	_hand_drag_gap = -1
	_hand_drop_accepted = false
	for index in _hand_order.size():
		var card_id := _hand_order[index]
		var widget: CardWidget = _card_widgets[card_id]
		var slot := _hand_slot(index)
		if widget.get_parent() == slot:
			continue
		var visual_position := widget.global_position
		widget.reparent(slot, false)
		_place_hand_widget(widget, _staged.has(card_id))
		if widget != dragged:
			widget.global_position = visual_position
	_update_draw_presentation(dragged_id)
	_slide_hand_widgets(_hand_order)
	if reordered:
		hand_reordered_manually.emit()


func _cancel_hand_drag() -> void:
	if not _hand_drag_card.is_empty():
		get_viewport().gui_cancel_drag()


func _hand_slot(index: int) -> Control:
	return _hand_cards_node.get_child(index) as Control


func _slide_hand_widgets(order: Array[StringName], skip_card: StringName = &"") -> void:
	if _hand_slide != null:
		_hand_slide.kill()
		_hand_slide = null
	for index in order.size():
		var card_id := order[index]
		if card_id == skip_card:
			continue
		var widget: CardWidget = _card_widgets[card_id]
		var current_slot := widget.get_parent() as Control
		var target_offset := _hand_slot(index).position.x - current_slot.position.x
		if is_equal_approx(widget.position.x, target_offset):
			continue
		if _hand_slide == null:
			_hand_slide = create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_hand_slide.tween_property(widget, "position:x", target_offset, HAND_SLIDE_SECONDS)


func _place_hand_widget(widget: Control, staged: bool) -> void:
	widget.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	widget.offset_top = 0.0 if staged else STAGED_CARD_LIFT
	widget.offset_bottom = -STAGED_CARD_LIFT if staged else 0.0


func move_card(card_id: StringName, delta: int) -> void:
	if _input_locked or delta == 0:
		return
	var order := _staged_order if _staged.has(card_id) else _hand_order
	var current_index := order.find(card_id)
	if current_index < 0:
		return
	var target_index := clampi(current_index + delta, 0, order.size() - 1)
	if target_index == current_index:
		return
	order.remove_at(current_index)
	order.insert(target_index, card_id)
	_render_hand_play()


func local_hand_order() -> Array[StringName]:
	return _hand_order.duplicate()


func staged_order() -> Array[StringName]:
	return _staged_order.duplicate()


func has_staged_card(card_id: StringName) -> bool:
	return _staged.has(card_id)


func staged_selection(card_id: StringName) -> Dictionary:
	return _staged.get(card_id, {}).duplicate(true)


func card_widget(card_id: StringName) -> Variant:
	return _card_widgets.get(card_id)


func set_draw_pending(card_id: StringName, pending: bool) -> void:
	if pending:
		_pending_draws[card_id] = true
		if _hand_drag_card == card_id:
			_cancel_hand_drag()
	else:
		_pending_draws.erase(card_id)
	_update_draw_presentation(card_id)


func clear_pending_draws() -> void:
	var pending_ids := _pending_draws.keys()
	_pending_draws.clear()
	for card_id in pending_ids:
		_update_draw_presentation(card_id)


func _update_draw_presentation(card_id: StringName) -> void:
	var widget: Control = _card_widgets.get(card_id)
	if widget == null:
		return
	var pending := _pending_draws.has(card_id)
	var dragging := not _hand_drag_card.is_empty() and _hand_drag_card == card_id
	widget.modulate.a = 0.0 if pending or dragging else 1.0
	widget.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED if pending else Control.MOUSE_BEHAVIOR_INHERITED
	widget.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED if pending else Control.FOCUS_BEHAVIOR_INHERITED


func set_inputs_locked(locked: bool) -> void:
	if locked == _input_locked:
		return
	_input_locked = locked
	if _phase == PHASE_HAND_PLAY:
		_render_hand_play()
	elif not locked and _phase == PHASE_START:
		_advance_start_request()
	_refresh_buttons()


func inputs_locked() -> bool:
	return _input_locked


func trigger_ready_shortcut() -> bool:
	return _request_ready()


func hand_focus_rect() -> Rect2:
	var bounds := _hand_cards_node.get_global_rect()
	bounds.position.y -= 22.0
	bounds.size.y += 22.0
	return bounds


func set_ability_focus_held(held: bool) -> void:
	if _ability_focus_held == held:
		return
	_ability_focus_held = held
	if held:
		_cancel_hand_drag()
	if table_cockpit:
		_render_hand_play()
	else:
		_refresh_buttons()


func set_targeting(kind: StringName, eligible: Array, selected: Array = []) -> void:
	_targeting = true
	_target_kind = kind
	_target_eligible = eligible.duplicate(true)
	_target_selected = selected.duplicate(true)
	if _phase == PHASE_HAND_PLAY:
		_render_hand_play()


func clear_targeting() -> void:
	if not _targeting:
		return
	_targeting = false
	_target_kind = &""
	_target_eligible.clear()
	_target_selected.clear()
	if _phase == PHASE_HAND_PLAY:
		_render_hand_play()


func toggle_ability_discard(copy_id: StringName, selected: bool) -> void:
	if _phase != PHASE_END or _discard_inputs_locked():
		return
	if selected and copy_id not in _ability_discards and _ability_discards.size() < _required_ability_discards():
		_ability_discards.append(copy_id)
	elif not selected:
		_ability_discards.erase(copy_id)
	interaction_sound.emit(&"select")
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
		if kind == &"set_replenishment_request" and _last_start_request != _start_counts:
			_advance_start_request()
			_refresh_buttons()
			return
		if _phase == PHASE_START and kind != &"configure_joker":
			_start_ready_requested = false
		_status.text = "Action rejected: %s" % str(error_code).replace("_", " ")
		_show_hand_feedback(_status.text)
		if table_cockpit and _phase != PHASE_HAND_PLAY:
			_status.show()
		if kind == &"configure_joker":
			_render_hand_play()
		else:
			_refresh_buttons()
		return
	if kind == &"configure_joker":
		_render_hand_play()
		return
	if _phase == PHASE_START and kind in [&"set_replenishment_request", &"set_ready"]:
		_status.text = ""
		_status.hide()
	if kind == &"set_ready":
		_ready_on_host = true
	if kind == &"set_replenishment_request":
		_confirmed_start_request = _last_start_request.duplicate(true)
		_advance_start_request()
	if kind == &"stage_hand" and _after_stage_action == &"lock":
		_after_stage_action = &""
		_emit_intent(&"lock_hand", {})
		return
	if kind == &"lock_hand":
		_hand_lock_acknowledged = true
		_render_hand_play()
		return
	if kind == &"choose_ability_discards":
		_discard_acknowledged = true
	_refresh_buttons()


func _render_start() -> void:
	_required_halves = int(_model.get(
		"required_half_count", maxi(0, 6 - _model.get("private_hand", []).size()) * 2
	))
	$StartControls/Required.text = "Choose %d half-cards" % _required_halves
	_update_start_total()


func _render_hand_play() -> void:
	_cancel_hand_drag()
	var hand_changed := _load_private_hand()
	if _phase == PHASE_HAND_PLAY:
		_load_authoritative_staging_if_needed()
		for card_id in _staged.keys():
			if bool(_hand_cards[card_id].get("submission_locked", false)):
				_staged.erase(card_id)
				_staged_order.erase(card_id)
				continue
			var selection: Dictionary = _staged[card_id]
			selection["joker_choices"] = _default_joker_choices(
				_hand_cards[card_id], selection.get("joker_choices", [])
			)
	if table_cockpit and hand_changed:
		_sort_hand_order()
	_clear_card_nodes()
	var active_context := int(_model.get("active_context", 0))
	var locked := _hand_is_locked()
	if table_cockpit:
		for index in range(6):
			var slot := Control.new()
			slot.name = "CardSlot"
			slot.custom_minimum_size = Vector2(120, HAND_SLOT_HEIGHT)
			slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_hand_cards_node.add_child(slot)
			if index >= _hand_order.size():
				continue
			var card_id := _hand_order[index]
			var staged := _staged.has(card_id)
			var widget: Control = _make_card_widget(card_id, active_context, staged, locked, slot)
			_place_hand_widget(widget, staged)
			_forward_hand_drop(widget)
		if _phase == PHASE_HAND_PLAY:
			_render_preview()
		_refresh_buttons()
		return
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


func _load_private_hand() -> bool:
	var cards: Array = _model.get("private_hand", [])
	var current_ids: Array[StringName] = []
	_hand_cards.clear()
	for card in cards:
		if not card is Dictionary:
			continue
		var card_id := StringName(card.get("card_id", ""))
		current_ids.append(card_id)
		_hand_cards[card_id] = card.duplicate(true)
	var changed := current_ids.size() != _hand_order.size()
	for existing in _hand_order.duplicate():
		if existing not in current_ids:
			changed = true
			_hand_order.erase(existing)
			_staged.erase(existing)
			_staged_order.erase(existing)
			_orientations.erase(existing)
	for card_id in current_ids:
		if card_id not in _hand_order:
			_hand_order.append(card_id)
			if table_cockpit:
				_orientations[card_id] = _default_half_index(_hand_cards[card_id]) == 1
				if _sort_key >= 0:
					_orient_for_context_sort(card_id)
	return changed


func _load_authoritative_staging_if_needed() -> void:
	var authoritative: Array = _model.get("private_staging", {}).get("staged_submission", [])
	var signature := JSON.stringify(authoritative)
	if signature == _authoritative_staging_signature:
		return
	_authoritative_staging_signature = signature
	_staged.clear()
	_staged_order.clear()
	for selection in authoritative:
		if not selection is Dictionary:
			continue
		var card_id := StringName(selection.get("card_id", ""))
		if _hand_cards.has(card_id):
			_staged_order.append(card_id)
			_staged[card_id] = selection.duplicate(true)
			if table_cockpit:
				_orientations[card_id] = int(selection.get("half_index", 0)) == 1


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
	var full_card_value := str(card_id)
	var full_card_eligible := (
		_targeting and _target_kind in [&"card", &"full_card"]
		and full_card_value in _target_eligible
	)
	var full_card_selected := _targeting and full_card_value in _target_selected
	var half_eligible: Array[bool] = [false, false]
	var half_selected: Array[bool] = [false, false]
	if _targeting:
		for half_index in range(2):
			var half_target := {"card_id": full_card_value, "half_index": half_index}
			half_eligible[half_index] = _target_kind == &"half_card" and half_target in _target_eligible
			half_selected[half_index] = half_target in _target_selected
	var has_target := full_card_eligible or half_eligible[0] or half_eligible[1]
	widget.render(_hand_cards[card_id], active_context, false, {
		"active_contexts": _active_contexts(),
		"staged": staged,
		"selected_half_index": selection.get("half_index", _top_half(card_id) if table_cockpit else _default_half_index_for_card(card_id)),
		"joker_choices": selection.get("joker_choices", []),
		"joker_editable": _can_configure_jokers(),
		"joker_edit_pending": _hand_command_pending(),
		"orientation_flipped": bool(_orientations.get(card_id, false)),
		"interaction_disabled": (
			_phase != PHASE_HAND_PLAY or _input_locked or locked or (_targeting and not has_target)
			or (_ability_focus_held and not has_target)
			or (not table_cockpit and not _targeting and not staged and not _card_is_eligible(_hand_cards[card_id]))
		),
		"display_only": table_cockpit and (_phase != PHASE_HAND_PLAY or _ability_focus_held),
		"targeting_kind": _target_kind,
		"targeting_eligible": full_card_eligible,
		"targeting_selected": full_card_selected,
		"targeting_half_eligible": half_eligible,
		"targeting_half_selected": half_selected,
		"reorder_enabled": not table_cockpit and not _targeting and not locked,
		"drag_hand": _hand_cards_node if table_cockpit and _can_sort_hand() else null,
		"select_in_place": table_cockpit,
		"hover_enabled": table_cockpit and not _input_locked,
	})
	widget.primary_clicked.connect(click_card)
	widget.orientation_requested.connect(right_click_card)
	widget.half_choice_requested.connect(choose_half)
	widget.half_target_requested.connect(_on_half_target_requested)
	widget.joker_choice_changed.connect(set_joker_choice)
	widget.reorder_requested.connect(move_card)
	widget.card_hovered.connect(func(): interaction_sound.emit(&"hover"))
	widget.interaction_rejected.connect(func(): interaction_sound.emit(&"invalid"))
	_card_widgets[card_id] = widget
	_update_draw_presentation(card_id)
	return widget


func _on_half_target_requested(card_id: StringName, half_index: int) -> void:
	choose_half(card_id, half_index)


func _clear_card_nodes() -> void:
	if _hand_slide != null:
		_hand_slide.kill()
		_hand_slide = null
	_card_widgets.clear()
	for parent in [_shelf_cards, _hand_cards_node]:
		for child in parent.get_children():
			parent.remove_child(child)
			child.queue_free()


func _render_preview() -> void:
	var preview: Dictionary = _model.get("submission_preview", {})
	if table_cockpit:
		_render_cockpit_preview(preview)
		return
	_preview_heading.text = "SCORE PREVIEW"
	_preview_authority.text = "Local estimate · host validates on lock"
	if preview.is_empty():
		var base_sum := 0
		for card_id in _staged_order:
			var selection: Dictionary = _staged[card_id]
			var half := _card_half(_hand_cards[card_id], int(selection.half_index))
			base_sum += int(half.get("effective_rank", half.get("rank", 0)))
		_preview_details.text = "Base %d  ·  hand/context multipliers appear after host evaluation" % base_sum
		_invalid_reason.text = "" if not _staged_order.is_empty() else "Stage one or more cards, or choose PASS."
		return
	if preview.has("score_breakdown"):
		_preview_details.text = _factor_breakdown_text(preview.score_breakdown)
		_invalid_reason.text = str(preview.get("invalid_reason", ""))
		return
	_preview_details.text = "Base %d  ·  %s %s  ·  %s %s  ·  projected %d" % [
		int(preview.get("base_value", 0)), str(preview.get("normal_category", "—")),
		str(preview.get("normal_multiplier", "×1")), str(preview.get("context_category", "No Context Pattern")),
		str(preview.get("context_multiplier", "×1")), int(preview.get("projected_score", 0)),
	]
	_invalid_reason.text = str(preview.get("invalid_reason", ""))


func _render_cockpit_preview(fixture_preview: Dictionary) -> void:
	var preview := _score_preview.evaluate(_model, _canonical_staging())
	if preview.is_empty():
		preview = fixture_preview
	var score: Dictionary = preview.get("score_breakdown", {})
	var hand_name := _preview_pattern_name(score, "card_hand", "normal", "No Hand")
	var context_name := _preview_pattern_name(score, "context_hand", "context", "No Context Pattern")
	_score_labels["Hand"].text = hand_name
	_score_labels["Context"].text = context_name
	_set_score_value("Base", str(score.get("base_value", "—")), _base_score_rows(score))
	_set_score_value("Hand", _preview_factor_text(score, "card_hand"), _factor_score_rows(score, "card_hand"))
	_set_score_value("Context", _preview_factor_text(score, "context_hand"), _factor_score_rows(score, "context_hand"))
	_set_score_value("Field", _preview_factor_text(score, "field"), _factor_score_rows(score, "field"))
	_set_score_value("Total", str(score.get("final_score", "—")), _total_score_rows(score, hand_name, context_name))
	_invalid_reason.text = "Submitted · waiting for the other hands" if _hand_is_locked() else str(preview.get("invalid_reason", "")).replace("_", " ")


func _build_score_formula() -> void:
	for key: String in SCORE_COLORS:
		if key != "Base":
			_add_formula_label(Label.new(), "=" if key == "Total" else "×", Color.WHITE)
		if key != "Total":
			var label := Label.new()
			label.name = key + "Name"
			_score_labels[key] = label
			_add_formula_label(label, key, SCORE_COLORS[key])
		var number := ScoreValue.new()
		number.name = key + "Value"
		number.mouse_filter = Control.MOUSE_FILTER_PASS
		_score_values[key] = number
		_add_formula_label(number, "—", SCORE_COLORS[key])


func _add_formula_label(label: Label, text: String, color: Color) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 22)
	if score_font != null:
		label.add_theme_font_override("font", score_font)
	_preview_factors.add_child(label)


func _set_score_value(key: String, text: String, rows: Array) -> void:
	var number: ScoreValue = _score_values[key]
	number.text = text
	number.rows = rows
	number.tooltip_text = "" if rows.is_empty() else key + " contributions"
	number.mouse_default_cursor_shape = Control.CURSOR_ARROW if rows.is_empty() else Control.CURSOR_HELP


func _base_score_rows(score: Dictionary) -> Array:
	if score.is_empty():
		return []
	var rows := [["Selected face", "Points"]]
	for face: Dictionary in score.get("base_components", []):
		var rank := str(face.get("rank", 0))
		var name := "Joker" if bool(face.get("joker", false)) else "Rank " + rank
		rows.append(["%s · %s" % [name, GameTypes.suit_name(int(face.get("suit", -1)))], rank])
	rows.append(["Base", str(score.get("base_value", 0))])
	return rows


func _preview_factor_text(score: Dictionary, factor_id: String) -> String:
	return "—" if score.is_empty() else _rational_text(score.get(factor_id + "_factor", {}))


func _preview_pattern_name(score: Dictionary, factor_id: String, group: String, empty_name: String) -> String:
	var names := PackedStringArray()
	for component: Dictionary in score.get(factor_id + "_components", []):
		var source_id := str(component.get("source_definition_id", component.get("category_id", "")))
		names.append(_hand_score_name(source_id, group, true))
	return empty_name if names.is_empty() else " + ".join(names)


func _factor_score_rows(score: Dictionary, factor_id: String) -> Array:
	if score.is_empty():
		return []
	var field := factor_id == "field"
	var group := "context" if factor_id == "context_hand" else "normal"
	var rows := [["Effect" if field else "Component", "Contribution"]]
	if field:
		rows.append(["Starting factor", "1"])
	for component: Dictionary in score.get(factor_id + "_components", []):
		var source_id := str(component.get("source_definition_id", component.get("category_id", "")))
		var name := _ability_score_name(source_id) if field else _hand_score_name(source_id, group)
		var value: Dictionary = component.get("value", {})
		rows.append([name, _signed_rational_text(value) if field else _rational_text(value)])
	for modifier: Dictionary in score.get("applied_modifiers", []):
		if str(modifier.get("factor_id", "")) != factor_id:
			continue
		var source_id := str(modifier.get("source_definition_id", modifier.get("category_id", "")))
		rows.append([_ability_score_name(source_id), _signed_rational_text(modifier.get("delta", {}))])
	if rows.size() == 1:
		rows.append(["No matching pattern", "1"])
	else:
		var unclamped: Dictionary = score.get(factor_id + "_unclamped", {})
		if _rational_less_than_one(unclamped):
			var denominator := int(unclamped.denominator)
			var adjustment := Rational.new(denominator - int(unclamped.numerator), denominator)
			rows.append(["Minimum factor", _signed_rational_text({
				"numerator": adjustment.numerator, "denominator": adjustment.denominator,
			})])
	rows.append(["Factor", _preview_factor_text(score, factor_id)])
	return rows


func _ability_score_name(source_id: String) -> String:
	var ability: Dictionary = _model.get("ability_catalog", {}).get(source_id, {})
	return str(ability.get("display_name", source_id.capitalize()))


func _hand_score_name(source_id: String, group: String, compact := false) -> String:
	for definition: Dictionary in _model.get("scoring_catalog", {}).get(group, []):
		if str(definition.get("id", "")) == source_id:
			var full_name := str(definition.get("display_name", source_id.capitalize()))
			if compact:
				return str(definition.get("short_display_name", full_name))
			var requirements := str(definition.get("requirements_text", ""))
			return full_name if requirements.is_empty() else "%s (%s)" % [full_name, requirements]
	return source_id.capitalize()


func _total_score_rows(score: Dictionary, hand_name: String, context_name: String) -> Array:
	if score.is_empty():
		return []
	var rows := [
		["Component", "Value"],
		["Base", str(score.get("base_value", 0))],
		[hand_name, _preview_factor_text(score, "card_hand")],
		[context_name, _preview_factor_text(score, "context_hand")],
		["Field", _preview_factor_text(score, "field")],
	]
	if score.has("raw_score"):
		rows.append(["Exact product", _rational_text(score.raw_score)])
	rows.append(["Score (rounded up)", str(score.get("final_score", 0))])
	return rows


func _factor_breakdown_text(breakdown: Dictionary) -> String:
	return "Base %d\nCard %s\nContext %s\nField %s\nprojected %d" % [
		int(breakdown.get("base_value", 0)), _factor_summary(breakdown, "card_hand"),
		_factor_summary(breakdown, "context_hand"), _factor_summary(breakdown, "field"),
		int(breakdown.get("final_score", 0)),
	]


func _factor_summary(breakdown: Dictionary, factor_id: String) -> String:
	var terms: Array[String] = []
	for component in breakdown.get(factor_id + "_components", []):
		terms.append("%s %s" % [str(component.get("category_id", "")).replace("_", " ").capitalize(),
			_rational_text(component.get("value", {}))])
	for modifier in breakdown.get("applied_modifiers", []):
		if str(modifier.get("factor_id", "")) != factor_id: continue
		terms.append("%s %s" % [str(modifier.get("category_id", "")).replace("_", " ").capitalize(),
			_signed_rational_text(modifier.get("delta", {}))])
	if terms.is_empty(): terms.append("neutral")
	var unclamped: Dictionary = breakdown.get(factor_id + "_unclamped", {})
	var factor: Dictionary = breakdown.get(factor_id + "_factor", {})
	var floor_text := " (floor 1)" if _rational_less_than_one(unclamped) else ""
	return "[%s] = %s%s" % [" + ".join(terms), _rational_text(factor), floor_text]


func _rational_text(value: Dictionary) -> String:
	var numerator := int(value.get("numerator", 1))
	var denominator := int(value.get("denominator", 1))
	return str(numerator) if denominator == 1 else "%d/%d" % [numerator, denominator]


func _signed_rational_text(value: Dictionary) -> String:
	var text := _rational_text(value)
	return "+%s" % text if int(value.get("numerator", 0)) >= 0 else text


func _rational_less_than_one(value: Dictionary) -> bool:
	return int(value.get("numerator", 1)) < int(value.get("denominator", 1))


func _render_end() -> void:
	for child in _ability_choices.get_children():
		_ability_choices.remove_child(child)
		child.queue_free()
	var required := _required_ability_discards()
	_ability_choices.visible = required > 0
	_end_confirm.visible = required > 0
	if required == 0:
		_ability_discards.clear()
		_update_end_button()
		return
	var abilities: Array = _model.get("private_abilities", [])
	for ability in abilities:
		if not ability is Dictionary:
			continue
		var copy_id := StringName(ability.get("copy_id", ""))
		var choice := CheckButton.new()
		choice.text = str(ability.get("ability_id", "Ability")).capitalize()
		choice.set_meta("copy_id", copy_id)
		choice.toggled.connect(func(selected: bool): toggle_ability_discard(copy_id, selected))
		_ability_choices.add_child(choice)
	_update_end_button()


func _update_start_total() -> void:
	if not is_node_ready():
		return
	var total := _start_selected_count()
	var locked := _input_locked or _start_ready_requested or _ready_on_host
	var minimum := maxi(0, _required_halves - CardFactory.CONTEXT_DRAW_CAP * (_start_counts.size() - 1))
	for context in _start_counts:
		var selected: int = _start_counts[context]
		var available := _required_halves - (total - selected)
		var keys: Array = _start_keys[context]
		for index in keys.size():
			var button: Button = keys[index]
			var amount := index + 1
			button.set_pressed_no_signal(amount == selected)
			button.disabled = locked or amount < minimum or amount > available
			button.tooltip_text = (
				"Clear %s selection" % GameTypes.context_name(context) if amount == selected else
				"Draw %d from %s" % [amount, GameTypes.context_name(context)]
			)
	var count_format := "%d / %d half-cards selected" if not _start_piles.is_empty() else "%d / %d selected"
	_start_total.text = count_format % [total, _required_halves]
	_start_ready.disabled = locked or total != _required_halves
	if _start_ready_requested and _pending.has(&"set_replenishment_request"):
		_start_ready.text = "SAVING SELECTION…"
	elif _start_ready_requested or _ready_on_host:
		_start_ready.text = "WAITING FOR PLAYERS…"
	else:
		_start_ready.text = "READY FOR MAIN 1"


func _start_selected_count() -> int:
	return int(_start_counts[0]) + int(_start_counts[1]) + int(_start_counts[2])


func _update_end_button() -> void:
	var required := _required_ability_discards()
	var count := _ability_discards.size()
	var locked := _discard_inputs_locked()
	_end_confirm.disabled = locked or required <= 0 or count != required
	if required <= 0 or _discard_acknowledged:
		_end_required.text = "Waiting for other players to discard…"
	elif _pending.has(&"choose_ability_discards"):
		_end_required.text = "Confirming discard…"
	else:
		_end_required.text = "Choose %d to discard" % required
	for choice: BaseButton in _ability_choices.get_children():
		var selected: bool = choice.get_meta("copy_id") in _ability_discards
		choice.set_pressed_no_signal(selected)
		choice.disabled = locked or (not selected and count >= required)


func _discard_inputs_locked() -> bool:
	return _input_locked or _discard_acknowledged or _pending.has(&"choose_ability_discards")


func _required_ability_discards() -> int:
	return int(_model.get(
		"required_ability_discards",
		maxi(_model.get("private_abilities", []).size() - AbilityDeckState.DEFAULT_END_HAND_LIMIT, 0)
	))


func _refresh_buttons() -> void:
	if _phase == PHASE_HAND_PLAY:
		_submit_button.text = "PASS" if _staged_order.is_empty() else "SUBMIT HAND"
		var invalid_top: bool = table_cockpit and _staged_order.any(func(id: StringName) -> bool:
			return not _half_index_is_eligible(_hand_cards[id], _top_half(id))
		)
		_submit_button.disabled = (
			_input_locked or _hand_is_locked() or _hand_command_pending() or _ability_focus_held or _targeting
			or invalid_top
		)
	elif _phase == PHASE_START:
		_update_start_total()
	elif _phase in [PHASE_MAIN_1, PHASE_MAIN_2]:
		_main_ready.disabled = (
			_input_locked or _ability_focus_held or _pending.has(&"set_ready") or _ready_on_host
		)
		_main_ready.text = "READY"
		if _ready_on_host:
			var waiting: bool = _model.get("players", []).any(func(player: Dictionary) -> bool:
				return (
					bool(player.get("active", false)) and not bool(player.get("pending", false))
					and not bool(player.get("ready", false))
				)
			)
			_main_ready.text = (
				"REVIEWING SUBMISSIONS…" if _phase == PHASE_MAIN_2 and not waiting else "WAITING FOR PLAYERS…"
			)
	elif _phase == PHASE_END:
		_update_end_button()


func _on_start_number_pressed(context: int, amount: int) -> void:
	if _phase != PHASE_START or _start_keys[context][amount - 1].disabled:
		return
	_start_counts[context] = 0 if _start_counts[context] == amount else amount
	_advance_start_request()
	_update_start_total()


func _advance_start_request() -> void:
	# Keep one save in flight and use its acknowledgement to process the latest split.
	if _input_locked or _ready_on_host or _pending.has(&"set_replenishment_request"):
		return
	if _start_selected_count() != _required_halves:
		return
	if _required_halves > 0 and _start_counts != _confirmed_start_request:
		_last_start_request = _start_counts.duplicate()
		_emit_intent(&"set_replenishment_request", {"request": _last_start_request})
	elif _start_ready_requested:
		_emit_intent(&"set_ready", {"ready": true})


func _on_ready_pressed() -> void:
	_request_ready()


func _request_ready() -> bool:
	if _phase == PHASE_START and _start_ready.is_visible_in_tree() and not _start_ready.disabled:
		_start_ready_requested = true
		_advance_start_request()
		_update_start_total()
		return true
	if (
		_phase in [PHASE_MAIN_1, PHASE_MAIN_2] and _main_ready.is_visible_in_tree()
		and not _main_ready.disabled
	):
		_emit_intent(&"set_ready", {"ready": true})
		return true
	return false


func _on_submit_pressed() -> void:
	if _phase != PHASE_HAND_PLAY or _submit_button.disabled:
		return
	_after_stage_action = &"lock"
	_emit_intent(&"stage_hand", {"cards": _canonical_staging()})


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
	if card.has("eligible_half_indexes"):
		return not card.eligible_half_indexes.is_empty()
	return _half_is_eligible(card.get("first", {})) or _half_is_eligible(card.get("second", {}))


func _half_index_is_eligible(card: Dictionary, half_index: int) -> bool:
	if card.has("eligible_half_indexes"):
		return half_index in card.eligible_half_indexes
	return _half_is_eligible(_card_half(card, half_index))


func _half_is_eligible(half: Dictionary) -> bool:
	return (
		int(half.get("kind", 0)) == 1
		or int(half.get("effective_context", -1)) in _active_contexts()
	)


func _active_contexts() -> Array:
	var result: Array = _model.get("active_contexts", [])
	if result.is_empty():
		result = [int(_model.get("active_context", 0))]
	return result


func _card_half(card: Dictionary, half_index: int) -> Dictionary:
	return card.get("first", {}) if half_index == 0 else card.get("second", {})


func _default_half_index(card: Dictionary) -> int:
	return 0 if _half_index_is_eligible(card, 0) else 1


func _default_half_index_for_card(card_id: StringName) -> int:
	var card: Dictionary = _hand_cards.get(card_id, {})
	if bool(_orientations.get(card_id, false)) and _half_index_is_eligible(card, 1):
		return 1
	return _default_half_index(card)


func _default_joker_choices(card: Dictionary, previous_choices: Array = []) -> Array:
	var choices: Array = []
	for half_index in 2:
		var half := _card_half(card, half_index)
		if int(half.get("kind", 0)) != GameTypes.HalfKind.JOKER:
			continue
		var choice := {"half_index": half_index, "context": 0, "suit": 0}
		for previous: Dictionary in previous_choices:
			if int(previous.get("half_index", -1)) == half_index:
				choice = previous
				break
		if half.has("joker_suit"):
			choice = {"half_index": half_index, "context": half.joker_context, "suit": half.joker_suit}
		choices.append(choice)
	return choices
