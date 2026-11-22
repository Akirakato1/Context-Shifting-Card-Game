extends Control

const Clock := preload("res://assets/artwork/board/figma/context_clock.svg")
const Edge := preload("res://assets/artwork/board/figma/table_edge_left.svg")
const FarEdge := preload("res://assets/artwork/board/figma/table_edge_top.svg")
const Emblems := [
	preload("res://assets/artwork/context_emblems/context_emblem_rish.png"),
	preload("res://assets/artwork/context_emblems/context_emblem_flourish.png"),
	preload("res://assets/artwork/context_emblems/context_emblem_fall.png"),
]
const COLORS := [Color("d7ad77"), Color("94bd9b"), Color("9db5ca")]
const BACKGROUND := [Color("2c2330"), Color("142f31"), Color("202c48")]
const BASE := Vector2(1920, 1080)

@export var rise_background: Texture2D
@export var flourish_background: Texture2D
@export var fall_background: Texture2D
@export_group("Table and HUD Artwork")
@export var show_placeholder_guides := true
@export var table_art: Texture2D
@export var lower_bar_art: Texture2D
@export var hand_tray_art: Texture2D
@export var score_bar_art: Texture2D
@export_group("Context Clock Artwork")
@export var clock_housing_art: Texture2D
@export var clock_face_art: Texture2D
@export var clock_pointer_art: Texture2D
@export var cycle_arrow_art: Texture2D

var _context := -1
var _direction := 1
var _active: Array = [0]
var _blend := [1.0, 0.0, 0.0]
var _transition: Tween
var _show_score_bar := false


func _ready() -> void:
	resized.connect(queue_redraw)


func render(context: int, direction: int, active: Array, show_score_bar: bool = false) -> void:
	context = clampi(context, 0, 2)
	if _context != context:
		if _transition != null: _transition.kill()
		if _context < 0:
			_set_backdrop_weights(1.0, Vector3.ZERO, context)
		else:
			_transition = create_tween()
			_transition.tween_method(
				_set_backdrop_weights.bind(Vector3(_blend[0], _blend[1], _blend[2]), context),
				0.0, 1.0, 0.42
			)
		_context = context
	_direction = direction
	_active = active.duplicate()
	_show_score_bar = show_score_bar
	queue_redraw()


func _set_backdrop_weights(progress: float, previous: Vector3, context: int) -> void:
	for i in range(3):
		_blend[i] = lerpf(previous[i], 1.0 if i == context else 0.0, progress)
	queue_redraw()


func _draw() -> void:
	var scale_to_view := size / BASE
	draw_set_transform(Vector2.ZERO, 0.0, scale_to_view)
	var backdrop := Color(0.0, 0.0, 0.0, 0.0)
	for i in range(3):
		backdrop += BACKGROUND[i] * float(_blend[i])
	backdrop.a = 1
	if show_placeholder_guides:
		draw_rect(Rect2(Vector2.ZERO, BASE), backdrop)
	var art := [rise_background, flourish_background, fall_background]
	for i in range(3):
		if art[i] != null and _blend[i] > 0:
			draw_texture_rect(art[i], Rect2(Vector2.ZERO, BASE), false, Color(1, 1, 1, _blend[i]))

	if table_art != null:
		draw_texture_rect(table_art, Rect2(232, 260, 1588, 462), false)
	elif show_placeholder_guides:
		var a := Vector2(630, 260)
		var b := Vector2(1417, 260)
		var c := Vector2(1820, 710)
		var d := Vector2(232, 710)
		draw_colored_polygon(PackedVector2Array([a, b, c, d]), Color("33404a"))
		draw_colored_polygon(PackedVector2Array([d, c, c + Vector2(0, 12), d + Vector2(0, 12)]), Color("1a2029"))
		_draw_edge(FarEdge, a, b, scale_to_view)
		_draw_edge(Edge, a, d, scale_to_view)
		_draw_edge(Edge, b, c, scale_to_view)
		draw_set_transform(Vector2.ZERO, 0.0, scale_to_view)
	_draw_surface(lower_bar_art, Rect2(0, 710, 1920, 370), Color("202a35"))
	_draw_surface(clock_housing_art, Rect2(19, 731, 324, 327), Color("151d26"))
	_draw_surface(hand_tray_art, Rect2(369, 731, 1247, 327), Color("151d26"))
	if _show_score_bar:
		_draw_surface(score_bar_art, Rect2(361, 662, 1246, 48), Color("202a35"))
	_draw_clock(scale_to_view)


func _draw_surface(texture: Texture2D, rect: Rect2, guide_color: Color) -> void:
	if texture != null:
		draw_texture_rect(texture, rect, false)
	elif show_placeholder_guides:
		draw_rect(rect, guide_color)


func _draw_edge(texture: Texture2D, start: Vector2, end: Vector2, view_scale: Vector2) -> void:
	var delta := (end - start) * view_scale
	draw_set_transform(start * view_scale, delta.angle())
	draw_texture_rect(texture, Rect2(0, -1, delta.length(), 2), false, Color("d9e2eb"))


func _draw_clock(view_scale: Vector2) -> void:
	var face := clock_face_art if clock_face_art != null else (Clock if show_placeholder_guides else null)
	if face != null:
		draw_texture_rect(face, Rect2(28, 738, 301, 309), false)
	var center := Vector2(179, 891)
	var points := [Vector2(179, 790), Vector2(266, 944), Vector2(92, 944)]
	for i in 3:
		var next := posmod(i + _direction, 3)
		var start: Vector2 = points[i].move_toward(points[next], 40)
		var end: Vector2 = points[next].move_toward(points[i], 40)
		_draw_clock_arrow(cycle_arrow_art, start, end, view_scale, Color("a8afbd"), 2.0, 20.0)
	for i in range(3):
		var fg: Color = COLORS[i] if i in _active else Color("a8afbd")
		if show_placeholder_guides and clock_face_art == null:
			draw_circle(points[i], 31, Color("344152"))
			draw_arc(points[i], 31, 0, TAU, 36, fg, 3 if i == _context else 1, true)
		var emblem_size := Vector2(39, 39)
		draw_texture_rect(Emblems[i], Rect2(points[i] - emblem_size / 2, emblem_size), false, fg)
	var direction: Vector2 = (points[clampi(_context, 0, 2)] - center).normalized()
	_draw_clock_arrow(clock_pointer_art, center, center + direction * 50, view_scale, Color("e9eff5"), 4.0, 20.0)
	if show_placeholder_guides and clock_pointer_art == null:
		draw_circle(center, 5, Color("e9eff5"))


func _draw_clock_arrow(texture: Texture2D, start: Vector2, end: Vector2, view_scale: Vector2,
		guide_color: Color, guide_width: float, texture_height: float) -> void:
	if texture != null:
		var delta := (end - start) * view_scale
		var height := texture_height * minf(view_scale.x, view_scale.y)
		draw_set_transform(start * view_scale, delta.angle())
		draw_texture_rect(texture, Rect2(0, -height / 2, delta.length(), height), false)
		draw_set_transform(Vector2.ZERO, 0.0, view_scale)
	elif show_placeholder_guides:
		draw_line(start, end, guide_color, guide_width, true)
		_arrow_tip(end, (end - start).angle(), guide_color)


func _arrow_tip(end: Vector2, angle: float, color: Color) -> void:
	var rear := Vector2.from_angle(angle) * 10
	var side := rear.orthogonal() * 0.5
	draw_colored_polygon(PackedVector2Array([end, end - rear + side, end - rear - side]), color)
