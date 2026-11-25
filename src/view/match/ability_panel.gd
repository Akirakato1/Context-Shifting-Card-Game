class_name AbilityPanel
extends Control

signal ability_activated(copy_id: StringName, ability: Dictionary)
signal ability_primed(copy_id: StringName, ability: Dictionary)
signal ability_cancel_requested
signal interaction_sound(cue: StringName)
signal discards_confirmed(copy_ids: Array[String])

const AbilityCard = preload("res://src/view/match/ability_card.gd")
const AbilityCardScene = preload("res://src/view/match/ability_inventory_card.tscn")
const GameTypes := preload("res://src/core/common/game_types.gd")
const MatchButtonArt := preload("res://src/view/match/match_button_art.gd")
const DETAILS_EYE := preload("res://assets/artwork/svg/ability_details_eye.svg")
const DETAILS_EYE_HIDDEN := preload("res://assets/artwork/svg/ability_details_eye_hidden.svg")
const CARD_SEPARATION := 7.0
const DRAG_THRESHOLD := 7.0
const REORDER_DURATION := 0.14

var _abilities: Dictionary = {}
var _legal_ids: Array[StringName] = []
var _order: Array[StringName] = []
var _cards_by_id: Dictionary[StringName, AbilityCard] = {}
var _detail_overrides: Dictionary[StringName, bool] = {}
var _show_all_details := false
var _pending_draws: Dictionary[StringName, bool] = {}
var _card_targets: Dictionary[StringName, Vector2] = {}
var _card_tweens: Dictionary[StringName, Tween] = {}
var _expanded := false
var _target_behind_drawer := false
var _input_locked := false
var _focused_id: StringName
var _activating_id: StringName
var _pressed_id: StringName
var _press_position := Vector2.ZERO
var _grab_offset := Vector2.ZERO
var _drag_order: Array[StringName] = []
var _kept_ids: Array[StringName] = []
var _keep_limit := 0
var _discarding := false
var _discard_pending := false
var _expanded_before_discard := false

@onready var _drawer: PanelContainer = $Drawer
@onready var _discard_prompt: Label = $Drawer/Layout/DiscardPrompt
@onready var _scroll: ScrollContainer = $Drawer/Layout/Scroll
@onready var _cards: Control = $Drawer/Layout/Scroll/Cards
@onready var _drag_overlay: Control = $DragOverlay
@onready var _toggle: Button = $ToggleButton
@onready var _details_mode: Button = $DetailsMode
@onready var _confirm_keep: Button = $Drawer/Layout/ConfirmKeep


func _ready() -> void:
	_drawer.add_theme_stylebox_override("panel", _drawer.get_theme_stylebox("panel").duplicate())
	MatchButtonArt.skin(_toggle, MatchButtonArt.PILL)
	MatchButtonArt.skin(_details_mode, MatchButtonArt.ROUND)
	MatchButtonArt.skin(_confirm_keep, MatchButtonArt.ACTION)
	_details_mode.add_theme_constant_override("icon_max_width", 24)
	_cards.resized.connect(_layout_cards)
	visibility_changed.connect(_on_visibility_changed)
	_confirm_keep.pressed.connect(_on_confirm_keep_pressed)
	_details_mode.toggled.connect(_set_all_details)


func _exit_tree() -> void:
	if not _drag_order.is_empty():
		_set_drag_cursor(false)


func set_drawer_bounds(bounds: Rect2) -> void:
	var frame := _drawer.get_theme_stylebox("panel")
	frame.content_margin_left = bounds.size.x * 0.068
	frame.content_margin_right = bounds.size.x * 0.068
	frame.content_margin_top = bounds.size.y * 0.070
	frame.content_margin_bottom = bounds.size.y * 0.024
	_drawer.position = bounds.position
	_drawer.size = bounds.size


