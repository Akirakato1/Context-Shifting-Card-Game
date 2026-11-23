extends Control

const Edge := preload("res://assets/artwork/board/figma/table_edge_left.svg")
const FarEdge := preload("res://assets/artwork/board/figma/table_edge_top.svg")
const ContextBlend := preload("res://src/view/match/context_art_blend.gdshader")
const CONTEXT_KEYS: Array[String] = ["rise", "flourish", "fall"]
const BACKGROUND := [Color("2c2330"), Color("142f31"), Color("202c48")]
const BASE := Vector2(1920, 1080)
const TABLE_RECT := Rect2(142, 282, 1636, 476)
const CLOCK_RECT := Rect2(26, 740, 306, 306)
const HOTBAR_TOP := 710.0
const SCORE_BAR_TOP := 662.0
const HAND_TRAY_RECT := Rect2(349, 718, 1271, 350)
const TABLE_SHADE_OPACITY := 0.5
const CONTEXT_TRANSITION_SECONDS := 0.42

@export var rise_background: Texture2D = preload("res://assets/artwork/background/background_rise.png")
@export var flourish_background: Texture2D = preload("res://assets/artwork/background/background_flourish.png")
@export var fall_background: Texture2D = preload("res://assets/artwork/background/background_fall.png")
@export_group("Table and HUD Artwork")
@export var show_placeholder_guides := true:
	set(value):
		show_placeholder_guides = value
		_set_background_fallback()
		queue_redraw()
@export var table_art: Texture2D
## Shared crop for the base table and context shades. An empty rect uses each whole texture.
@export var table_source_region := Rect2()
## Shade layers in Rise, Flourish, and Fall order, registered to the same canvas as Table Art.
@export var table_shading: Array[Texture2D]
@export var lower_bar_art: Texture2D
@export var hand_tray_art: Texture2D
@export var score_bar_art: Texture2D

var _context := -1
var _blend := Vector3(1.0, 0.0, 0.0)
var _transition: Tween
var _show_score_bar := false
var _background_layer: ColorRect
var _board_layer: TextureRect
var _shade_layer: ColorRect
@onready var _clock: ContextClock = $ContextClock


func _ready() -> void:
	_background_layer = _add_blend_layer("ContextBackground", 1.0)
	_configure_blend_layer(_background_layer, [rise_background, flourish_background, fall_background], true)
	_set_background_fallback()
	_board_layer = TextureRect.new()
	_board_layer.name = "BoardArt"
	_board_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_board_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_layer.show_behind_parent = true
	if table_art != null and table_source_region.has_area():
		var cropped_art := AtlasTexture.new()
		cropped_art.atlas = table_art
		cropped_art.region = table_source_region
		cropped_art.filter_clip = true
		_board_layer.texture = cropped_art
	else:
		_board_layer.texture = table_art
	add_child(_board_layer)
	_shade_layer = _add_blend_layer("ContextShade", TABLE_SHADE_OPACITY)
	_shade_layer.visible = table_art != null
	_configure_blend_layer(_shade_layer, table_shading, false)
	resized.connect(_layout_layers)
	_layout_layers()


func _add_blend_layer(layer_name: String, opacity: float) -> ColorRect:
	var layer := ColorRect.new()
	layer.name = layer_name
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.show_behind_parent = true
	var blend_material := ShaderMaterial.new()
	blend_material.shader = ContextBlend
	blend_material.set_shader_parameter("opacity", opacity)
	blend_material.set_shader_parameter("weights", _blend)
	layer.material = blend_material
	add_child(layer)
	return layer


func _configure_blend_layer(layer: ColorRect, textures: Array, is_background: bool) -> void:
	var blend_material := layer.material as ShaderMaterial
	for i in CONTEXT_KEYS.size():
		var texture: Texture2D = textures[i] if i < textures.size() else null
		var context_key := CONTEXT_KEYS[i]
		blend_material.set_shader_parameter("has_" + context_key, texture != null)
		if texture == null:
			continue
		blend_material.set_shader_parameter(context_key + "_art", texture)
		var region := _texture_region(texture, is_background)
		blend_material.set_shader_parameter(context_key + "_region",
			Vector4(region.position.x, region.position.y, region.size.x, region.size.y))


