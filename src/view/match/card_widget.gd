class_name CardWidget
extends PanelContainer

signal primary_clicked(card_id: StringName)
signal orientation_requested(card_id: StringName)
signal half_choice_requested(card_id: StringName, half_index: int)
signal joker_choice_changed(card_id: StringName, half_index: int, context: int, suit: int)

const CONTEXT_NAMES := ["A", "B", "C"]
const SUIT_NAMES := ["ONE", "TWO", "THREE"]

var card_id := ""
var active_half_index := -1
var face_down := false
var interaction_disabled := false
var orientation_flipped := false
var targeting_eligible := false
var targeting_selected := false
var _card: Dictionary = {}
var _staged := false

@onready var _back: Label = $Back
@onready var _face: VBoxContainer = $Face
@onready var _first: Label = $Face/First
@onready var _second: Label = $Face/Second
@onready var _first_choices: HBoxContainer = $Face/FirstChoices
@onready var _first_context: OptionButton = $Face/FirstChoices/Context
@onready var _first_suit: OptionButton = $Face/FirstChoices/Suit
@onready var _second_choices: HBoxContainer = $Face/SecondChoices
@onready var _second_context: OptionButton = $Face/SecondChoices/Context
@onready var _second_suit: OptionButton = $Face/SecondChoices/Suit


func _ready() -> void:
	_populate_choices(_first_context, CONTEXT_NAMES)
	_populate_choices(_second_context, CONTEXT_NAMES)
	_populate_choices(_first_suit, SUIT_NAMES)
	_populate_choices(_second_suit, SUIT_NAMES)


func render(
	card: Dictionary,
	active_context: int = -1,
	hidden: bool = false,
	view_state: Dictionary = {}
) -> void:
	_card = card.duplicate(true)
	card_id = str(card.get("card_id", ""))
	face_down = hidden
	interaction_disabled = bool(view_state.get("interaction_disabled", hidden))
	orientation_flipped = bool(view_state.get("orientation_flipped", false))
	_staged = bool(view_state.get("staged", false))
	targeting_eligible = bool(view_state.get("targeting_eligible", false))
	targeting_selected = bool(view_state.get("targeting_selected", false))
	_back.visible = hidden
	_face.visible = not hidden
	_first_choices.visible = false
	_second_choices.visible = false
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
	elif view_state.has("selected_half_index"):
		active_half_index = int(view_state["selected_half_index"])
	elif _half_matches_context(first, active_context):
		active_half_index = 0
	elif _half_matches_context(second, active_context):
		active_half_index = 1
	_apply_joker_choices(first, second, view_state)
	_apply_orientation()
	_apply_active_style()
	if targeting_selected:
		modulate = Color("ffd45a")
	elif targeting_eligible:
		modulate = Color("77e8ff")
	else:
		modulate = Color("8290a0") if interaction_disabled else Color.WHITE


func _gui_input(event: InputEvent) -> void:
	if interaction_disabled or face_down:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			primary_clicked.emit(StringName(card_id))
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			orientation_requested.emit(StringName(card_id))
			accept_event()


func first_face_text() -> String:
	return _first.text


func second_face_text() -> String:
	return _second.text


func joker_prompts_visible() -> bool:
	return _first_choices.visible or _second_choices.visible


func _half_text(half: Dictionary) -> String:
	if int(half.get("kind", 0)) == 1:
		return "JOKER  0  ANY"
	var context := int(half.get("effective_context", half.get("base_context", 0)))
	var rank := int(half.get("effective_rank", half.get("rank", half.get("base_rank", 0))))
	var suit := int(half.get("effective_suit", half.get("suit", half.get("base_suit", 0))))
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


func _apply_joker_choices(first: Dictionary, second: Dictionary, view_state: Dictionary) -> void:
	if not bool(view_state.get("staged", false)):
		return
	var choices: Array = view_state.get("joker_choices", [])
	for raw_choice in choices:
		if not raw_choice is Dictionary:
			continue
		var half_index := int(raw_choice.get("half_index", -1))
		if half_index == 0 and int(first.get("kind", 0)) == 1:
			_first_choices.visible = true
			_first_context.select(int(raw_choice.get("context", 0)))
			_first_suit.select(int(raw_choice.get("suit", 0)))
		elif half_index == 1 and int(second.get("kind", 0)) == 1:
			_second_choices.visible = true
			_second_context.select(int(raw_choice.get("context", 0)))
			_second_suit.select(int(raw_choice.get("suit", 0)))


func _apply_orientation() -> void:
	if orientation_flipped:
		_face.move_child(_second, 0)
		_face.move_child(_second_choices, 1)
		_face.move_child(_first, 3)
		_face.move_child(_first_choices, 4)
	else:
		_face.move_child(_first, 0)
		_face.move_child(_first_choices, 1)
		_face.move_child(_second, 3)
		_face.move_child(_second_choices, 4)


func _populate_choices(button: OptionButton, values: Array) -> void:
	if button.item_count > 0:
		return
	for value in values:
		button.add_item(str(value))


func _on_first_context_selected(index: int) -> void:
	joker_choice_changed.emit(StringName(card_id), 0, index, _first_suit.selected)


func _on_first_suit_selected(index: int) -> void:
	joker_choice_changed.emit(StringName(card_id), 0, _first_context.selected, index)


func _on_second_context_selected(index: int) -> void:
	joker_choice_changed.emit(StringName(card_id), 1, index, _second_suit.selected)


func _on_second_suit_selected(index: int) -> void:
	joker_choice_changed.emit(StringName(card_id), 1, _second_context.selected, index)


func _on_first_gui_input(event: InputEvent) -> void:
	_handle_half_gui_input(event, 0)


func _on_second_gui_input(event: InputEvent) -> void:
	_handle_half_gui_input(event, 1)


func _handle_half_gui_input(event: InputEvent, half_index: int) -> void:
	if interaction_disabled or face_down:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _staged:
			half_choice_requested.emit(StringName(card_id), half_index)
		else:
			primary_clicked.emit(StringName(card_id))
		accept_event()


func _safe_name(values: Array, index: int, fallback: String) -> String:
	return str(values[index]) if index >= 0 and index < values.size() else fallback