func render(abilities: Array, phase: int, catalog: Dictionary, input_locked: bool, required_discards := 0) -> void:
	var models: Dictionary = {}
	var snapshot_order: Array[StringName] = []
	if input_locked and not _input_locked:
		_discard_pending = false
	_input_locked = input_locked
	_legal_ids.clear()
	for ability_ref in abilities:
		if not ability_ref is Dictionary:
			continue
		var copy_id := StringName(ability_ref.get("copy_id", ""))
		if copy_id.is_empty() or models.has(copy_id):
			continue
		var ability_id := str(ability_ref.get("ability_id", ""))
		var definition: Dictionary = catalog.get(ability_id, {})
		var model: Dictionary = ability_ref.duplicate(true)
		model.merge(definition, true)
		models[copy_id] = model
		snapshot_order.append(copy_id)
		var legal := bool(model.get("legal", _timing_allows(int(model.get("timing", -1)), phase)))
		if legal:
			_legal_ids.append(copy_id)

	var inventory_changed := models.size() != _order.size()
	for copy_id in snapshot_order:
		if not _cards_by_id.has(copy_id):
			inventory_changed = true
			break
	if _input_locked or inventory_changed or required_discards > 0:
		_finish_drag(false)
	if _input_locked or required_discards > 0 or _focused_id not in _legal_ids:
		_set_focused_id(&"")

	_abilities = models
	_set_discard_requirement(required_discards)
	for copy_id in _order.duplicate():
		if not _abilities.has(copy_id):
			var card := _cards_by_id[copy_id]
			_stop_card_tween(copy_id)
			_cards.remove_child(card)
			card.queue_free()
			_cards_by_id.erase(copy_id)
			_detail_overrides.erase(copy_id)
			_card_targets.erase(copy_id)
			_order.erase(copy_id)
	for copy_id in snapshot_order:
		if not _cards_by_id.has(copy_id):
			var card := AbilityCardScene.instantiate() as AbilityCard
			_cards.add_child(card)
			card.gui_input.connect(_on_ability_gui_input.bind(card, copy_id))
			card.card_hovered.connect(func(): interaction_sound.emit(&"hover"))
			card.minimum_size_changed.connect(_layout_cards, CONNECT_DEFERRED)
			_cards_by_id[copy_id] = card
			_order.append(copy_id)
			_add_detail_button(card, copy_id)
		var card := _cards_by_id[copy_id]
		var model: Dictionary = _abilities[copy_id]
		var playable := _can_play(copy_id)
		card.render(model, str(model.get("ability_id", "")), false, _discarding or playable)
		card.set_inventory_playable_highlight(playable and phase == GameTypes.Phase.MAIN_1)
		_update_card_details(copy_id)
		_update_draw_presentation(copy_id)
	_update_toggle()
	_update_discard_controls()
	_layout_cards()


func open_drawer() -> void:
	if _expanded or _abilities.is_empty():
		return
	_expanded = true
	_update_toggle()


func set_target_behind_drawer(behind_drawer: bool) -> void:
	if _target_behind_drawer == behind_drawer:
		return
	_target_behind_drawer = behind_drawer
	_update_toggle()


func legal_ability_ids() -> Array[StringName]:
	return _legal_ids.duplicate()


func inputs_locked() -> bool:
	return _input_locked


func draw_destination(copy_id: StringName) -> Control:
	var card: Control = _cards_by_id.get(copy_id)
	if _expanded and card != null and card.is_visible_in_tree() and card.size.x > 0 and card.size.y > 0:
		var center := card.get_global_transform_with_canvas() * (card.size * 0.5)
		if _contains_pointer(_scroll, center) and get_viewport_rect().has_point(center):
			return card
	return _toggle if _toggle.is_visible_in_tree() else null


func set_draw_pending(copy_id: StringName, pending: bool) -> void:
	if pending:
		_pending_draws[copy_id] = true
		if _pressed_id == copy_id:
			_finish_drag(false)
		if _focused_id == copy_id:
			_set_focused_id(&"")
	else:
		_pending_draws.erase(copy_id)
	_update_draw_presentation(copy_id)


