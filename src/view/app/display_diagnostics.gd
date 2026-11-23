extends RefCounted

const DisplayPreferences := preload("res://src/view/app/display_preferences.gd")
const PATH := "user://display-diagnostics.log"


static func record(window: Window, mode: int, event: String, new_session := false) -> String:
	if DisplayServer.get_name() == "headless":
		return ""
	var report := "Zeitklus display diagnostics\n"
	if not new_session and FileAccess.file_exists(PATH):
		report = FileAccess.get_file_as_string(PATH)
	report += "\n" + JSON.stringify(_snapshot(window, mode, event), "  ") + "\n"
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
	else:
		push_warning("Could not save display diagnostics: %s" % error_string(FileAccess.get_open_error()))
	return report


static func _snapshot(window: Window, mode: int, event: String) -> Dictionary:
	var screen := window.current_screen
	return {
		"event": event,
		"utc": Time.get_datetime_string_from_system(true) + "Z",
		"godot": Engine.get_version_info().get("string", ""),
		"reported_os": OS.get_name(),
		"reported_os_version": OS.get_version(),
		"display_backend": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"render_driver": RenderingServer.get_current_rendering_driver_name(),
		"graphics_adapter": RenderingServer.get_video_adapter_name(),
		"selected_mode": "fullscreen" if mode == DisplayPreferences.FULLSCREEN else "windowed",
		"requested_window_px": "display resolution" if mode == DisplayPreferences.FULLSCREEN else _dimensions(DisplayPreferences.window_size_for(mode)),
		"actual_window_mode": ["windowed", "minimized", "maximized", "fullscreen", "exclusive fullscreen"][window.mode],
		"native_window_px": _dimensions(DisplayServer.window_get_size(window.get_window_id())),
		"godot_window_px": _dimensions(window.size),
		"viewport_texture_px": _dimensions(window.get_texture().get_size()),
		"logical_viewport_size": _dimensions(Vector2i(window.get_visible_rect().size)),
		"design_size": _dimensions(window.content_scale_size),
		"content_scale_mode": ["disabled", "canvas items", "viewport"][window.content_scale_mode],
		"content_scale_factor": window.content_scale_factor,
		"allow_hidpi": ProjectSettings.get_setting("display/window/dpi/allow_hidpi", true),
		"screen_px": _dimensions(DisplayServer.screen_get_size(screen)),
		"usable_screen_px": _dimensions(DisplayServer.screen_get_usable_rect(screen).size),
		"reported_screen_dpi": DisplayServer.screen_get_dpi(screen),
		"reported_screen_scale": DisplayServer.screen_get_scale(screen),
	}


static func _dimensions(size: Vector2i) -> String:
	return "%d x %d" % [size.x, size.y]
