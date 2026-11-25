extends Resource

const MAX_CURSOR_EDGE := 36.0

## Hotspots are specified in pixels on the source textures, including their transparent margins.
@export_group("Default pointer", "pointer_")
@export var pointer_texture: Texture2D
@export var pointer_hotspot := Vector2.ZERO
@export_group("Hover over a card or action", "hover_")
@export var hover_texture: Texture2D
@export var hover_hotspot := Vector2.ZERO
@export_group("Select an ability target", "target_")
@export var target_texture: Texture2D
@export var target_hotspot := Vector2.ZERO
@export_group("Drag a card", "drag_")
@export var drag_texture: Texture2D
@export var drag_hotspot := Vector2.ZERO
@export_group("Drop a card", "drop_")
@export var drop_texture: Texture2D
@export var drop_hotspot := Vector2.ZERO
@export_group("Blocked action", "blocked_")
@export var blocked_texture: Texture2D
@export var blocked_hotspot := Vector2.ZERO

var _installed_shapes: Array[int] = []


func apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	clear()
	_apply_cursor(pointer_texture, Input.CURSOR_ARROW, pointer_hotspot)
	_apply_cursor(hover_texture, Input.CURSOR_POINTING_HAND, hover_hotspot)
	_apply_cursor(target_texture, Input.CURSOR_CROSS, target_hotspot)
	_apply_cursor(drag_texture, Input.CURSOR_DRAG, drag_hotspot)
	_apply_cursor(drop_texture, Input.CURSOR_CAN_DROP, drop_hotspot)
	_apply_cursor(blocked_texture, Input.CURSOR_FORBIDDEN, blocked_hotspot)


func clear() -> void:
	for shape in _installed_shapes:
		Input.set_custom_mouse_cursor(null, shape)
	_installed_shapes.clear()


func _apply_cursor(texture: Texture2D, shape: Input.CursorShape, hotspot: Vector2) -> void:
	if texture == null:
		return
	var pixels := _cursor_pixels(texture, hotspot)
	if not pixels.is_empty():
		Input.set_custom_mouse_cursor(pixels[0], shape, pixels[1])
		_installed_shapes.append(shape)


func _cursor_pixels(texture: Texture2D, hotspot: Vector2) -> Array:
	var original_size := texture.get_size()
	if maxf(original_size.x, original_size.y) <= MAX_CURSOR_EDGE:
		return [texture, hotspot.clamp(Vector2.ZERO, (original_size - Vector2.ONE).max(Vector2.ZERO))]
	var image := texture.get_image()
	if image == null or (image.is_compressed() and image.decompress() != OK):
		return []
	var bounds := image.get_used_rect()
	if not bounds.has_area():
		return []
	var scale := minf(1.0, MAX_CURSOR_EDGE / maxf(bounds.size.x, bounds.size.y))
	var cursor_size := (Vector2(bounds.size) * scale).round().max(Vector2.ONE)
	var cursor_image := image.get_region(bounds)
	cursor_image.resize(int(cursor_size.x), int(cursor_size.y), Image.INTERPOLATE_LANCZOS)
	var cursor_hotspot := ((hotspot - Vector2(bounds.position)) * cursor_size / Vector2(bounds.size)).round()
	return [ImageTexture.create_from_image(cursor_image), cursor_hotspot.clamp(Vector2.ZERO, cursor_size - Vector2.ONE)]
