class_name PlayerSeat
extends VBoxContainer

const CARD_SCENE := preload("res://src/view/match/card_widget.tscn")

@export var seat_position: StringName = &"empty"

var _hidden_cards := 0

@onready var _name: Label = $Info/Name
@onready var _status: Label = $Info/Status
@onready var _score: Label = $ScoreSummary
@onready var _request: Label = $Request
@onready var _hand: HBoxContainer = $Hand


func render(
	player: Dictionary,
	private_hand: Array,
	active_context: int,
	is_local: bool,
	request: Dictionary = {},
	show_hand: bool = true
) -> void:
	_clear_hand()
	_hidden_cards = 0
	if player.is_empty():
		_name.text = "OPEN SEAT"
		_status.text = "WAITING"
		_score.text = ""
		_request.visible = false
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
		for index in _hidden_cards:
			cards.append({"card_id": "back_%d" % index})
	_hand.visible = show_hand and (is_local or not cards.is_empty())
	for card in cards:
		var widget = CARD_SCENE.instantiate()
		_hand.add_child(widget)
		widget.render(card, active_context, hidden)
	_score.text = _score_text(player, revealed)


func visible_card_count() -> int:
	return _hand.get_child_count() if _hand.visible and _hidden_cards == 0 else 0


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
	return "DRAW  A%d · B%d · C%d" % [
		int(request.get("A", request.get("0", 0))),
		int(request.get("B", request.get("1", 0))),
		int(request.get("C", request.get("2", 0))),
	]


func _score_text(player: Dictionary, revealed: Dictionary) -> String:
	if not revealed.is_empty():
		return "%s  ×  %s   ·   %d pts" % [
		_category_name(str(revealed.get("normal_category", "high_card"))),
		_context_name(str(revealed.get("context_category", "no_context_pattern"))),
		int(revealed.get("finalized_score", revealed.get("provisional_score", 0))),
		]
	var provisional: Dictionary = player.get("provisional_score", {})
	if provisional.is_empty():
		return ""
	return "%s  ×  %s   ·   %d provisional" % [
		_category_name(str(provisional.get("normal_category", "high_card"))),
		_context_name(str(provisional.get("context_category", "no_context_pattern"))),
		int(provisional.get("final_score", 0)),
	]


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
	return id.replace("_", " ").to_upper().replace("ABC 1", "ABC ×1")
