extends Control

signal landed(destination: Control)
signal sound_requested(cue: StringName)

const CARD_SCENE := preload("res://src/view/match/card_widget.tscn")
const ABILITY_SCENE := preload("res://src/view/match/ability_inventory_card.tscn")
const HALF_ART_FRACTION := 1508.0 / 2610.0
const HAND_MERGE_SIZE := Vector2(106, 159)
const HALF_LIFT_SIZE := Vector2(74, 65)
const ABILITY_LIFT_SIZE := Vector2(132, 66)
const CARD_GLOW := Color("ffe3a5")
const ABILITY_GLOW := Color("dbbdff")
const HAND_TRAVEL_SECONDS := 1.12
const ABILITY_TRAVEL_SECONDS := 0.80
const GLOW_SECONDS := 0.40
const MERGE_POINT := 0.48

@export_group("Draw Effects")
## Transparent overlay that replaces the default half-card merge pulse.
@export var hand_merge_art: Texture2D
## Transparent overlays that replace the default landing rim for each card type.
@export var hand_landing_art: Texture2D
@export var ability_landing_art: Texture2D

var playback_speed := 1.0


class Pulse extends Control:
	var texture: Texture2D
	var tint: Color
	var bounds := Rect2()
	var opacity := 0.0
	var rim := StyleBoxFlat.new()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		rim.draw_center = false
		rim.set_corner_radius_all(9)
		rim.set_border_width_all(2)

	func show_pulse(rect: Rect2, strength: float) -> void:
		bounds = rect
		opacity = strength
		queue_redraw()

	func _draw() -> void:
		if opacity <= 0.0 or not bounds.has_area():
			return
		if texture != null:
			draw_texture_rect(texture, bounds.grow(16.0), false, Color(1.0, 1.0, 1.0, opacity))
			return
		for spread in [12.0, 8.0, 4.0]:
			rim.border_color = Color(tint, opacity * (0.54 - spread * 0.036))
			draw_style_box(rim, bounds.grow(spread))
		rim.border_color = Color(tint, opacity * 0.9)
		draw_style_box(rim, bounds.grow(1.0))


class Flight extends Control:
	signal landed

	var destination: Variant
	var target_rect := Rect2()
	var sources: Array[Vector2] = []
	var halves: Array[TextureRect] = []
	var face: Control
	var pulse: Pulse
	var tint: Color
	var landing_art: Texture2D
	var timeline: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 8


## Source points use global canvas coordinates. A callable can resolve a newly rendered slot.
func play_hand_draw(card: Dictionary, sources: Array[Vector2], destination: Variant, delay := 0.0) -> Control:
	if sources.size() != 2:
		return null
	var flight := _make_flight(destination, CARD_GLOW, hand_landing_art)
	flight.sources.assign(sources)
	var face := CARD_SCENE.instantiate() as CardWidget
	flight.face = face
	flight.add_child(face)
	face.custom_minimum_size = HAND_MERGE_SIZE
	face.size = HAND_MERGE_SIZE
	face.render(card, -1, false, {"interaction_disabled": true, "display_only": true, "select_in_place": true})
	_ignore_input(face)
	for i in 2:
		var art: TextureRect = face.get_node("Artwork/TopHalf" if i == 0 else "Artwork/BottomHalf")
		var half := TextureRect.new()
		half.name = "Half%d" % i
		half.mouse_filter = Control.MOUSE_FILTER_IGNORE
		half.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		half.flip_h = art.flip_h
		half.flip_v = art.flip_v
		half.texture = _crop_half(art.texture as AtlasTexture)
		flight.add_child(half)
		flight.halves.append(half)
	_make_pulse(flight, hand_merge_art)
	_animate_hand(0.0, flight)
	_play(flight, _animate_hand.bind(flight), HAND_TRAVEL_SECONDS, delay)
	return flight


func play_ability_draw(card: Dictionary, source: Vector2, destination: Variant, delay := 0.0) -> Control:
	var flight := _make_flight(destination, ABILITY_GLOW, ability_landing_art)
	flight.sources.append(source)
	var face = ABILITY_SCENE.instantiate()
	flight.face = face
	flight.add_child(face)
	face.size = face.get_combined_minimum_size()
	face.render(card, str(card.get("ability_id", "")), false)
	face.modulate = Color.WHITE
	_ignore_input(face)
	_make_pulse(flight)
	_animate_ability(0.0, flight)
	_play(flight, _animate_ability.bind(flight), ABILITY_TRAVEL_SECONDS, delay)
	return flight


func cancel() -> void:
	for flight: Flight in get_children():
		flight.timeline.kill()
		flight.hide()
		flight.queue_free()


func set_playback_speed(speed: float) -> void:
	playback_speed = speed
	for flight: Flight in get_children():
		if flight.timeline.is_valid():
			flight.timeline.set_speed_scale(playback_speed)


func _make_flight(destination: Variant, tint: Color, landing_art: Texture2D) -> Flight:
	var flight := Flight.new()
	flight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight.destination = destination
	flight.tint = tint
	flight.landing_art = landing_art
	add_child(flight)
	return flight


func _make_pulse(flight: Flight, art: Texture2D = null) -> void:
	var pulse := Pulse.new()
	pulse.texture = art
	pulse.tint = flight.tint
	flight.add_child(pulse)
	flight.pulse = pulse


func _play(flight: Flight, step: Callable, duration: float, delay: float) -> void:
	flight.timeline = flight.create_tween()
	flight.timeline.set_speed_scale(playback_speed)
	if delay > 0.0:
		flight.hide()
		flight.timeline.tween_interval(delay)
		flight.timeline.tween_callback(flight.show)
	flight.timeline.tween_callback(func(): sound_requested.emit(&"draw"))
	flight.timeline.tween_method(step, 0.0, 1.0, duration)
	flight.timeline.tween_callback(_land.bind(flight))
	flight.timeline.tween_method(_animate_landing.bind(flight), 0.0, 1.0, GLOW_SECONDS)
	flight.timeline.tween_callback(flight.queue_free)


