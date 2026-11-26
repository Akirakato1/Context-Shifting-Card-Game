class_name PlayerSeat
extends VBoxContainer

signal ability_target_requested(player_id: String)
signal view_requested(player_id: String)

const CARD_SCENE := preload("res://src/view/match/card_widget.tscn")
const AvatarCatalog := preload("res://src/view/common/avatar_catalog.gd")
const GameTypes := preload("res://src/core/common/game_types.gd")
const ScoringReference := preload("res://src/view/app/scoring_reference.gd")
const FACE_SIZE := Vector2(92, 96)
const BACK_SIZE := Vector2(42, 58)
const TARGET_AURA := preload("res://src/view/match/primed_card_aura.tres")

@export var seat_position: StringName = &"empty"

var show_placeholder_guides := true
var seat_art: StyleBox
var _shown_spectator_hand: Array = []
var _shown_backs := 0
var _context_catalog: Array = []
var _player_id := ""
var _target_eligible := false
var _target_selected := false
var _target_interactive := false
var _target_hovered := false
var _target_glow := TARGET_AURA.duplicate() as StyleBoxFlat
var _shadow_light := Vector2.INF

@onready var _name: Label = $Info/Name
@onready var _ready_check: Label = $Info/Name/ReadyCheck
@onready var _avatar_frame: TextureRect = $Avatar
@onready var _ready_aura: TextureRect = $Avatar/ReadyAura
var _view_selectable := false
@onready var _avatar: TextureRect = $Avatar/Portrait
@onready var _summary: VBoxContainer = $Summary
@onready var _ready_status: Label = $Summary/ReadyStatus
@onready var _score: Label = $Summary/ScoreSummary
@onready var _seat_tally: Label = $Summary/SeatTally
@onready var _request: Label = $Request
@onready var _hand: HFlowContainer = $Hand


func _ready() -> void:
	resized.connect(queue_redraw)
	minimum_size_changed.connect(queue_redraw)
	_avatar_frame.item_rect_changed.connect(queue_redraw)
	_name.resized.connect(_position_ready_check)
	_ready_check.add_theme_font_override("font", ThemeDB.fallback_font)
	set_notify_transform(true)
	mouse_entered.connect(_set_target_hovered.bind(true))
	mouse_exited.connect(_set_target_hovered.bind(false))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	_target_glow.draw_center = true
	_target_glow.set_corner_radius_all(10)
	_target_glow.set_border_width_all(2)
	_target_glow.shadow_size = 10


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()


func set_shadow_light(world_position: Vector2) -> void:
	_shadow_light = world_position
	queue_redraw()


func _draw() -> void:
	if _avatar_frame.visible:
		_draw_avatar_shadow()
	else:
		var frame := seat_art if seat_art != null else (get_theme_stylebox("panel") if show_placeholder_guides else null)
		if frame != null:
			draw_style_box(frame, _ability_target_local_rect())
	if _target_eligible:
		var emphasized := _target_hovered or _target_selected or has_focus()
		_target_glow.border_color = Color(TARGET_AURA.border_color, 0.82 if emphasized else 0.43)
		_target_glow.bg_color = Color(TARGET_AURA.border_color, 0.13 if emphasized else 0.055)
		_target_glow.shadow_color = Color(TARGET_AURA.shadow_color, 0.28 if emphasized else 0.12)
		draw_style_box(_target_glow, _ability_target_local_rect())


