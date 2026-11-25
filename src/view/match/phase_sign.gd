class_name PhaseSign
extends Control

signal landed
signal pulling
signal dropping

const RETRACTED_Y := -175.0
const PULL_SECONDS := 0.14
const DROP_SECONDS := 0.24
const SHAKE_BEAT := 0.052

@export var resting_y := 0.0

var _pending_title := ""
var _round_number := -1
var _motion: Tween

@onready var _phase: Label = $Phase


func _ready() -> void:
	position.y = RETRACTED_Y


func present_phase(title: String, round_number: int) -> void:
	if title == _pending_title and round_number == _round_number:
		return
	var first_phase := _pending_title.is_empty()
	_pending_title = title
	_round_number = round_number
	if _motion != null:
		_motion.kill()
	rotation_degrees = 0.0
	_motion = create_tween()
	if first_phase:
		_phase.text = title
	else:
		_motion.tween_callback(func(): pulling.emit())
		_motion.tween_property(self, "position:y", RETRACTED_Y, PULL_SECONDS) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_motion.tween_callback(func(): _phase.text = title)
	_motion.tween_callback(func(): dropping.emit())
	_motion.tween_property(self, "position:y", resting_y, DROP_SECONDS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_motion.tween_callback(func(): landed.emit())
	_motion.tween_property(self, "position:y", resting_y - 3.0, SHAKE_BEAT)
	_motion.parallel().tween_property(self, "rotation_degrees", -2.7, SHAKE_BEAT)
	_motion.tween_property(self, "position:y", resting_y + 1.3, SHAKE_BEAT)
	_motion.parallel().tween_property(self, "rotation_degrees", 1.5, SHAKE_BEAT)
	_motion.tween_property(self, "position:y", resting_y, SHAKE_BEAT)
	_motion.parallel().tween_property(self, "rotation_degrees", 0.0, SHAKE_BEAT)
