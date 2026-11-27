extends Control

const GameIcons := preload("res://src/view/common/game_icons.gd")
const DRAG_THRESHOLD := 7.0
const PANEL_GAP := 15.0
const SCREEN_MARGIN := 8.0

var _model := {}
var _hand_controls: Control
var _page := 0
var _held := false
var _dragging := false
var _press_position := Vector2.ZERO
var _press_origin := Vector2.ZERO
var _bubble_on_right := true
var _bubble_motion: Tween
var _frame_center: Vector2
var _idle_mouth: PackedVector2Array
var _jump_mouth: PackedVector2Array
var _jump_clearance: PackedFloat32Array

@onready var _button: Button = $Ask
@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _shadow: TextureRect = $Shadow
@onready var _panel: PanelContainer = $Bubble
@onready var _title: Label = $Bubble/Content/Title
@onready var _body: RichTextLabel = $Bubble/Content/Body
@onready var _prompt: Label = $Bubble/Content/Prompt


func _ready() -> void:
	_frame_center = _sprite.sprite_frames.get_frame_texture(&"idle", 0).get_size() * 0.5
	_idle_mouth = _sprite.sprite_frames.get_meta(&"idle_mouth")
	_jump_mouth = _sprite.sprite_frames.get_meta(&"jump_mouth")
	_jump_clearance = _sprite.sprite_frames.get_meta(&"jump_clearance")
	_button.pressed.connect(_on_ask)
	_sprite.frame_changed.connect(_on_sprite_frame_changed)
	_sprite.animation_finished.connect(_sprite.play.bind(&"idle"))
	_panel.resized.connect(_place_bubble)
	get_parent().resized.connect(_keep_on_screen)


func set_body_font(font: Font) -> void:
	_body.add_theme_font_override("normal_font", font)
	_title.add_theme_font_override("font", font)
	_prompt.add_theme_font_override("font", font)


func render(model: Dictionary, hand_controls: Control) -> void:
	var new_phase: bool = _model.get("phase") != model.get("phase") or _model.get("round_number") != model.get("round_number")
	_model = model
	_hand_controls = hand_controls
	visible = bool(model.get("is_practice", false))
	if new_phase or not visible:
		_page = 0
	if visible and not _sprite.is_playing():
		_sprite.play(&"idle")
	elif not visible:
		_release_pointer()
		_sprite.stop()
	refresh_bubble()


func refresh_bubble() -> void:
	_panel.visible = visible and _page != 0
	queue_redraw()
	if not _panel.visible:
		return
	var hint: Dictionary = _model.get("practice_hint", {})
	var plan: Dictionary = hint.get("plan", {})
	_body.custom_minimum_size.y = 120.0 if _page == 1 or plan.is_empty() else 250.0
	if int(_model.get("phase", -1)) != GameTypes.Phase.HAND_PLAY:
		_title.text = "Ask me during Hand Play"
		GameIcons.write(_body, "I can find your best guaranteed hand when it’s time to play cards.")
		_prompt.text = "Click Zetty again to close."
	else:
		_show_hint(hint, plan)
	_panel.reset_size()
	_place_bubble()


func _show_hint(hint: Dictionary, plan: Dictionary) -> void:
	match hint.get("status", ""):
		"calculating", "":
			_title.text = "Still calculating…"
			GameIcons.write(_body, "I’m checking your hand and the abilities you can use this round.")
			_prompt.text = "The hint will appear here when it’s ready."
		"ready":
			_show_plan(plan)
		_:
			_title.text = "Hint unavailable"
			GameIcons.write(_body, "I couldn’t calculate a hint for this hand.")
			_prompt.text = "Click Zetty again to close."


func _on_ask() -> void:
	if not is_visible_in_tree():
		return
	var opening := _page == 0
	if _page == 0:
		_page = 1
	elif _page == 1 and _model.get("practice_hint", {}).get("status", "") == "ready":
		_page = 2
	else:
		_page = 0
	_sprite.stop()
	_sprite.play(&"jump")
	refresh_bubble()
	if _bubble_motion != null:
		_bubble_motion.kill()
	_animate_bubble(0.0 if opening else 1.0)
	if opening:
		_bubble_motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_bubble_motion.tween_method(_animate_bubble, 0.0, 1.0, 0.18)


func _has_point(point: Vector2) -> bool:
	var hit := _button.get_rect()
	var top := minf(hit.position.y, _mouth_position().y - 27.0)
	hit = Rect2(Vector2(hit.position.x, top), Vector2(hit.size.x, hit.end.y - top))
	return hit.has_point(point)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_held = true
		_press_origin = position
		_press_position = position + event.position
		accept_event()


func _input(event: InputEvent) -> void:
	if not _held:
		return
	if event is InputEventMouseMotion:
		var parent: Control = get_parent()
		var delta: Vector2 = parent.get_global_transform_with_canvas().affine_inverse() * event.position - _press_position
		if not _dragging and delta.length() >= DRAG_THRESHOLD:
			_dragging = true
			mouse_default_cursor_shape = Control.CURSOR_DRAG
		if _dragging:
			position = _press_origin + delta
			_keep_on_screen()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var local_point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		var clicked := not _dragging and _has_point(local_point)
		_release_pointer()
		if clicked:
			_on_ask()
	else:
		return
	get_viewport().set_input_as_handled()