func _add_detail_button(card: AbilityCard, copy_id: StringName) -> void:
	var button := Button.new()
	button.name = "DetailsButton"
	button.toggle_mode = true
	MatchButtonArt.skin(button, MatchButtonArt.ROUND)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_constant_override("icon_max_width", 19)
	card.get_node("Face").add_child(button)
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.offset_left = -42.0
	button.offset_right = -6.0
	button.toggled.connect(_set_card_details.bind(copy_id))


func _set_card_details(enabled: bool, copy_id: StringName) -> void:
	_finish_drag(false)
	_detail_overrides[copy_id] = enabled
	_update_card_details(copy_id)
	_layout_cards()
	if enabled:
		_scroll_to_card.call_deferred(copy_id)


func _scroll_to_card(copy_id: StringName) -> void:
	if _cards_by_id.has(copy_id):
		_scroll.ensure_control_visible(_cards_by_id[copy_id])


func _set_all_details(enabled: bool) -> void:
	_finish_drag(false)
	_show_all_details = enabled
	_detail_overrides.clear()
	for copy_id in _order:
		_update_card_details(copy_id)
	if enabled and not _abilities.is_empty():
		_expanded = true
	_details_mode.icon = DETAILS_EYE_HIDDEN if enabled else DETAILS_EYE
	_details_mode.tooltip_text = "Hide all ability descriptions" if enabled else "Show all ability descriptions"
	_update_toggle()
	_layout_cards()


func _shows_details(copy_id: StringName) -> bool:
	return _detail_overrides.get(copy_id, _show_all_details)


func _update_card_details(copy_id: StringName) -> void:
	var card := _cards_by_id[copy_id]
	var enabled := _shows_details(copy_id)
	card.set_tray_details(enabled)
	var button: Button = card.get_node("Face/DetailsButton")
	button.set_pressed_no_signal(enabled)
	button.icon = DETAILS_EYE_HIDDEN if enabled else DETAILS_EYE
	button.tooltip_text = "Hide ability description" if enabled else "Show ability description"
	button.anchor_top = 0.0 if enabled else 0.5
	button.anchor_bottom = button.anchor_top
	button.offset_top = 5.0 if enabled else -18.0
	button.offset_bottom = button.offset_top + 36.0


func clear_pending_draws() -> void:
	var pending_ids := _pending_draws.keys()
	_pending_draws.clear()
	for copy_id in pending_ids:
		_update_draw_presentation(copy_id)


func _update_draw_presentation(copy_id: StringName) -> void:
	var card: Control = _cards_by_id.get(copy_id)
	if card == null:
		return
	var pending := _pending_draws.has(copy_id)
	card.modulate.a = 0.0 if pending else 1.0
	card.get_node("Face/DetailsButton").disabled = pending
	var ignore_input := pending or _input_locked or card.get_parent() == _drag_overlay
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE if ignore_input else Control.MOUSE_FILTER_PASS


func activate_ability(copy_id: StringName) -> void:
	if not _pending_draws.has(copy_id) and _can_play(copy_id):
		_set_focused_id(&"", false)
		ability_activated.emit(copy_id, _abilities[copy_id].duplicate(true))


func ability_focus_rect(copy_id: StringName) -> Rect2:
	var card: Control = _cards_by_id.get(copy_id)
	if card == null or not card.is_visible_in_tree():
		return Rect2()
	return card.get_global_rect().grow(7).intersection(_scroll.get_global_rect().grow(7))


func discard_focus_rect() -> Rect2:
	return _drawer.get_global_rect() if _discarding and not _input_locked and is_visible_in_tree() else Rect2()


func discard_keep_limit() -> int:
	return _keep_limit


