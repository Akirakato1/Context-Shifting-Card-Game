class_name MatchTimer
extends Label

signal countdown_tick(seconds_left: int)

const NORMAL_INK := Color("fff9ed")
const NORMAL_GLOW := Color(0.85, 0.91, 1.0, 0.7)
const URGENT_INK := Color("ffd6d1")
const URGENT_GLOW := Color(1.0, 0.24, 0.28, 0.9)

var _period := Vector2i(-1, -1)
var _next_tick := 5
var _urgent := false


func set_period(round_number: int, phase: int) -> void:
	var period := Vector2i(round_number, phase)
	if period != _period:
		_period = period
		_next_tick = 5


func show_remaining(remaining_msec: int, untimed: bool, audible: bool) -> void:
	if remaining_msec < 0:
		text = "UNTIMED" if untimed else "—"
	else:
		text = "%.1fs" % (remaining_msec / 1000.0)
	var urgent := remaining_msec >= 0 and remaining_msec <= 10000
	if urgent != _urgent:
		_urgent = urgent
		add_theme_color_override("font_color", URGENT_INK if urgent else NORMAL_INK)
		add_theme_color_override("font_shadow_color", URGENT_GLOW if urgent else NORMAL_GLOW)
	if audible and remaining_msec > 0:
		var seconds_left := ceili(remaining_msec / 1000.0)
		if seconds_left <= _next_tick:
			_next_tick = seconds_left - 1
			countdown_tick.emit(seconds_left)
