extends RefCounted

signal draw_speed_changed(speed: int)

const PATH := "user://gameplay.cfg"
const DRAW_SKIP := 0
const DRAW_NORMAL := 1
const DRAW_FAST := 2
const SOUND_EFFECTS := &"Sound Effects"
const AMBIENT := &"Ambient"
const MUSIC := &"Music"
const VOLUME_KEYS := {SOUND_EFFECTS: "sound_effects", AMBIENT: "ambient", MUSIC: "music"}
const HOTKEY_READY := &"ready"
const HOTKEY_ABILITIES := &"abilities"
const HOTKEY_HISTORY := &"history"
const DEFAULT_HOTKEYS := {HOTKEY_READY: KEY_SPACE, HOTKEY_ABILITIES: KEY_A, HOTKEY_HISTORY: KEY_H}
const HOTKEY_LABELS := {
	HOTKEY_READY: "Ready", HOTKEY_ABILITIES: "Toggle ability tray", HOTKEY_HISTORY: "Toggle history",
}

var draw_speed: int:
	get:
		var saved: Variant = _config.get_value("animation", "draw_speed", DRAW_NORMAL)
		return saved if saved is int and saved in [DRAW_SKIP, DRAW_NORMAL, DRAW_FAST] else DRAW_NORMAL

var _path: String
var _config := ConfigFile.new()


func _init(path: String = PATH) -> void:
	_path = path
	_config.load(_path)


func set_draw_speed(speed: int) -> void:
	if speed == draw_speed or speed not in [DRAW_SKIP, DRAW_NORMAL, DRAW_FAST]:
		return
	_config.set_value("animation", "draw_speed", speed)
	draw_speed_changed.emit(speed)
	_save()


func volume(bus: StringName) -> int:
	var saved: Variant = _config.get_value("audio", VOLUME_KEYS[bus], 100)
	return clampi(saved, 0, 100) if saved is int else 100


func set_volume(bus: StringName, percent: int) -> void:
	percent = clampi(percent, 0, 100)
	if volume(bus) == percent:
		return
	_config.set_value("audio", VOLUME_KEYS[bus], percent)
	_apply_volume(bus, percent)
	_save()


func apply_audio() -> void:
	for bus in VOLUME_KEYS:
		_apply_volume(bus, volume(bus))


func hotkey(action: StringName) -> int:
	var fallback: int = DEFAULT_HOTKEYS.get(action, 0)
	var saved: Variant = _config.get_value("hotkeys", str(action), fallback)
	return saved if saved is int and saved > 0 else fallback


func hotkey_action(keycode: int) -> StringName:
	for action: StringName in DEFAULT_HOTKEYS:
		if hotkey(action) == keycode:
			return action
	return &""


func set_hotkey(action: StringName, keycode: int) -> bool:
	if not DEFAULT_HOTKEYS.has(action) or keycode <= 0:
		return false
	var assigned := hotkey_action(keycode)
	if not assigned.is_empty() and assigned != action:
		return false
	if hotkey(action) != keycode:
		_config.set_value("hotkeys", str(action), keycode)
		_save()
	return true


func reset_hotkeys() -> void:
	if _config.has_section("hotkeys"):
		_config.erase_section("hotkeys")
		_save()


func _apply_volume(bus: StringName, percent: int) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, percent == 0)
	if percent > 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(percent / 100.0))


func _save() -> void:
	var result := _config.save(_path)
	if result != OK:
		push_warning("Could not save gameplay preferences: %s" % error_string(result))