func discard_rejected(reason: StringName) -> void:
	if not _discard_pending:
		return
	_discard_pending = false
	_confirm_keep.tooltip_text = "Could not confirm: %s" % str(reason).replace("_", " ")
	interaction_sound.emit(&"invalid")
	_update_discard_controls()


func _set_discard_requirement(required: int) -> void:
	var was_discarding := _discarding
	_discarding = required > 0
	_keep_limit = maxi(_abilities.size() - required, 0)
	if _discarding and not was_discarding:
		_expanded_before_discard = _expanded
		_expanded = true
		_scroll.scroll_vertical = 0
	elif was_discarding and not _discarding:
		for copy_id in _kept_ids:
			if _cards_by_id.has(copy_id):
				_cards_by_id[copy_id].set_inventory_focused(false)
		_kept_ids.clear()
		_discard_pending = false
		_confirm_keep.tooltip_text = ""
		_expanded = _expanded_before_discard
	_kept_ids.assign(_kept_ids.filter(func(copy_id: StringName) -> bool: return _abilities.has(copy_id)))
	if _kept_ids.size() > _keep_limit:
		_kept_ids.resize(_keep_limit)


func _update_discard_controls() -> void:
	_discard_prompt.visible = _discarding
	_confirm_keep.visible = _discarding
	if not _discarding:
		return
	_discard_prompt.text = "Select %d cards to keep · %d / %d" % [_keep_limit, _kept_ids.size(), _keep_limit]
	_confirm_keep.disabled = _input_locked or _discard_pending or _kept_ids.size() != _keep_limit
	_confirm_keep.text = "CONFIRM KEEP %d" % _keep_limit
	if _discard_pending:
		_confirm_keep.text = "CONFIRMING…"
	elif not _confirm_keep.tooltip_text.is_empty():
		_confirm_keep.text = "TRY CONFIRMING AGAIN"
	for copy_id in _order:
		var kept := copy_id in _kept_ids
		var card := _cards_by_id[copy_id]
		card.set_inventory_focused(kept)
		var at_limit := not kept and _kept_ids.size() == _keep_limit
		var opacity := card.modulate.a
		card.modulate = Color(0.76, 0.76, 0.76, opacity) if at_limit else Color(1.0, 1.0, 1.0, opacity)


func _toggle_keep(copy_id: StringName) -> void:
	if _discard_pending:
		return
	if copy_id in _kept_ids:
		_kept_ids.erase(copy_id)
	elif _kept_ids.size() < _keep_limit:
		_kept_ids.append(copy_id)
	else:
		interaction_sound.emit(&"invalid")
		return
	_confirm_keep.tooltip_text = ""
	interaction_sound.emit(&"select")
	_update_discard_controls()


func _on_confirm_keep_pressed() -> void:
	if not _discarding or _confirm_keep.disabled:
		return
	var discarded: Array[String] = []
	for copy_id in _order:
		if copy_id not in _kept_ids:
			discarded.append(str(copy_id))
	_confirm_keep.tooltip_text = ""
	_discard_pending = true
	_update_discard_controls()
	discards_confirmed.emit(discarded)


func set_activating_copy(copy_id: StringName) -> void:
	if _cards_by_id.has(_activating_id):
		_cards_by_id[_activating_id].set_inventory_focused(_activating_id == _focused_id)
	_activating_id = copy_id
	if _cards_by_id.has(copy_id):
		_cards_by_id[copy_id].set_inventory_focused(true)


func clear_primed_ability() -> void:
	_set_focused_id(&"")


func _on_toggle_pressed() -> void:
	if _discarding or not _activating_id.is_empty():
		interaction_sound.emit(&"invalid")
		return
	_finish_drag(false)
	_set_focused_id(&"")
	_expanded = not _expanded
	_update_toggle()


func _update_toggle() -> void:
	_drawer.visible = _expanded and (_discarding or not _target_behind_drawer)
	_toggle.text = "ABILITIES  %d  %s" % [_abilities.size(), "▼" if _drawer.visible else "▲"]
	_toggle.disabled = _discarding or (_abilities.is_empty() and not _expanded)
	_details_mode.disabled = _abilities.is_empty()


