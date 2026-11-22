class_name PlayerSeat
extends VBoxContainer

const CARD_SCENE := preload("res://src/view/match/card_widget.tscn")

@export var seat_position: StringName = &"empty"

var _hidden_cards := 0
var show_placeholder_guides := true
var seat_art: StyleBox

@onready var _name: Label = $Info/Name
@onready var _status: Label = $Info/Status
@onready var _score: Label = $ScoreSummary
@onready var _request: Label = $Request
@onready var _hand_count: Label = $HandCount
@onready var _hand: HFlowContainer = $Hand
@onready var _seat_tally: Label = $SeatTally
@onready var _ability_holder: HBoxContainer = $AbilityHolder


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var frame := seat_art if seat_art != null else (get_theme_stylebox("panel") if show_placeholder_guides else null)
	if frame != null:
		draw_style_box(frame, Rect2(-10, -8, size.x + 20, size.y + 16))


func render_table_seat(player: Dictionary, victory_mode: int) -> void:
	_seat_tally.visible = not player.is_empty()
	_ability_holder.visible = not player.is_empty()
	for child in _ability_holder.get_children():
		_ability_holder.remove_child(child)
		child.queue_free()
	if player.is_empty():
		return
	_seat_tally.text = "◉    %d %s" % [
		int(player.get("round_wins" if victory_mode == 1 else "match_score", 0)),
		"wins" if victory_mode == 1 else "pts",
	]
	var count := int(player.get("ability_count", 0))
	for i in mini(count, 4):
		var back := Label.new()
		back.text = "◇"
		back.modulate = Color("d1baed")
		_ability_holder.add_child(back)
	var amount := Label.new()
	amount.text = "%d abilities" % count
	_ability_holder.add_child(amount)


func render(
	player: Dictionary,
	private_hand: Array,
	active_context: int,
	is_local: bool,
	request: Dictionary = {},
	show_hand: bool = true,
	active_contexts: Array = []
) -> void:
	_clear_hand()
	_hidden_cards = 0
	if player.is_empty():
		_name.text = "OPEN SEAT"
		_status.text = "WAITING"
		_score.text = ""
		_request.visible = false
		_hand_count.visible = false
		_hand.visible = false
		return
	var display_name := str(player.get("name", player.get("player_id", "Player")))
	_name.text = ("YOU  ·  " + display_name) if is_local else display_name
	_status.text = _status_text(player)
	_request.visible = not request.is_empty()
	_request.text = _request_text(request) if _request.visible else ""
	var revealed: Dictionary = player.get("revealed_submission", {})
	var cards: Array = []
	var hidden := false
	if is_local:
		cards = private_hand
	elif not revealed.is_empty():
		cards = revealed.get("cards", [])
	else:
		hidden = true
		_hidden_cards = int(player.get("hand_count", 0))
		var visible_backs := mini(_hidden_cards, 3)
		for index in visible_backs:
			cards.append({"card_id": "back_%d" % index})
	_hand_count.visible = hidden
	_hand_count.text = "Private hand · %d %s" % [
		_hidden_cards, "card" if _hidden_cards == 1 else "cards",
	] if hidden else ""
	_hand.visible = show_hand and (is_local or not cards.is_empty())
	for card in cards:
		var widget = CARD_SCENE.instantiate()
		_hand.add_child(widget)
		if not is_local:
			widget.custom_minimum_size = Vector2(72, 58)
		widget.render(card, active_context, hidden, {"active_contexts": active_contexts})
		widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score.text = _score_text(player, revealed)


func visible_card_count() -> int:
	return _hand.get_child_count() if _hidden_cards == 0 else 0


func hidden_card_count() -> int:
	return _hidden_cards


func card_at(index: int) -> Variant:
	if index < 0 or index >= _hand.get_child_count():
		return null
	return _hand.get_child(index)


func _clear_hand() -> void:
	for child in _hand.get_children():
		_hand.remove_child(child)
		child.queue_free()


func _status_text(player: Dictionary) -> String:
	if not bool(player.get("connected", true)):
		return "RECONNECTING"
	if bool(player.get("pending", false)):
		return "JOINS NEXT ROUND"
	return "READY" if bool(player.get("ready", false)) else "THINKING"


func _request_text(request: Dictionary) -> String:
	return "DRAW  Rise %d · Flourish %d · Fall %d" % [
		int(request.get("0", request.get(0, 0))),
		int(request.get("1", request.get(1, 0))),
		int(request.get("2", request.get(2, 0))),
	]


func _score_text(player: Dictionary, revealed: Dictionary) -> String:
	if not revealed.is_empty():
		var cards: Array = revealed.get("cards", [])
		if revealed.has("cards") and cards.is_empty():
			return "Passed · 0 points"
		if revealed.has("score_breakdown"):
			return _factor_score_text(revealed.score_breakdown, "pts")
		return "%s  ×  %s   ·   %d pts" % [
		_category_name(str(revealed.get("normal_category", "high_card"))),
		_context_name(str(revealed.get("context_category", "no_context_pattern"))),
		int(revealed.get("finalized_score", revealed.get("provisional_score", 0))),
		]
	var provisional: Dictionary = player.get("provisional_score", {})
	if provisional.is_empty():
		return ""
	if provisional.has("score_breakdown"):
		return _factor_score_text(provisional.score_breakdown, "provisional")
	return "%s  ×  %s   ·   %d provisional" % [
		_category_name(str(provisional.get("normal_category", "high_card"))),
		_context_name(str(provisional.get("context_category", "no_context_pattern"))),
		int(provisional.get("final_score", 0)),
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
	if id == "no_context_pattern":
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
