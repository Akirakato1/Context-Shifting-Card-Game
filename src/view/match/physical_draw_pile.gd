@tool
extends Control

const STACK_BASE_Y := 66.0
const MAX_HEIGHT := 25.0
const LAYER_GAP := 2.7
static var _face_uvs := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])

@export var pile_name := "":
	set(value):
		pile_name = value
		_update_labels()
@export var accent_color := Color("d0ae77"):
	set(value):
		accent_color = value
		_update_labels()
		queue_redraw()
@export var landscape := false:
	set(value):
		landscape = value
		queue_redraw()
## Context half-card artwork used on both halves of the pile's top card.
@export var context_half_art: Texture2D:
	set(value):
		context_half_art = value
		queue_redraw()
## Optional full card-back illustration projected onto the top of the stack.
@export var top_art: Texture2D:
	set(value):
		top_art = value
		queue_redraw()
## Optional full-height edge illustration, cropped as the stack gets shorter.
@export var edge_art: Texture2D:
	set(value):
		edge_art = value
		queue_redraw()

var _draw_count := -1
var _capacity := 0
var _active := false

const GameIcons := preload("res://src/view/common/game_icons.gd")

@onready var _name_label: Label = $Name
@onready var _context_icon: TextureRect = $ContextIcon
@onready var _count_label: Label = $Count


func _ready() -> void:
	resized.connect(queue_redraw)
	_update_labels()


func render(draw_count: int, capacity: int, active: bool = false) -> void:
	_draw_count = draw_count
	_capacity = maxi(capacity, 1)
	_active = active
	_update_labels()
	queue_redraw()


func draw_origin() -> Vector2:
	var top := _face_at_height(_stack_height())
	return get_global_transform_with_canvas() * ((top[0] + top[2]) * 0.5)


func _update_labels() -> void:
	if _name_label == null:
		return
	_name_label.text = pile_name
	_name_label.add_theme_color_override("font_color", accent_color.lightened(0.42))
	_context_icon.texture = GameIcons.context(GameIcons.CONTEXT_NAMES.find(pile_name))
	_context_icon.visible = _context_icon.texture != null
	_context_icon.tooltip_text = pile_name
	_name_label.visible = not _context_icon.visible
	_count_label.text = "Hidden" if _draw_count < 0 else "%d left" % _draw_count


func _stack_height() -> float:
	if _draw_count < 0:
		return MAX_HEIGHT * 0.55
	return MAX_HEIGHT * clampf(float(_draw_count) / _capacity, 0.0, 1.0)


func _face_at_height(height: float) -> PackedVector2Array:
	var width := 112.0 if landscape else 76.0
	var depth := 36.0 if landscape else 46.0
	var skew := 17.0 if landscape else 22.0
	var bottom_left := Vector2((size.x - width - skew) * 0.5, STACK_BASE_Y - height)
	var back_left := bottom_left + Vector2(skew, -depth)
	var across := Vector2(width, 0.0)
	return PackedVector2Array([back_left, back_left + across, bottom_left + across, bottom_left])


func _draw() -> void:
	var floor_face := _face_at_height(0.0)
	var shadow := Transform2D(0.0, Vector2(3.0, 4.0)) * floor_face
	draw_colored_polygon(shadow, Color(0.046, 0.035, 0.026, 0.36))
	var height := _stack_height()
	if is_zero_approx(height):
		draw_colored_polygon(floor_face, Color(accent_color, 0.13))
		_outline_face(floor_face, Color(accent_color, 0.42), 1.5)
		return
	var top := _face_at_height(height)
	_draw_edges(top, floor_face, height)
	_draw_top(top)


func _draw_edges(top: PackedVector2Array, floor_face: PackedVector2Array, height: float) -> void:
	var front := PackedVector2Array([top[3], top[2], floor_face[2], floor_face[3]])
	var side := PackedVector2Array([top[1], top[2], floor_face[2], floor_face[1]])
	draw_colored_polygon(front, Color("c9b59a").lerp(accent_color, 0.18))
	draw_colored_polygon(side, Color("83705b").lerp(accent_color, 0.20))
	if edge_art != null:
		var fraction := height / MAX_HEIGHT
		var edge_uvs := PackedVector2Array([
			Vector2.ZERO, Vector2.RIGHT, Vector2(1.0, fraction), Vector2(0.0, fraction),
		])
		draw_colored_polygon(front, Color.WHITE, edge_uvs, edge_art)
		draw_colored_polygon(side, Color("9f9381"), edge_uvs, edge_art)
	else:
		for layer in range(1, ceili(height / LAYER_GAP)):
			var offset := Vector2(0.0, layer * LAYER_GAP)
			draw_line(front[0] + offset, front[1] + offset, Color(0.23, 0.17, 0.13, 0.48), 1.0)
			draw_line(side[0] + offset, side[1] + offset, Color(0.17, 0.13, 0.10, 0.52), 1.0)
	draw_line(floor_face[3], floor_face[2], Color("534337"), 1.3, true)
	draw_line(floor_face[2], floor_face[1], Color("45372f"), 1.3, true)


func _draw_top(top: PackedVector2Array) -> void:
	draw_colored_polygon(top, accent_color.darkened(0.68))
	if top_art != null:
		draw_colored_polygon(top, Color.WHITE, _face_uvs, top_art)
	elif context_half_art != null:
		var crop := CardWidget.CARD_ART_REGION
		var texture_size := context_half_art.get_size()
		var half_uvs := PackedVector2Array()
		for corner in _face_uvs:
			half_uvs.append((crop.position + corner * crop.size) / texture_size)
		draw_colored_polygon(top, Color.WHITE, half_uvs, context_half_art)
		# The bottom is the same crop turned 180 degrees, as on a hand card.
		var flipped := PackedVector2Array([half_uvs[2], half_uvs[3], half_uvs[0], half_uvs[1]])
		draw_colored_polygon(top, Color.WHITE, flipped, context_half_art)
	else:
		_draw_ability_back(top)
	var border := Color(accent_color.lightened(0.42), 0.86)
	_outline_face(top, Color("ffdda1") if _active else border, 2.3 if _active else 1.15)


func _draw_ability_back(top: PackedVector2Array) -> void:
	var center := (top[0] + top[2]) * 0.5
	var frame := PackedVector2Array()
	for corner in top:
		frame.append(center.lerp(corner, 0.82))
	_outline_face(frame, Color(accent_color, 0.58), 1.05)
	var along := (top[1] - top[0]) * 0.20
	var across := (top[3] - top[0]) * 0.24
	var emblem := PackedVector2Array([center - across, center + along, center + across, center - along])
	draw_colored_polygon(emblem, Color(accent_color, 0.26))
	_outline_face(emblem, Color(accent_color, 0.94), 1.15)
	draw_line(center - along * 0.52, center + along * 0.52, Color(accent_color, 0.7), 1.1, true)


func _outline_face(face: PackedVector2Array, color: Color, width: float) -> void:
	var outline := face.duplicate()
	outline.append(face[0])
	draw_polyline(outline, color, width, true)