func _can_play(copy_id: StringName) -> bool:
	return not _input_locked and not _discarding and copy_id in _legal_ids and _abilities.has(copy_id)


func _set_focused_id(copy_id: StringName, notify := true) -> void:
	if _focused_id == copy_id:
		return
	if _cards_by_id.has(_focused_id):
		_cards_by_id[_focused_id].set_inventory_focused(false)
	_focused_id = copy_id
	if _cards_by_id.has(copy_id):
		_cards_by_id[copy_id].set_inventory_focused(true)
	if notify:
		interaction_sound.emit(&"unprime" if copy_id.is_empty() else &"prime")
		ability_primed.emit(copy_id, _abilities.get(copy_id, {}).duplicate(true))


func _on_ability_gui_input(event: InputEvent, card: AbilityCard, copy_id: StringName) -> void:
	if _input_locked or _pending_draws.has(copy_id) or not event is InputEventMouseButton or not event.pressed:
		return
	if _discarding:
		if event.button_index == MOUSE_BUTTON_LEFT:
			card.accept_event()
			_toggle_keep(copy_id)
		return
	if not _activating_id.is_empty():
		if event.button_index == MOUSE_BUTTON_RIGHT and copy_id == _activating_id:
			card.accept_event()
			ability_cancel_requested.emit()
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			card.accept_event()
			interaction_sound.emit(&"invalid")
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		card.accept_event()
		if _pressed_id.is_empty() and _can_play(copy_id):
			var ability: Dictionary = _abilities[copy_id]
			if ability.get("choice_schema", {}).get("steps", []).is_empty():
				_set_focused_id(&"" if _focused_id == copy_id else copy_id)
			else:
				interaction_sound.emit(&"prime")
				activate_ability(copy_id)
		else:
			interaction_sound.emit(&"invalid")
	elif event.button_index == MOUSE_BUTTON_LEFT:
		card.accept_event()
		_pressed_id = copy_id
		_press_position = card.get_global_transform_with_canvas() * event.position


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not _activating_id.is_empty():
			ability_cancel_requested.emit()
			get_viewport().set_input_as_handled()
		elif not _pressed_id.is_empty() or not _focused_id.is_empty():
			_finish_drag(false)
			_set_focused_id(&"")
			get_viewport().set_input_as_handled()
		return
	if _pressed_id.is_empty():
		return
	if event is InputEventMouseMotion:
		if _drag_order.is_empty():
			var local_motion := _drag_overlay.get_global_transform_with_canvas().affine_inverse().basis_xform(
				event.position - _press_position
			)
			if local_motion.length() < DRAG_THRESHOLD:
				return
			_begin_drag()
		_move_drag(event.position)
		_set_drag_cursor(true)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var copy_id := _pressed_id
		var card := _cards_by_id[copy_id]
		var over_scroll := _contains_pointer(_scroll, event.position)
		if not _drag_order.is_empty():
			if over_scroll:
				_move_drag(event.position)
			_finish_drag(over_scroll)
			interaction_sound.emit(&"drop" if over_scroll else &"invalid")
		else:
			_pressed_id = &""
			if over_scroll and _contains_pointer(card, event.position):
				if copy_id == _focused_id:
					activate_ability(copy_id)
				else:
					var idle_click := _focused_id.is_empty() and _can_play(copy_id)
					interaction_sound.emit(&"select" if idle_click else &"invalid")


func _contains_pointer(control: Control, pointer: Vector2) -> bool:
	var local_point := control.get_global_transform_with_canvas().affine_inverse() * pointer
	return Rect2(Vector2.ZERO, control.size).has_point(local_point)


