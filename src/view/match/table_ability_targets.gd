extends Control

signal target_requested(player_id: String)

const SCENERY := preload("res://src/view/match/table_scenery.gd")
const TARGET_AURA := preload("res://src/view/match/primed_card_aura.tres")
const BOARD_SOURCE := Rect2(0, 265, 2560, 955)
const SEAT_ORDER: Array[StringName] = [&"top", &"right", &"bottom", &"left"]

var _table_rect := Rect2()
var _targets: Dictionary[StringName, String] = {}
var _regions: Dictionary[StringName, PackedVector2Array] = {}
var _selected: Array = []
var _interactive := false
var _hovered_seat: StringName
var _keyboard_seat: StringName


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	resized.connect(_rebuild_regions)
	mouse_exited.connect(_set_hovered.bind(&""))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	_rebuild_regions()


func set_table_rect(rect: Rect2) -> void:
	_table_rect = rect
	_rebuild_regions()


func set_targets(players_by_seat: Dictionary, eligible: Array, selected: Array, interactive: bool) -> void:
	_targets.clear()
	for seat in SEAT_ORDER:
		var player_id := str(players_by_seat.get(seat, ""))
		if not player_id.is_empty() and player_id in eligible:
			_targets[seat] = player_id
	_selected = selected.duplicate()
	_interactive = interactive and not _targets.is_empty()
	mouse_filter = Control.MOUSE_FILTER_STOP if _interactive else Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_ALL if _interactive else Control.FOCUS_NONE
	if not _interactive:
		release_focus()
		_hovered_seat = &""
	if not _targets.has(_keyboard_seat):
		_keyboard_seat = _targets.keys().front() if not _targets.is_empty() else &""
	queue_redraw()


func target_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for seat in _targets:
		var points: PackedVector2Array = _regions.get(seat, PackedVector2Array())
		if points.is_empty():
			continue
		var transform := get_global_transform()
		var bounds := Rect2(transform * points[0], Vector2.ZERO)
		for point in points:
			bounds = bounds.expand(transform * point)
		rects.append(bounds.grow(3.0))
	return rects


func _has_point(point: Vector2) -> bool:
	return _interactive and not _seat_at(point).is_empty()


func _gui_input(event: InputEvent) -> void:
	if not _interactive:
		return
	if event is InputEventMouseMotion:
		_set_hovered(_seat_at(event.position))
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var seat := _seat_at(event.position)
		if not seat.is_empty():
			_keyboard_seat = seat
			accept_event()
			target_requested.emit(_targets[seat])
		return
	if event.is_action_pressed(&"ui_accept") and _targets.has(_keyboard_seat):
		accept_event()
		target_requested.emit(_targets[_keyboard_seat])
		return
	var step := 0
	if event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"ui_down"):
		step = 1
	elif event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_up"):
		step = -1
	if step != 0:
		var seats := _targets.keys()
		_keyboard_seat = seats[posmod(seats.find(_keyboard_seat) + step, seats.size())]
		queue_redraw()
		accept_event()


func _set_hovered(seat: StringName) -> void:
	if _hovered_seat != seat:
		_hovered_seat = seat
		queue_redraw()


func _seat_at(point: Vector2) -> StringName:
	for seat in _targets:
		if _regions.has(seat) and Geometry2D.is_point_in_polygon(point, _regions[seat]):
			return seat
	return &""


func _draw() -> void:
	var gold: Color = TARGET_AURA.border_color
	for seat in _targets:
		if not _regions.has(seat):
			continue
		var points := _regions[seat]
		var emphasized := seat == _hovered_seat or (has_focus() and seat == _keyboard_seat) or _targets[seat] in _selected
		var outline := points.duplicate()
		outline.append(points[0])
		draw_colored_polygon(points, Color(gold, 0.14 if emphasized else 0.055))
		draw_polyline(outline, Color(TARGET_AURA.shadow_color, 0.14 if emphasized else 0.08), 8.0, true)
		draw_polyline(outline, Color(gold, 0.82 if emphasized else 0.43), 2.0, true)


func _rebuild_regions() -> void:
	# The endpoints and curves follow the semicircles printed on board.png.
	var table_rect := _table_rect
	if not table_rect.has_area():
		var view_scale: Vector2 = size / SCENERY.BASE
		table_rect = Rect2(SCENERY.TABLE_RECT.position * view_scale, SCENERY.TABLE_RECT.size * view_scale)
	_regions[&"top"] = _project_curve(PackedVector2Array(
		[Vector2(1065, 320), Vector2(1160, 425), Vector2(1430, 425), Vector2(1525, 322)]
	), table_rect)
	_regions[&"right"] = _project(PackedVector2Array([
		Vector2(2096, 423), Vector2(2043, 433), Vector2(1992, 452), Vector2(1951, 478),
		Vector2(1921, 510), Vector2(1906, 542), Vector2(1902, 571), Vector2(1910, 609),
		Vector2(1936, 656), Vector2(1978, 703), Vector2(2030, 748), Vector2(2098, 789),
		Vector2(2170, 823), Vector2(2254, 846), Vector2(2344, 860),
	]), table_rect)
	_regions[&"bottom"] = _project_curve(PackedVector2Array(
		[Vector2(597, 1133), Vector2(957, 693), Vector2(1638, 687), Vector2(2002, 1133)]
	), table_rect)
	_regions[&"left"] = _project(PackedVector2Array([
		Vector2(496, 435), Vector2(540, 445), Vector2(586, 463), Vector2(624, 490),
		Vector2(647, 520), Vector2(661, 554), Vector2(663, 583), Vector2(655, 624),
		Vector2(629, 675), Vector2(591, 720), Vector2(538, 760), Vector2(470, 803),
		Vector2(397, 836), Vector2(318, 857), Vector2(246, 869),
	]), table_rect)
	queue_redraw()


func _project_curve(points: PackedVector2Array, table_rect: Rect2) -> PackedVector2Array:
	var curve := PackedVector2Array()
	for step in 25:
		var progress := float(step) / 24.0
		curve.append(points[0].bezier_interpolate(points[1], points[2], points[3], progress))
	return _project(curve, table_rect)


func _project(points: PackedVector2Array, table_rect: Rect2) -> PackedVector2Array:
	var result := PackedVector2Array()
	var hotbar_top: float = SCENERY.HOTBAR_TOP * size.y / SCENERY.BASE.y
	for point in points:
		var projected := table_rect.position + (point - BOARD_SOURCE.position) / BOARD_SOURCE.size * table_rect.size
		projected.y = minf(projected.y, hotbar_top - 2.0)
		result.append(projected)
	return result
