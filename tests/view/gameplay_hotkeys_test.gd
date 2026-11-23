extends "res://tests/test_case.gd"

const App := preload("res://src/view/app/app_root.tscn")
const Preferences := preload("res://src/view/app/gameplay_preferences.gd")
const DisplayPreferences := preload("res://src/view/app/display_preferences.gd")
const Settings := preload("res://src/view/lobby/general_settings_screen.tscn")
const MatchFixture := preload("res://tests/view/match_screen_test.gd")


func test_default_match_hotkeys_ready_and_toggle_the_drawers() -> void:
	var app = App.instantiate()
	app.gameplay_preferences = Preferences.new("user://shift-hotkey-defaults-%d.cfg" % Time.get_ticks_usec())
	var window: Window = Engine.get_main_loop().root
	window.add_child(app)
	var model := MatchFixture.new()._active_player_model()
	model["phase"] = 2
	model["private_abilities"] = [{"copy_id": "field-copy", "ability_id": "reverse_cycle", "legal": true}]
	app.show_screen(&"match", model)
	var match_view: Control = app.get_node("SafeArea/ScreenHost").get_child(0)
	var requests: Array[StringName] = []
	app.game_intent_requested.connect(func(kind: StringName, _payload: Dictionary): requests.append(kind))
	await Engine.get_main_loop().process_frame
	_press(window, KEY_A)
	assert_true(match_view.get_node("AbilityPanel/Drawer").visible)
	_press(window, KEY_H)
	assert_true(match_view.get_node("AbilityHistory/Drawer").visible)
	_press(window, KEY_SPACE)
	_press(window, KEY_SPACE, true)
	assert_eq(requests, [&"set_ready"])
	match_view.settings_requested.emit()
	_press(window, KEY_H)
	assert_true(match_view.get_node("AbilityHistory/Drawer").visible)
	app.queue_free()
	await Engine.get_main_loop().process_frame


func test_settings_can_change_and_restore_a_saved_binding() -> void:
	var path := "user://shift-hotkey-settings-%d.cfg" % Time.get_ticks_usec()
	var prefs: Variant = Preferences.new(path)
	var screen: Control = Settings.instantiate()
	screen.set("preferences", prefs)
	var window: Window = Engine.get_main_loop().root
	window.add_child(screen)
	await Engine.get_main_loop().process_frame
	var status: Label = screen.get_node("Content/DisplayStatus")
	assert_true(status.text.contains("%d × %d" % [window.size.x, window.size.y]))
	assert_true(screen.has_node("Content/CopyDisplayDiagnostics"))
	assert_true(DisplayPreferences.describe_window(1440, Vector2i(1920, 1080)).ends_with("below selected size"))
	assert_false(DisplayPreferences.describe_window(1440, Vector2i(2560, 1440)).ends_with("below selected size"))
	var binding := screen.get_node_or_null("Content/Hotkeys/ready/Binding") as Button
	assert_true(binding != null)
	if binding != null:
		binding.pressed.emit()
		_press(window, KEY_H)
		assert_eq(prefs.hotkey(&"ready"), KEY_SPACE)
		_press(window, KEY_R)
		assert_eq(prefs.hotkey(&"ready"), KEY_R)
		var reloaded: Variant = Preferences.new(path)
		assert_eq(reloaded.hotkey(&"ready"), KEY_R)
		screen.get_node("Content/Hotkeys/Heading/Reset").pressed.emit()
		assert_eq(prefs.hotkey(&"ready"), KEY_SPACE)
	screen.queue_free()
	await Engine.get_main_loop().process_frame
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _press(window: Window, keycode: Key, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.echo = echo
	window.push_input(event)
