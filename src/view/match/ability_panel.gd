class_name AbilityPanel
extends Control

signal ability_activated(copy_id: StringName, ability: Dictionary)

var _abilities: Dictionary = {}
var _legal_ids: Array[StringName] = []
var _button_copy_ids: Dictionary = {}
var _expanded := false
var _input_locked := false

@onready var _drawer: PanelContainer = $Drawer
@onready var _cards: VBoxContainer = $Drawer/Layout/Cards
@onready var _toggle: Button = $ToggleButton


func render(abilities: Array, phase: int, catalog: Dictionary, input_locked: bool) -> void:
	_input_locked = input_locked
	_abilities.clear()
	_legal_ids.clear()
	_button_copy_ids.clear()
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	for ability_ref in abilities:
		if not ability_ref is Dictionary:
			continue
		var copy_id := StringName(ability_ref.get("copy_id", ""))
		var ability_id := str(ability_ref.get("ability_id", ""))
		var definition: Dictionary = catalog.get(ability_id, {})
		var model: Dictionary = ability_ref.duplicate(true)
		model.merge(definition, true)
		_abilities[copy_id] = model
		var legal := bool(model.get(
			"legal", _timing_allows(int(model.get("timing", -1)), phase)
		))
		if legal:
			_legal_ids.append(copy_id)
		var button := Button.new()
		button.text = "%s\n%s\n%s" % [
			str(model.get("label", ability_id.replace("_", " ").capitalize())),
			_timing_name(int(model.get("timing", -1))),
			str(model.get("rules_text", "")),
		]
		button.disabled = not legal or _input_locked
		button.gui_input.connect(func(event: InputEvent): _on_ability_gui_input(event, button))
		_cards.add_child(button)
		_button_copy_ids[button.get_instance_id()] = copy_id
	_drawer.visible = _expanded
	_toggle.text = "ABILITIES  %d  %s" % [abilities.size(), "▼" if _expanded else "▲"]
	_toggle.disabled = abilities.is_empty()


func legal_ability_ids() -> Array[StringName]:
	return _legal_ids.duplicate()


func inputs_locked() -> bool:
	return _input_locked


func activate_ability(copy_id: StringName) -> void:
	if _input_locked or copy_id not in _legal_ids or not _abilities.has(copy_id):
		return
	ability_activated.emit(copy_id, _abilities[copy_id].duplicate(true))


func _on_toggle_pressed() -> void:
	_expanded = not _expanded
	_drawer.visible = _expanded
	_toggle.text = "ABILITIES  %d  %s" % [_abilities.size(), "▼" if _expanded else "▲"]


func _on_ability_gui_input(event: InputEvent, button: Button) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		activate_ability(_button_copy_ids.get(button.get_instance_id(), &""))
		button.accept_event()


func _timing_allows(timing: int, phase: int) -> bool:
	match timing:
		0:
			return phase == 3
		1, 3:
			return phase == 2
		2:
			return phase == 2 or phase == 4
	return false


func _timing_name(timing: int) -> String:
	return ["HAND MANIPULATION", "FIELD · MAIN 1", "BUFF / NERF", "SABOTAGE · MAIN 1"][timing] if timing >= 0 and timing <= 3 else "UNCONFIGURED"
