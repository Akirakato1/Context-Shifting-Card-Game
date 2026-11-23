extends Control

signal back_requested

const DisplayPreferences = preload("res://src/view/app/display_preferences.gd")
const GameplayPreferences = preload("res://src/view/app/gameplay_preferences.gd")

var preferences: GameplayPreferences
var _binding_action: StringName
var _binding_buttons: Dictionary[StringName, Button] = {}
@onready var _modes: OptionButton = $Content/Modes
@onready var _draw_speed: OptionButton = $Content/DrawSpeed
@onready var _hotkeys: VBoxContainer = $Content/Hotkeys
@onready var _hotkey_status: Label = $Content/HotkeyStatus


func _ready() -> void:
	if preferences == null:
		preferences = GameplayPreferences.new()
	DisplayPreferences.populate_modes(_modes)
	_modes.item_selected.connect(_on_display_mode_selected)
	_draw_speed.add_item("Skip", GameplayPreferences.DRAW_SKIP)
	_draw_speed.add_item("1.0×", GameplayPreferences.DRAW_NORMAL)
	_draw_speed.add_item("2.0×", GameplayPreferences.DRAW_FAST)
	_draw_speed.select(_draw_speed.get_item_index(preferences.draw_speed))
	_draw_speed.item_selected.connect(func(index: int): preferences.set_draw_speed(_draw_speed.get_item_id(index)))
	_bind_volume($Content/SoundEffects, GameplayPreferences.SOUND_EFFECTS)
	_bind_volume($Content/Ambient, GameplayPreferences.AMBIENT)
	_bind_volume($Content/Music, GameplayPreferences.MUSIC)
	_build_hotkeys()
	var back: Button = $Content/BackButton
	back.pressed.connect(func(): back_requested.emit())
	var focus_order: Array[Control] = [
		_modes, _draw_speed, $Content/SoundEffects/Slider, $Content/Ambient/Slider, $Content/Music/Slider,
	]
	for binding: Button in _binding_buttons.values():
		focus_order.append(binding)
	focus_order.append_array([_hotkeys.get_node("Heading/Reset"), back])
	_link_focus(focus_order)
	back.grab_focus()


func _input(event: InputEvent) -> void:
	if not _binding_action.is_empty() and event is InputEventKey:
		get_viewport().set_input_as_handled()
		if event.pressed and not event.echo:
			_capture_binding(event)
		return
	if event.is_action_pressed("ui_cancel") and not _modes.get_popup().visible and not _draw_speed.get_popup().visible:
		get_viewport().set_input_as_handled()
		back_requested.emit()


func _on_display_mode_selected(index: int) -> void:
	var mode := _modes.get_item_id(index)
	DisplayPreferences.apply(get_window(), mode)
	DisplayPreferences.save_mode(mode)


func _bind_volume(row: HBoxContainer, bus: StringName) -> void:
	var slider: HSlider = row.get_node("Slider")
	var value_label: Label = row.get_node("Value")
	var percent := preferences.volume(bus)
	slider.set_value_no_signal(percent)
	value_label.text = "%d%%" % percent
	slider.value_changed.connect(func(value: float):
		var next := roundi(value)
		value_label.text = "%d%%" % next
		preferences.set_volume(bus, next)
	)


func _build_hotkeys() -> void:
	for action: StringName in GameplayPreferences.HOTKEY_LABELS:
		var row := HBoxContainer.new()
		row.name = action
		var label := Label.new()
		label.text = GameplayPreferences.HOTKEY_LABELS[action]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var binding := Button.new()
		binding.name = "Binding"
		binding.custom_minimum_size = Vector2(182, 32)
		binding.tooltip_text = "Click to change. Escape cancels."
		binding.pressed.connect(_begin_binding.bind(action))
		_binding_buttons[action] = binding
		_hotkeys.add_child(row)
		row.add_child(label)
		row.add_child(binding)
	_hotkeys.get_node("Heading/Reset").pressed.connect(_reset_bindings)
	_refresh_bindings()


func _begin_binding(action: StringName) -> void:
	_binding_action = action
	_hotkey_status.hide()
	_refresh_bindings()


func _capture_binding(event: InputEventKey) -> void:
	if event.keycode == KEY_ESCAPE:
		_end_binding()
		return
	if event.keycode in [KEY_NONE, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_TAB]:
		return
	var code := event.get_keycode_with_modifiers()
	if not preferences.set_hotkey(_binding_action, code):
		var assigned := preferences.hotkey_action(code)
		_hotkey_status.text = "%s is already assigned to %s." % [
			OS.get_keycode_string(code), GameplayPreferences.HOTKEY_LABELS.get(assigned, "another action"),
		]
		_hotkey_status.show()
		return
	_end_binding()


func _reset_bindings() -> void:
	preferences.reset_hotkeys()
	_end_binding()


func _end_binding() -> void:
	_binding_action = &""
	_hotkey_status.hide()
	_refresh_bindings()


func _refresh_bindings() -> void:
	for action: StringName in _binding_buttons:
		_binding_buttons[action].text = (
			"Press a key…" if _binding_action == action else OS.get_keycode_string(preferences.hotkey(action))
		)


func _link_focus(controls: Array[Control]) -> void:
	for i in controls.size():
		var control := controls[i]
		control.focus_previous = control.get_path_to(controls[posmod(i - 1, controls.size())])
		control.focus_next = control.get_path_to(controls[(i + 1) % controls.size()])
		control.focus_neighbor_top = control.focus_previous
		control.focus_neighbor_bottom = control.focus_next