func _texture_region(texture: Texture2D, is_background: bool) -> Rect2:
	var texture_size := texture.get_size()
	if not is_background:
		return Rect2(table_source_region.position / texture_size, table_source_region.size / texture_size) \
			if table_source_region.has_area() else Rect2(Vector2.ZERO, Vector2.ONE)
	var cover_scale := maxf(BASE.x / texture_size.x, BASE.y / texture_size.y)
	var visible_size := BASE / (texture_size * cover_scale)
	return Rect2((Vector2.ONE - visible_size) / 2.0, visible_size)


func _set_background_fallback() -> void:
	if _background_layer == null:
		return
	var blend_material := _background_layer.material as ShaderMaterial
	for i in CONTEXT_KEYS.size():
		blend_material.set_shader_parameter(CONTEXT_KEYS[i] + "_fallback",
			BACKGROUND[i] if show_placeholder_guides else Color.TRANSPARENT)


func _layout_layers() -> void:
	_background_layer.size = size
	for layer in [_board_layer, _shade_layer]:
		layer.position = TABLE_RECT.position * size / BASE
		layer.size = TABLE_RECT.size * size / BASE
	var clock_bounds := clock_rect()
	_clock.position = clock_bounds.position
	_clock.size = clock_bounds.size
	queue_redraw()


func clock_rect() -> Rect2:
	var view_scale := size / BASE
	var diameter := CLOCK_RECT.size.x * minf(view_scale.x, view_scale.y)
	return Rect2(CLOCK_RECT.get_center() * view_scale - Vector2.ONE * diameter / 2.0,
		Vector2.ONE * diameter)


func render(context: int, direction: int, active: Array, show_score_bar: bool = false) -> void:
	context = clampi(context, 0, 2)
	if _context != context:
		if _transition != null:
			_transition.kill()
		if _context < 0 or not is_inside_tree():
			_set_backdrop_weights(1.0, Vector3.ZERO, context)
		else:
			_transition = create_tween()
			_transition.tween_method(
				_set_backdrop_weights.bind(_blend, context), 0.0, 1.0, CONTEXT_TRANSITION_SECONDS
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_context = context
	_clock.render(context, direction, active)
	_show_score_bar = show_score_bar
	queue_redraw()


func _set_backdrop_weights(progress: float, previous: Vector3, context: int) -> void:
	var target := Vector3.ZERO
	target[context] = 1.0
	_blend = previous.lerp(target, progress)
	if _background_layer != null:
		(_background_layer.material as ShaderMaterial).set_shader_parameter("weights", _blend)
		(_shade_layer.material as ShaderMaterial).set_shader_parameter("weights", _blend)


func _draw() -> void:
	var scale_to_view := size / BASE
	draw_set_transform(Vector2.ZERO, 0.0, scale_to_view)
	if table_art == null and show_placeholder_guides:
		var a := TABLE_RECT.position + Vector2(398, 0)
		var b := TABLE_RECT.position + Vector2(1185, 0)
		var c := TABLE_RECT.end - Vector2(0, 12)
		var d := Vector2(TABLE_RECT.position.x, c.y)
		draw_colored_polygon(PackedVector2Array([a, b, c, d]), Color("33404a"))
		draw_colored_polygon(PackedVector2Array([d, c, c + Vector2(0, 12), d + Vector2(0, 12)]), Color("1a2029"))
		_draw_edge(FarEdge, a, b, scale_to_view)
		_draw_edge(Edge, a, d, scale_to_view)
		_draw_edge(Edge, b, c, scale_to_view)
		draw_set_transform(Vector2.ZERO, 0.0, scale_to_view)
	_draw_surface(lower_bar_art, Rect2(0, HOTBAR_TOP, 1920, 370), Color("202a35"))
	_draw_surface(hand_tray_art, HAND_TRAY_RECT, Color("151d26"))
	if _show_score_bar:
		_draw_surface(score_bar_art, Rect2(HAND_TRAY_RECT.position.x, SCORE_BAR_TOP,
			HAND_TRAY_RECT.size.x, HOTBAR_TOP - SCORE_BAR_TOP), Color("202a35"))


func _draw_surface(texture: Texture2D, rect: Rect2, guide_color: Color) -> void:
	if texture != null:
		draw_texture_rect(texture, rect, false)
	elif show_placeholder_guides:
		draw_rect(rect, guide_color)


func _draw_edge(texture: Texture2D, start: Vector2, end: Vector2, view_scale: Vector2) -> void:
	var delta := (end - start) * view_scale
	draw_set_transform(start * view_scale, delta.angle())
	draw_texture_rect(texture, Rect2(0, -1, delta.length(), 2), false, Color("d9e2eb"))