func _draw_avatar_shadow() -> void:
	if _avatar.texture == null or not _shadow_light.is_finite():
		return
	var dimensions := _avatar_frame.size
	var foot := _avatar_frame.position + Vector2(dimensions.x * 0.5, dimensions.y - 2.0)
	var ground_scale := Vector2(1.0, 0.55)
	var light := get_global_transform().affine_inverse() * _shadow_light
	var outward := ((foot - light) / ground_scale).normalized()
	var across := Vector2(-outward.y, outward.x)
	if (across.x < 0.0) != _avatar.flip_h:
		across = -across
	var width_axis := across * ground_scale * 0.9
	var height_axis := -outward * ground_scale * 0.85
	var origin := foot - width_axis * dimensions.x * 0.5 - height_axis * dimensions.y
	var silhouette := Rect2(Vector2.ZERO, dimensions)
	for edge_offset in [-3.0, 3.0]:
		draw_set_transform_matrix(Transform2D(width_axis, height_axis, origin + across * edge_offset))
		draw_texture_rect(_avatar.texture, silhouette, false, Color(0.02, 0.013, 0.02, 0.12))
	draw_set_transform_matrix(Transform2D(width_axis, height_axis, origin))
	draw_texture_rect(_avatar.texture, silhouette, false, Color(0.02, 0.013, 0.02, 0.32))
	draw_set_transform_matrix(Transform2D.IDENTITY)


func player_id() -> String:
	return _player_id


func hand_submitted() -> bool:
	return _ready_check.visible


func _position_ready_check() -> void:
	if not hand_submitted():
		return
	var font := _name.get_theme_font("font")
	var text_width := font.get_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _name.get_theme_font_size("font_size")).x
	var text_left := maxf((_name.size.x - text_width) * 0.5, 0)
	_ready_check.position.x = text_left - _ready_check.size.x - 6.0


func set_ability_target(eligible: bool, selected := false, interactive := false) -> void:
	_target_eligible = eligible and not _player_id.is_empty()
	_target_selected = _target_eligible and selected
	_target_interactive = _target_eligible and interactive
	_update_pointer()
	if not _target_interactive:
		_target_hovered = false
	queue_redraw()


func set_view_selectable(enabled: bool) -> void:
	_view_selectable = enabled and not _player_id.is_empty()
	_update_pointer()


func _update_pointer() -> void:
	var interactive := _target_interactive or _view_selectable
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _view_selectable else Control.CURSOR_ARROW
	if _target_interactive:
		mouse_default_cursor_shape = Control.CURSOR_CROSS
	focus_mode = Control.FOCUS_ALL if interactive else Control.FOCUS_NONE
	if not interactive:
		release_focus()


func ability_target_rect() -> Rect2:
	return get_global_transform() * _ability_target_local_rect()


func is_ability_target() -> bool:
	return _target_eligible


func _ability_target_local_rect() -> Rect2:
	var info_width := maxf(_name.get_combined_minimum_size().x, _summary.get_combined_minimum_size().x)
	var width := (size.x if _hand.visible else info_width) + 16.0
	return Rect2((size.x - width) / 2.0, -6, width, get_combined_minimum_size().y + 12)


func _has_point(point: Vector2) -> bool:
	return (_target_interactive and _ability_target_local_rect().has_point(point)) or (
		_view_selectable and _avatar_frame.visible and _avatar_frame.get_rect().has_point(point)
	)


func _gui_input(event: InputEvent) -> void:
	if not _target_interactive and not _view_selectable:
		return
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
			return
		if not _has_point(event.position):
			return
	elif not event.is_action_pressed(&"ui_accept"):
		return
	accept_event()
	if _target_interactive:
		ability_target_requested.emit(_player_id)
	else:
		view_requested.emit(_player_id)


func _set_target_hovered(hovered: bool) -> void:
	_target_hovered = _target_interactive and hovered
	queue_redraw()


