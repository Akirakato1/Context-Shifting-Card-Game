class_name PlayerSeat
extends VBoxContainer

signal ability_target_requested(player_id: String)

const CARD_SCENE := preload("res://src/view/match/card_widget.tscn")
const GameTypes := preload("res://src/core/common/game_types.gd")
const FACE_SIZE := Vector2(92, 96)
const BACK_SIZE := Vector2(42, 58)
const TARGET_AURA := preload("res://src/view/match/primed_card_aura.tres")

@export var seat_position: StringName = &"empty"

var show_placeholder_guides := true
var seat_art: StyleBox
var _shown_cards: Array = []
var _shown_spectator_hand: Array = []
var _shown_backs := 0
var _context_catalog: Array = []
var _player_id := ""
var _target_eligible := false
var _target_selected := false
var _target_interactive := false
var _target_hovered := false
var _target_glow := TARGET_AURA.duplicate() as StyleBoxFlat
var _base_info_mouse_filter := Control.MOUSE_FILTER_PASS

@onready var _info: HBoxContainer = $Info
@onready var _name: Label = $Info/Name
@onready var _score: Label = $Summary/ScoreSummary
@onready var _seat_tally: Label = $Summary/SeatTally
@onready var _request: Label = $Request
@onready var _hand: HFlowContainer = $Hand


func _ready() -> void:
	resized.connect(queue_redraw)
	minimum_size_changed.connect(queue_redraw)
	mouse_entered.connect(_set_target_hovered.bind(true))
	mouse_exited.connect(_set_target_hovered.bind(false))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	_base_info_mouse_filter = _info.mouse_filter
	_target_glow.draw_center = true
	_target_glow.set_corner_radius_all(10)
	_target_glow.set_border_width_all(2)
	_target_glow.shadow_size = 10


func _draw() -> void:
	var frame := seat_art if seat_art != null else (get_theme_stylebox("panel") if show_placeholder_guides else null)
	if frame != null:
		draw_style_box(frame, Rect2(-10, -8, size.x + 20, get_combined_minimum_size().y + 16))
	if _target_eligible:
		var emphasized := _target_hovered or _target_selected or has_focus()
		_target_glow.border_color = Color(TARGET_AURA.border_color, 0.82 if emphasized else 0.43)
		_target_glow.bg_color = Color(TARGET_AURA.border_color, 0.13 if emphasized else 0.055)
		_target_glow.shadow_color = Color(TARGET_AURA.shadow_color, 0.28 if emphasized else 0.12)
		draw_style_box(_target_glow, _ability_target_local_rect())


func player_id() -> String:
	return _player_id


func set_ability_target(eligible: bool, selected := false, interactive := false) -> void:
	_target_eligible = eligible and not _player_id.is_empty()
	_target_selected = _target_eligible and selected
	_target_interactive = _target_eligible and interactive
	mouse_filter = Control.MOUSE_FILTER_STOP if _target_interactive else Control.MOUSE_FILTER_IGNORE
	mouse_default_cursor_shape = Control.CURSOR_CROSS if _target_interactive else Control.CURSOR_ARROW
	focus_mode = Control.FOCUS_ALL if _target_interactive else Control.FOCUS_NONE
	_info.mouse_filter = Control.MOUSE_FILTER_PASS if _target_interactive else _base_info_mouse_filter
	if not _target_interactive:
		release_focus()
		_target_hovered = false
	queue_redraw()


func ability_target_rect() -> Rect2:
	return get_global_transform() * _ability_target_local_rect()


func is_ability_target() -> bool:
	return _target_eligible


func _ability_target_local_rect() -> Rect2:
	var width := minf(size.x + 16, 320.0) if not _hand.visible else size.x + 16
	return Rect2((size.x - width) / 2.0, -6, width, maxf(size.y, get_combined_minimum_size().y) + 12)


func _has_point(point: Vector2) -> bool:
	return _target_interactive and _ability_target_local_rect().has_point(point)


func _gui_input(event: InputEvent) -> void:
	if not _target_interactive:
		return
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
			return
		if not _ability_target_local_rect().has_point(event.position):
			return
	elif not event.is_action_pressed(&"ui_accept"):
		return
	accept_event()
	ability_target_requested.emit(_player_id)


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
	var display_name := str(player.get("name", player.get("player_id", "OPEN SEAT")))
	_name.text = ("YOU  ·  " + display_name) if is_local else display_name
	_name.tooltip_text = display_name if occupied else ""
	$Summary.visible = occupied
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
	var revealed: Dictionary = {}
	if is_end or phase == GameTypes.Phase.MAIN_2:
		revealed = player.get("revealed_submission", {})
	var cards: Array = revealed.get("cards", [])
	var spectator_hand: Array = []
	var backs := 0
	if viewing_as_spectator and not is_end:
		spectator_hand = player.get("spectator_hand", [])
		backs = maxi(int(player.get("hand_count", 0)) - spectator_hand.size(), 0)
	_render_hand(cards, spectator_hand, backs)
	_score.visible = is_end and not revealed.is_empty()
	_score.text = "Passed" if revealed.has("cards") and cards.is_empty() else "%d points this round" % int(revealed.get(
		"finalized_score", revealed.get("score_breakdown", {}).get("final_score", 0)
	))
	_score.tooltip_text = _score_text(revealed) if _score.visible else ""


func card_at(index: int) -> Variant:
	if index < 0 or index >= _hand.get_child_count():
		return null
	return _hand.get_child(index)


func _render_hand(cards: Array, spectator_hand: Array, backs: int) -> void:
	_hand.visible = not cards.is_empty() or not spectator_hand.is_empty() or backs > 0
	if cards == _shown_cards and spectator_hand == _shown_spectator_hand and backs == _shown_backs:
		return
	_shown_cards = cards
	_shown_spectator_hand = spectator_hand
	_shown_backs = backs
	for child in _hand.get_children():
		_hand.remove_child(child)
		child.queue_free()
	for card: Dictionary in cards:
		_add_card(card, false)
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
	var faces := [widget.first_face_text(), widget.second_face_text()]
	var scored_half := widget.active_half_index
	widget.tooltip_text = (
		"%s\n%s" % faces if scored_half < 0
		else "Scored: %s\nOther half: %s" % [faces[scored_half], faces[1 - scored_half]]
	)


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
		_category_name(str(revealed.get("normal_category", "high_card"))),
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


func _category_name(id: String) -> String:
	var names := {
		"high_card": "High Card", "pair": "Pair", "two_pair": "Two Pair",
		"three_kind": "Three of a Kind", "straight": "Straight", "flush": "Flush",
		"full_house": "Full House", "four_kind": "Four of a Kind",
		"straight_flush": "Straight Flush",
	}
	return names.get(id, id.replace("_", " ").capitalize())


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