func _release_pointer() -> void:
	_held = false
	_dragging = false
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_pointer()


func _keep_on_screen() -> void:
	position = position.clamp(Vector2.ZERO, (get_parent_area_size() - size).max(Vector2.ZERO))
	_place_bubble()


func _place_bubble() -> void:
	var available := get_parent_area_size()
	var right_x := position.x + size.x + PANEL_GAP
	var left_x := position.x - _panel.size.x - PANEL_GAP
	_bubble_on_right = right_x + _panel.size.x <= available.x - SCREEN_MARGIN or left_x < SCREEN_MARGIN
	_sprite.flip_h = not _bubble_on_right
	var aim_y := position.y + _sprite.position.y + (_idle_mouth[0].y - _frame_center.y) * _sprite.scale.y
	var limit := (available - _panel.size - Vector2.ONE * SCREEN_MARGIN).max(Vector2.ONE * SCREEN_MARGIN)
	_panel.position = Vector2(right_x if _bubble_on_right else left_x, aim_y - 38.0).clamp(
		Vector2.ONE * SCREEN_MARGIN, limit
	) - position
	_panel.pivot_offset = Vector2(0 if _bubble_on_right else _panel.size.x, clampf(aim_y - position.y - _panel.position.y, 0.0, _panel.size.y))
	queue_redraw()


func _mouth_position() -> Vector2:
	var mouths := _jump_mouth if _sprite.animation == &"jump" else _idle_mouth
	var offset := mouths[_sprite.frame] - _frame_center
	if _sprite.flip_h:
		offset.x = -offset.x
	return _sprite.position + _sprite.scale * offset


func _on_sprite_frame_changed() -> void:
	var height := _jump_clearance[_sprite.frame] if _sprite.animation == &"jump" else 0.0
	_shadow.scale = Vector2.ONE.lerp(Vector2(0.67, 0.75), height)
	_shadow.modulate.a = lerpf(1.0, 0.50, height)
	if _panel.visible:
		queue_redraw()


func _animate_bubble(progress: float) -> void:
	_panel.modulate.a = progress
	_panel.scale = Vector2.ONE * lerpf(0.84, 1.0, progress)
	queue_redraw()


func _draw() -> void:
	if not _panel.visible:
		return
	var mouth := _mouth_position()
	var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	var edge := _panel.get_transform()
	var center := clampf((edge.affine_inverse() * mouth).y, 23.0, _panel.size.y - 23.0)
	var x := 1.0 if _bubble_on_right else _panel.size.x - 1.0
	var top := edge * Vector2(x, center - 9.0)
	var bottom := edge * Vector2(x, center + 9.0)
	var fade := Color(1, 1, 1, _panel.modulate.a)
	draw_colored_polygon(PackedVector2Array([top, mouth, bottom]), style.bg_color * fade)
	draw_polyline(PackedVector2Array([top, mouth, bottom]), style.border_color * fade, 1.0, true)


func _show_plan(plan: Dictionary) -> void:
	if _page == 1:
		_title.text = "Best guaranteed hand  ·  %d points" % int(plan.get("score", 0))
		var faces: Array = plan.get("faces", [])
		var names := PackedStringArray()
		for key in ["hand", "context"]:
			var label := _category_label(plan, key)
			if not label.is_empty():
				names.append(label)
		var message := "Pass this hand." if faces.is_empty() else " + ".join(names)
		if not faces.is_empty():
			message += "\n" + _staging_instruction(faces)
		message += "\nThe estimate assumes no new opponent effects."
		GameIcons.write(_body, message)
		_prompt.text = "Click Zetty again for the play sequence."
	else:
		_title.text = "Play sequence"
		GameIcons.write(_body, _play_sequence(plan))
		_prompt.text = "Click Zetty again to close."
	_body.scroll_to_line(0)


func _category_label(plan: Dictionary, kind: String) -> String:
	var id := str(plan.get(kind + "_type", ""))
	if id.is_empty() or id == "no_context":
		return ""
	var catalog: Dictionary = _model.get("scoring_catalog", {})
	for entry: Dictionary in catalog.get("normal" if kind == "hand" else "context", []):
		if str(entry.get("id", "")) == id:
			return str(entry.get("display_name", id.capitalize()))
	return id.capitalize()


