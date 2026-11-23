extends RefCounted

const PATH := "user://display.cfg"
const FULLSCREEN := 0
const DEFAULT_HEIGHT := 720
const WINDOW_HEIGHTS := [720, 900, 1080, 1440, 2160]
const FRAME_ALLOWANCE := Vector2i(24, 64)


static func load_mode() -> int:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		var mode: Variant = config.get_value("display", "mode", DEFAULT_HEIGHT)
		if mode is int and (mode == FULLSCREEN or mode in WINDOW_HEIGHTS):
			return mode
	return DEFAULT_HEIGHT


static func save_mode(mode: int) -> void:
	var config := ConfigFile.new()
	config.set_value("display", "mode", mode)
	var result := config.save(PATH)
	if result != OK:
		push_warning("Could not save display preferences: %s" % error_string(result))


static func window_size_for(height: int) -> Vector2i:
	return Vector2i(roundi(height * 16.0 / 9.0), height)


static func describe_window(mode: int, actual: Vector2i) -> String:
	var label := "Actual window · %d × %d px" % [actual.x, actual.y]
	if mode != FULLSCREEN:
		var requested := window_size_for(mode)
		if actual.x < requested.x or actual.y < requested.y:
			label += " · below selected size"
	return label


static func populate_modes(option: OptionButton) -> void:
	for height: int in WINDOW_HEIGHTS:
		var dimensions := window_size_for(height)
		option.add_item("%d × %d" % [dimensions.x, dimensions.y], height)
	option.add_item("Fullscreen (display resolution)", FULLSCREEN)
	option.select(option.get_item_index(load_mode()))


static func apply(window: Window, mode: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if mode == FULLSCREEN:
		window.mode = Window.MODE_FULLSCREEN
		return
	window.mode = Window.MODE_WINDOWED
	var desktop := DisplayServer.screen_get_usable_rect(window.current_screen)
	var requested_size := window_size_for(mode)
	if desktop.has_area():
		var available := desktop.size - FRAME_ALLOWANCE
		var scale := clampf(minf(
			float(available.x) / requested_size.x, float(available.y) / requested_size.y
		), 0.1, 1.0)
		window.size = Vector2i(Vector2(requested_size) * scale)
		window.position = desktop.position + (desktop.size - window.size) / 2
	else:
		window.size = requested_size
