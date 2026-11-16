class_name CardWidget
extends PanelContainer

const CONTEXT_NAMES := ["A", "B", "C"]
const SUIT_NAMES := ["ONE", "TWO", "THREE"]

var card_id := ""
var active_half_index := -1
var face_down := false

@onready var _back: Label = $Back
@onready var _face: VBoxContainer = $Face
@onready var _first: Label = $Face/First
@onready var _second: Label = $Face/Second


func render(card: Dictionary, active_context: int = -1, hidden: bool = false) -> void:
	card_id = str(card.get("card_id", ""))
	face_down = hidden
	_back.visible = hidden
	_face.visible = not hidden
	active_half_index = -1
	if hidden:
		return
	var first: Dictionary = card.get("first", {})
	var second: Dictionary = card.get("second", {})
	var resolved_halves: Array = card.get("halves", [])
	if resolved_halves.size() >= 2:
		first = _resolved_half(resolved_halves[0])
		second = _resolved_half(resolved_halves[1])
	_first.text = _half_text(first)
	_second.text = _half_text(second)
	if card.has("selected_half_index"):
		active_half_index = int(card["selected_half_index"])
	elif _half_matches_context(first, active_context):
		active_half_index = 0
	elif _half_matches_context(second, active_context):
		active_half_index = 1
	_apply_active_style()


func first_face_text() -> String:
	return _first.text


func second_face_text() -> String:
	return _second.text


func _half_text(half: Dictionary) -> String:
	if int(half.get("kind", 0)) == 1:
		return "JOKER  0  ANY"
	var context := int(half.get("effective_context", half.get("base_context", 0)))
	var rank := int(half.get("effective_rank", half.get("base_rank", 0)))
	var suit := int(half.get("effective_suit", half.get("base_suit", 0)))
	return "%s  %d  %s" % [_safe_name(CONTEXT_NAMES, context, "?"), rank, _safe_name(SUIT_NAMES, suit, "?")]


func _half_matches_context(half: Dictionary, active_context: int) -> bool:
	return (
		int(half.get("kind", 0)) == 1
		or int(half.get("effective_context", half.get("base_context", -1))) == active_context
	)


func _resolved_half(half: Dictionary) -> Dictionary:
	return {
		"effective_context": half.get("context", -1),
		"effective_rank": half.get("rank", 0),
		"effective_suit": half.get("suit", -1),
		"kind": 1 if bool(half.get("joker", false)) else 0,
	}


func _apply_active_style() -> void:
	var normal := Color("c4cfdb")
	var active := Color("ffd166")
	_first.modulate = active if active_half_index == 0 else normal
	_second.modulate = active if active_half_index == 1 else normal


func _safe_name(values: Array, index: int, fallback: String) -> String:
	return str(values[index]) if index >= 0 and index < values.size() else fallback
