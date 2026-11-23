extends Resource

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


func apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_apply_cursor(pointer_texture, Input.CURSOR_ARROW, pointer_hotspot)
	_apply_cursor(hover_texture, Input.CURSOR_POINTING_HAND, hover_hotspot)
	_apply_cursor(target_texture, Input.CURSOR_CROSS, target_hotspot)
	_apply_cursor(drag_texture, Input.CURSOR_DRAG, drag_hotspot)
	_apply_cursor(drop_texture, Input.CURSOR_CAN_DROP, drop_hotspot)
	_apply_cursor(blocked_texture, Input.CURSOR_FORBIDDEN, blocked_hotspot)


func _apply_cursor(texture: Texture2D, shape: Input.CursorShape, hotspot: Vector2) -> void:
	if texture == null:
		return
	var max_hotspot := (texture.get_size() - Vector2.ONE).max(Vector2.ZERO)
	Input.set_custom_mouse_cursor(texture, shape, hotspot.clamp(Vector2.ZERO, max_hotspot))