func _begin_drag() -> void:
	var card := _cards_by_id[_pressed_id]
	_set_focused_id(&"")
	_stop_card_tween(_pressed_id)
	_drag_order = _order.duplicate()
	var to_overlay := _drag_overlay.get_global_transform_with_canvas().affine_inverse()
	var card_origin := card.get_global_transform_with_canvas().origin
	_grab_offset = to_overlay * card_origin - to_overlay * _press_position
	card.reparent(_drag_overlay, false)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_sound.emit(&"drag")


func _move_drag(pointer: Vector2) -> void:
	var card := _cards_by_id[_pressed_id]
	card.position = _drag_overlay.get_global_transform_with_canvas().affine_inverse() * pointer + _grab_offset
	var center := card.get_global_transform_with_canvas() * (card.size * 0.5)
	var center_y := (_cards.get_global_transform_with_canvas().affine_inverse() * center).y
	var from_index := _drag_order.find(_pressed_id)
	var to_index := from_index
	while to_index > 0 and center_y < _slot_center(_drag_order[to_index - 1]):
		to_index -= 1
	while to_index < _drag_order.size() - 1 and center_y > _slot_center(_drag_order[to_index + 1]):
		to_index += 1
	if from_index != to_index:
		_drag_order.remove_at(from_index)
		_drag_order.insert(to_index, _pressed_id)
		_layout_cards(true)


func _slot_center(copy_id: StringName) -> float:
	return _card_targets[copy_id].y + _cards_by_id[copy_id].size.y * 0.5


func _finish_drag(commit: bool) -> void:
	var copy_id := _pressed_id
	_pressed_id = &""
	if _drag_order.is_empty():
		return
	_set_drag_cursor(false)
	if commit:
		_order.assign(_drag_order)
	_drag_order.clear()
	var card := _cards_by_id[copy_id]
	var card_origin := card.get_global_transform_with_canvas().origin
	card.reparent(_cards, false)
	card.position = _cards.get_global_transform_with_canvas().affine_inverse() * card_origin
	_update_draw_presentation(copy_id)
	_card_targets.erase(copy_id)
	for index in _order.size():
		_cards.move_child(_cards_by_id[_order[index]], index)
	_layout_cards(true)


func _set_drag_cursor(dragging: bool) -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE):
		# Manual drag events are handled before the viewport can choose a cursor.
		DisplayServer.cursor_set_shape(DisplayServer.CURSOR_DRAG if dragging else DisplayServer.CURSOR_ARROW)


func _layout_cards(animate := false) -> void:
	var layout_order := _order if _drag_order.is_empty() else _drag_order
	var y := 0.0
	var min_width := 0.0
	for copy_id in layout_order:
		var card := _cards_by_id[copy_id]
		var minimum := card.get_combined_minimum_size()
		var width := maxf(_cards.size.x, minimum.x)
		var height := card.tray_height(width, _shows_details(copy_id))
		var target := Vector2(0.0, y)
		y += height + CARD_SEPARATION
		min_width = maxf(min_width, minimum.x)
		var target_changed: bool = _card_targets.get(copy_id, Vector2.INF) != target
		_card_targets[copy_id] = target
		if card.get_parent() == _drag_overlay:
			continue
		card.size = Vector2(width, height)
		if target_changed:
			_stop_card_tween(copy_id)
			if animate and card.position != target:
				var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tween.tween_property(card, "position", target, REORDER_DURATION)
				_card_tweens[copy_id] = tween
			else:
				card.position = target
	_cards.custom_minimum_size = Vector2(min_width, maxf(0.0, y - CARD_SEPARATION))


func _stop_card_tween(copy_id: StringName) -> void:
	if _card_tweens.has(copy_id):
		_card_tweens[copy_id].kill()
		_card_tweens.erase(copy_id)


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_finish_drag(false)
		_set_focused_id(&"")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_finish_drag(false)


func _timing_allows(timing: int, phase: int) -> bool:
	match timing:
		0:
			return phase == 3
		1, 3:
			return phase == 2
		2:
			return phase == 2 or phase == 4
	return false
