extends Control

signal back_requested

const DisplayPreferences = preload("res://src/view/app/display_preferences.gd")

@onready var _modes: OptionButton = $Content/Modes


func _ready() -> void:
	DisplayPreferences.populate_modes(_modes)
	_modes.item_selected.connect(_on_display_mode_selected)
	$Content/BackButton.pressed.connect(func(): back_requested.emit())
	$Content/BackButton.grab_focus()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _modes.get_popup().visible:
		get_viewport().set_input_as_handled()
		back_requested.emit()


func _on_display_mode_selected(index: int) -> void:
	var mode := _modes.get_item_id(index)
	DisplayPreferences.apply(get_window(), mode)
	DisplayPreferences.save_mode(mode)