func render(
	player: Dictionary,
	phase: int,
	viewing_as_spectator: bool,
	is_local: bool,
	victory_mode: int,
	request: Dictionary = {},
	context_catalog: Array = []
) -> void:
	_context_catalog = context_catalog
	var next_player_id := str(player.get("player_id", ""))
	if _player_id != next_player_id:
		_player_id = next_player_id
		set_ability_target(false)
	var occupied := not player.is_empty()
	var active := occupied and bool(player.get("active", false)) and not bool(player.get("pending", false))
	var ready := bool(player.get("ready", false))
	var submitted := active and phase == GameTypes.Phase.HAND_PLAY and ready
	var display_name := str(player.get("name", player.get("player_id", "OPEN SEAT")))
	_name.text = ("YOU  ·  " + display_name) if is_local else display_name
	_name.tooltip_text = display_name if occupied else ""
	if submitted:
		_name.tooltip_text += " · Hand submitted"
	_ready_check.visible = submitted
	_ready_aura.visible = submitted
	_position_ready_check()
	var avatar_id := str(player.get("avatar_id", AvatarCatalog.default_avatar_id(int(player.get("seat_index", 0)))))
	_avatar.texture = AvatarCatalog.seat_texture(avatar_id, seat_position) if occupied else null
	_avatar.flip_h = occupied and seat_position == &"left" and AvatarCatalog.has_side(avatar_id)
	_avatar_frame.visible = occupied
	queue_redraw()
	_ready_status.visible = (
		active
		and phase in [GameTypes.Phase.START, GameTypes.Phase.MAIN_1, GameTypes.Phase.MAIN_2]
	)
	_ready_status.text = "READY" if ready else "DECIDING"
	_ready_status.modulate = Color("8fedc2") if ready else Color("f4ca8b")
	_summary.visible = occupied
	var use_wins := victory_mode == GameTypes.VictoryMode.ROUND_WIN_RACE
	var count := int(player.get("ability_count", 0))
	_seat_tally.text = "%d %s  ·  %d %s" % [
		int(player.get("round_wins" if use_wins else "match_score", 0)),
		"wins" if use_wins else "pts",
		count, "ability" if count == 1 else "abilities",
	]
	_request.visible = viewing_as_spectator and not request.is_empty()
	_request.text = _request_text(request) if _request.visible else ""
	var is_end := phase == GameTypes.Phase.END
	if is_end and player.has("discard_complete"):
		_seat_tally.text += "  ·  Ready" if bool(player.discard_complete) else "  ·  Discarding"
	var revealed: Dictionary = {}
	if is_end or phase == GameTypes.Phase.MAIN_2:
		revealed = player.get("revealed_submission", {})
	var spectator_hand: Array = []
	var backs := 0
	if viewing_as_spectator and not is_end:
		spectator_hand = player.get("spectator_hand", [])
		backs = maxi(int(player.get("hand_count", 0)) - spectator_hand.size(), 0)
	_render_spectator_hand(spectator_hand, backs)
	_hand.modulate = Color("c2c8d2") if phase == GameTypes.Phase.MAIN_2 else Color.WHITE
	_score.visible = not revealed.is_empty()
	var score_key := "finalized_score" if is_end else "provisional_score"
	var score := int(revealed.get(score_key, revealed.get("score_breakdown", {}).get("final_score", 0)))
	if revealed.get("cards", []).is_empty():
		_score.text = "Passed"
	else:
		_score.text = ("Hand score %d" if is_end else "%d provisional points") % score
	_score.tooltip_text = _score_text(revealed) if _score.visible else ""


func _render_spectator_hand(spectator_hand: Array, backs: int) -> void:
	_hand.visible = not spectator_hand.is_empty() or backs > 0
	if spectator_hand == _shown_spectator_hand and backs == _shown_backs:
		return
	_shown_spectator_hand = spectator_hand
	_shown_backs = backs
	for child in _hand.get_children():
		_hand.remove_child(child)
		child.queue_free()
	for card: Dictionary in spectator_hand:
		var display_card := card.duplicate()
		display_card["card_id"] = "spectator-" + str(card.get("view_id", ""))
		_add_card(display_card, false)
	for index in backs:
		_add_card({"card_id": "back_%d" % index}, true)


func _add_card(card: Dictionary, face_down: bool) -> void:
	var widget := CARD_SCENE.instantiate() as CardWidget
	widget.custom_minimum_size = BACK_SIZE if face_down else FACE_SIZE
	widget.mouse_filter = Control.MOUSE_FILTER_PASS
	_hand.add_child(widget)
	widget.render(card, -1, face_down, {"interaction_disabled": true, "display_only": true})
	if face_down:
		return
	widget.tooltip_text = "%s\n%s" % [widget.first_face_text(), widget.second_face_text()]


