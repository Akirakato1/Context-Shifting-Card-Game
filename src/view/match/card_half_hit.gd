extends Control

var hit_polygon := PackedVector2Array()
var foreground_polygon := PackedVector2Array()


func _has_point(point: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, size).has_point(point):
		return false
	if hit_polygon.is_empty():
		return true
	var normalized := point / size
	return (
		Geometry2D.is_point_in_polygon(normalized, hit_polygon)
		and not Geometry2D.is_point_in_polygon(normalized, foreground_polygon)
	)