func _animate_hand(progress: float, flight: Flight) -> void:
	var transform := get_global_transform_with_canvas().affine_inverse()
	var first_source := transform * flight.sources[0]
	var second_source := transform * flight.sources[1]
	var source_center := (first_source + second_source) * 0.5
	_update_target_rect(flight)
	var target := flight.target_rect
	if not target.has_area():
		target = _centered_rect(source_center + Vector2(0, 140), HAND_MERGE_SIZE)
	var merge_center := source_center.lerp(target.get_center(), 0.4) + Vector2(0, -42)
	var merge_progress := smoothstep(0.0, MERGE_POINT, progress)
	var travel := smoothstep(MERGE_POINT, 1.0, progress)
	var face_rect := _centered_rect(
		merge_center.lerp(target.get_center(), travel) + Vector2(0, -24) * sin(travel * PI),
		HAND_MERGE_SIZE.lerp(target.size, travel)
	)
	_place_face(flight.face, face_rect, -0.07 * sin(travel * TAU))
	var face_alpha := smoothstep(MERGE_POINT * 0.8, MERGE_POINT, progress)
	flight.face.modulate.a = face_alpha
	var inner := _centered_rect(merge_center, HAND_MERGE_SIZE).grow(-8.0)
	for i in 2:
		var half := flight.halves[i]
		var side := -1.0 if i == 0 else 1.0
		var half_size := Vector2(inner.size.x, inner.size.y * HALF_ART_FRACTION)
		var half_center := inner.get_center() + Vector2(0, side * (inner.size.y - half_size.y) * 0.5)
		var source := first_source if i == 0 else second_source
		var lift := Vector2(side * 19.0, -54.0) * sin(merge_progress * PI)
		var center := source.lerp(half_center, merge_progress) + lift
		half.visible = face_alpha < 1.0
		half.size = HALF_LIFT_SIZE.lerp(half_size, merge_progress)
		half.pivot_offset = half.size * 0.5
		half.position = center - half.pivot_offset
		half.rotation = side * 0.23 * sin(merge_progress * PI)
		half.modulate.a = 1.0 - face_alpha
	var flash := smoothstep(0.32, MERGE_POINT, progress) * (1.0 - smoothstep(MERGE_POINT, 0.68, progress))
	flight.pulse.show_pulse(face_rect, flash * 0.82)


func _animate_ability(progress: float, flight: Flight) -> void:
	var source := get_global_transform_with_canvas().affine_inverse() * flight.sources[0]
	var destination := _update_target_rect(flight)
	var target := flight.target_rect
	if not target.has_area():
		target = _centered_rect(source, ABILITY_LIFT_SIZE)
	var travel := smoothstep(0.0, 1.0, progress)
	var sway := sin(travel * PI)
	var ends_on_toggle := destination is Button
	var end_size := target.size
	if ends_on_toggle:
		end_size = Vector2(minf(target.size.x * 0.46, 84.0), minf(target.size.y * 0.8, 42.0))
	var face_size := ABILITY_LIFT_SIZE.lerp(end_size, travel) * (1.0 + 0.24 * sway)
	var center := source.lerp(target.get_center(), travel) + Vector2(0.0, -63.0) * sway
	_place_face(flight.face, _centered_rect(center, face_size), 0.15 * sway)
	flight.face.modulate.a = 1.0 - smoothstep(0.78, 1.0, progress) if ends_on_toggle else 1.0


func _land(flight: Flight) -> void:
	var destination := _update_target_rect(flight)
	if destination == null:
		flight.hide()
		flight.queue_free()
		return
	flight.face.hide()
	flight.pulse.texture = flight.landing_art
	flight.pulse.show_pulse(flight.target_rect, 1.0)
	sound_requested.emit(&"deal")
	flight.landed.emit()
	landed.emit(destination)


func _animate_landing(progress: float, flight: Flight) -> void:
	var destination := _update_target_rect(flight)
	var opacity := 1.0 - progress if destination != null else 0.0
	flight.pulse.show_pulse(flight.target_rect.grow(progress * 5.0), opacity)


func _update_target_rect(flight: Flight) -> Control:
	var candidate: Variant = flight.destination
	if candidate is Callable:
		candidate = candidate.call() if candidate.is_valid() else null
	if not is_instance_valid(candidate) or not candidate is Control:
		return null
	var target: Control = candidate
	if target.is_queued_for_deletion() or not target.is_visible_in_tree() or target.size.x <= 0.0 or target.size.y <= 0.0:
		return null
	var to_local := get_global_transform_with_canvas().affine_inverse() * target.get_global_transform_with_canvas()
	flight.target_rect = to_local * Rect2(Vector2.ZERO, target.size)
	return target


func _place_face(face: Control, rect: Rect2, angle: float) -> void:
	face.pivot_offset = face.size * 0.5
	face.position = rect.get_center() - face.pivot_offset
	face.scale = rect.size / face.size
	face.rotation = angle


func _centered_rect(center: Vector2, dimensions: Vector2) -> Rect2:
	return Rect2(center - dimensions * 0.5, dimensions)


func _crop_half(art: AtlasTexture) -> AtlasTexture:
	if art == null:
		return null
	var half := art.duplicate() as AtlasTexture
	half.region.size.y *= HALF_ART_FRACTION
	return half


func _ignore_input(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		if child is Control:
			_ignore_input(child)