func _request_text(request: Dictionary) -> String:
	return "DRAW  Rise %d · Flourish %d · Fall %d" % [
		int(request.get("0", request.get(0, 0))),
		int(request.get("1", request.get(1, 0))),
		int(request.get("2", request.get(2, 0))),
	]


func _score_text(revealed: Dictionary) -> String:
	if revealed.has("cards") and revealed.cards.is_empty():
		return "Passed · 0 points"
	if revealed.has("score_breakdown"):
		return _factor_score_text(revealed.score_breakdown, "pts")
	return "%s  ×  %s   ·   %d pts" % [
		ScoringReference.normal_display_name(str(revealed.get("normal_category", "high_card"))),
		_context_name(str(revealed.get("context_category", "no_context_pattern"))),
		int(revealed.get("finalized_score", revealed.get("provisional_score", 0))),
	]


func _factor_score_text(breakdown: Dictionary, suffix: String) -> String:
	return "Base %d · Card %s · Context %s · Field %s · %d %s" % [
		int(breakdown.get("base_value", 0)), _factor_summary(breakdown, "card_hand"),
		_factor_summary(breakdown, "context_hand"), _factor_summary(breakdown, "field"),
		int(breakdown.get("final_score", 0)), suffix,
	]


func _factor_summary(breakdown: Dictionary, factor_id: String) -> String:
	var terms: Array[String] = []
	for component in breakdown.get(factor_id + "_components", []):
		var component_name := str(component.get("category_id", "")).replace("_", " ").capitalize()
		var source_id := str(component.get("source_definition_id", ""))
		if factor_id == "context_hand" and not source_id.is_empty():
			component_name = _context_name(source_id)
		terms.append("%s %s" % [component_name, _rational_text(component.get("value", {}))])
	for modifier in breakdown.get("applied_modifiers", []):
		if str(modifier.get("factor_id", "")) != factor_id: continue
		terms.append("%s %s" % [str(modifier.get("category_id", "")).replace("_", " ").capitalize(),
			_signed_rational_text(modifier.get("delta", {}))])
	if terms.is_empty(): terms.append("neutral")
	var unclamped: Dictionary = breakdown.get(factor_id + "_unclamped", {})
	var factor: Dictionary = breakdown.get(factor_id + "_factor", {})
	var floor_text := " floor" if int(unclamped.get("numerator", 1)) < int(unclamped.get("denominator", 1)) else ""
	return "[%s]=%s%s" % [" + ".join(terms), _rational_text(factor), floor_text]


func _rational_text(value: Dictionary) -> String:
	var numerator := int(value.get("numerator", 1))
	var denominator := int(value.get("denominator", 1))
	return str(numerator) if denominator == 1 else "%d/%d" % [numerator, denominator]


func _signed_rational_text(value: Dictionary) -> String:
	var text := _rational_text(value)
	return "+%s" % text if int(value.get("numerator", 0)) >= 0 else text


func _context_name(id: String) -> String:
	for entry: Dictionary in _context_catalog:
		if str(entry.get("id", "")) == id:
			return str(entry.get("display_name", id.capitalize()))
	if id in ["no_context", "no_context_pattern"]:
		return "No Context Pattern ×1"
	if id.begins_with("all_contexts_"):
		return "All Contexts ×%s" % id.trim_prefix("all_contexts_")
	var parts := id.split("_")
	if parts.size() >= 2 and parts[-1].is_valid_int():
		var context_names: Array[String] = []
		for index in range(parts.size() - 1):
			var context_name: String = {
				"rise": "Rise", "flourish": "Flourish", "fall": "Fall",
			}.get(parts[index], "")
			if context_name.is_empty():
				return id.replace("_", " ").capitalize()
			context_names.append(context_name)
		return "%s ×%s" % [" + ".join(context_names), parts[-1]]
	return id.replace("_", " ").capitalize()
