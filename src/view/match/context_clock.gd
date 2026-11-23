class_name ContextClock
extends Control

const GameTypes := preload("res://src/core/common/game_types.gd")
const NameBacklight := preload("res://src/view/match/context_clock_backlight.gdshader")
const HUB := Vector2(0.493, 0.512)
const NAME_CENTERS := [Vector2(0.496, 0.228), Vector2(0.758, 0.643), Vector2(0.287, 0.648)]
const POINTER_PIVOT := Vector2(121, 443)
const POINTER_SCALE := 0.53 / 1000.0

@export var dial_art: Texture2D = preload("res://assets/artwork/board/clock_background.png")
@export var names_art: Texture2D = preload("res://assets/artwork/board/clock_text.png")
@export var pointer_art: Texture2D = preload("res://assets/artwork/board/clock_arow.png")
@export var forward_art: Texture2D = preload("res://assets/artwork/board/clock_directionarrow_1.png")
@export var reverse_art: Texture2D = preload("res://assets/artwork/board/clock_directionarrow_2.png")

var _context := -1
var _direction := 1
var _light_target := Vector3.ZERO
var _light := Vector3.ZERO
var _cycle_mix := 0.0
var _pointer_tween: Tween
var _direction_tween: Tween
var _light_tween: Tween
var _pointer: TextureRect
var _forward: TextureRect
var _reverse: TextureRect
var _names_material := ShaderMaterial.new()


func _ready() -> void:
	_add_layer("Dial", dial_art)
	_forward = _add_layer("ForwardCycle", forward_art)
	_reverse = _add_layer("ReverseCycle", reverse_art)
	_pointer = _add_layer("Pointer", pointer_art, false)
	var names := _add_layer("Names", names_art)
	_names_material.shader = NameBacklight
	names.material = _names_material
	_set_cycle_mix(0.0)
	resized.connect(_layout_pointer)
	_layout_pointer()
	tooltip_text = "Context clock"


func _add_layer(layer_name: String, texture: Texture2D, fill := true) -> TextureRect:
	var layer := TextureRect.new()
	layer.name = layer_name
	layer.texture = texture
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	if fill:
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return layer


func _layout_pointer() -> void:
	if pointer_art == null:
		return
	var art_scale := size.x * POINTER_SCALE
	_pointer.size = pointer_art.get_size() * art_scale
	_pointer.pivot_offset = POINTER_PIVOT * art_scale
	_pointer.position = HUB * size - _pointer.pivot_offset


func render(context: int, direction: int, active_contexts: Array) -> void:
	var first_render := _context < 0
	if context != _context:
		_move_pointer(context, first_render)
		_context = context
	direction = -1 if direction < 0 else 1
	if first_render or direction != _direction:
		_change_direction(direction, first_render)
		_direction = direction
	var lights := Vector3.ZERO
	for index in NAME_CENTERS.size():
		if index != context and index in active_contexts:
			lights[index] = 1.0
	if lights != _light_target:
		_light_target = lights
		if _light_tween != null:
			_light_tween.kill()
		if first_render:
			_set_backlight(lights)
		else:
			_light_tween = create_tween()
			_light_tween.tween_method(_set_backlight, _light, lights, 0.32).set_trans(Tween.TRANS_SINE)


func _move_pointer(context: int, immediate: bool) -> void:
	var target := Vector2.UP.angle_to(NAME_CENTERS[context] - HUB)
	if _pointer_tween != null:
		_pointer_tween.kill()
	if immediate:
		_pointer.rotation = target
		return
	var destination := _pointer.rotation + wrapf(target - _pointer.rotation, -PI, PI)
	_pointer_tween = create_tween()
	_pointer_tween.tween_property(_pointer, "rotation", destination, 0.52) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _change_direction(direction: int, immediate: bool) -> void:
	var target := 1.0 if direction < 0 else 0.0
	if _direction_tween != null:
		_direction_tween.kill()
	if immediate:
		_set_cycle_mix(target)
	else:
		_direction_tween = create_tween()
		_direction_tween.tween_method(_set_cycle_mix, _cycle_mix, target, 0.24)


func _set_cycle_mix(amount: float) -> void:
	_cycle_mix = amount
	_forward.self_modulate.a = 1.0 - amount
	_reverse.self_modulate.a = amount


func _set_backlight(amount: Vector3) -> void:
	_light = amount
	_names_material.set_shader_parameter("backlight", amount)


func _get_tooltip(at_position: Vector2) -> String:
	if _context < 0 or size.x <= 0.0:
		return ""
	var point := at_position / size
	for index in NAME_CENTERS.size():
		if point.distance_to(NAME_CENTERS[index]) < 0.17:
			var context := GameTypes.context_name(index)
			if index == _context:
				return "%s · Current context" % context
			if _light_target[index] > 0.0:
				return "%s · Also active" % context
			return context
	var next := GameTypes.context_name(posmod(_context + _direction, NAME_CENTERS.size()))
	return "%s · Next: %s" % ["Clockwise" if _direction > 0 else "Counterclockwise", next]