func _play_sequence(plan: Dictionary) -> String:
	var actions := PackedStringArray()
	if bool(plan.get("cancel_pending_manipulation", false)):
		actions.append("Cancel the ability you have open.")
	for play: Dictionary in plan.get("hand_play", []):
		var action := "Play %s." % _ability_name(play.copy_id)
		var choices := _describe_choices(play.choices)
		if not choices.is_empty():
			action += " " + choices
		actions.append(action)
	var handled_flips: Array[StringName] = []
	for selection: Dictionary in plan.get("submission", []):
		var slot := _card_slots([selection.card_id])
		if slot.is_empty():
			continue
		var jokers: Array = selection.get("joker_choices", [])
		if jokers.is_empty():
			continue
		for joker: Dictionary in jokers:
			if joker.half_index == selection.half_index:
				actions.append(_joker_instruction(joker, _half_position(selection.card_id, joker.half_index), slot))
		var card_id := StringName(selection.card_id)
		if _hand_controls._top_half(card_id) != int(selection.half_index):
			actions.append("Flip card %s." % slot)
			handled_flips.append(card_id)
		for joker: Dictionary in jokers:
			if joker.half_index != selection.half_index:
				actions.append(_joker_instruction(joker, "bottom half", slot))
	var faces: Array = plan.get("faces", [])
	if faces.is_empty():
		actions.append("Clear any staged cards and press Pass.")
	else:
		actions.append(_staging_instruction(faces, handled_flips))
		actions.append("Press Submit Hand.")
	for play: Dictionary in plan.get("main_2", []):
		actions.append("In Main Phase 2, right-click %s and click your side of the table." % _ability_name(play.copy_id))
	var lines := PackedStringArray()
	if not plan.get("hand_play", []).is_empty():
		lines.append("Right-click a Manipulation card, then choose its targets. Press Activate if it appears.")
	for index in actions.size():
		lines.append("%d. %s" % [index + 1, actions[index]])
	return "\n".join(lines)


func _describe_choices(choices: Dictionary) -> String:
	var card_ids: Array = choices.get("cards", []).duplicate()
	var halves: Array = choices.get("halves", []).duplicate()
	var half_indices: Array = choices.get("half_index", [])
	if not card_ids.is_empty() and not half_indices.is_empty():
		halves.append({"card_id": card_ids[0], "half_index": half_indices[0]})
	var top_ids: Array = []
	var bottom_ids: Array = []
	for half: Dictionary in halves:
		card_ids.append(half.card_id)
		var targets := top_ids if _half_position(half.card_id, half.half_index) == "top half" else bottom_ids
		targets.append(half.card_id)
	var instructions := PackedStringArray()
	var slots := _card_slots(card_ids)
	if not slots.is_empty():
		instructions.append("Select cards %s." % slots)
	var targets := PackedStringArray()
	var top_slots := _card_slots(top_ids)
	var bottom_slots := _card_slots(bottom_ids)
	if not top_slots.is_empty():
		targets.append("the top half for %s" % top_slots)
	if not bottom_slots.is_empty():
		targets.append("the bottom half for %s" % bottom_slots)
	if not targets.is_empty():
		instructions.append("Use %s." % " and ".join(targets))
	for suit in choices.get("suit", []):
		instructions.append("Choose %s as the suit." % GameTypes.suit_name(int(suit)))
	for context in choices.get("context", []):
		instructions.append("Choose %s as the context." % GameTypes.context_name(int(context)))
	for rank in choices.get("rank", []):
		instructions.append("Choose rank %d." % int(rank))
	return " ".join(instructions)


func _joker_instruction(joker: Dictionary, position: String, slot: String) -> String:
	var rank := "rank %d" % int(joker.rank) if int(joker.rank) > 0 else "no rank"
	return "Set the Joker on the %s of card %s to %s, suit %s, and context %s." % [
		position, slot, rank, GameTypes.suit_name(int(joker.suit)), GameTypes.context_name(int(joker.context)),
	]


func _staging_instruction(faces: Array, handled_flips: Array[StringName] = []) -> String:
	var card_ids: Array = []
	var flip_ids: Array = []
	for face: Dictionary in faces:
		card_ids.append(face.card_id)
		var card_id := StringName(face.card_id)
		if card_id not in handled_flips and _hand_controls._top_half(card_id) != int(face.selected_half_index):
			flip_ids.append(face.card_id)
	var flip_slots := _card_slots(flip_ids)
	var flip_text := "Flip cards %s before staging. " % flip_slots if not flip_slots.is_empty() else ""
	return "%sSelect cards %s to stage, counting from the left." % [flip_text, _card_slots(card_ids)]


func _card_slots(card_ids: Array) -> String:
	var order: Array[StringName] = _hand_controls.local_hand_order()
	var targets := PackedStringArray(card_ids)
	var labels := PackedStringArray()
	for index in order.size():
		if str(order[index]) in targets:
			labels.append(str(index + 1))
	return "" if labels.is_empty() else "[%s]" % ",".join(labels)


func _half_position(id: Variant, half_index: int) -> String:
	return "top half" if _hand_controls._top_half(StringName(id)) == half_index else "bottom half"


func _ability_name(copy_id: Variant) -> String:
	for card: Dictionary in _model.get("private_abilities", []):
		if str(card.copy_id) == str(copy_id):
			var catalog: Dictionary = _model.get("ability_catalog", {})
			return str(catalog.get(str(card.ability_id), {}).get("display_name", str(card.ability_id).capitalize()))
	return "the indicated ability"
