class_name PresentationQueue
extends RefCounted

signal event_ready(event: Dictionary)
signal cue_started(event: Dictionary, token: int)
signal cue_finished(event: Dictionary)
signal drained

var _durations_msec: Dictionary = {}
var _pending: Array[Dictionary] = []
var _active: Dictionary = {}
var _active_token := 0
var _next_token := 1
var _elapsed_msec := 0


func set_duration(kind: StringName, duration_msec: int) -> void:
	_durations_msec[kind] = maxi(duration_msec, 0)


func enqueue(events: Array) -> void:
	for raw_event in events:
		if raw_event is Dictionary:
			_pending.append(raw_event.duplicate(true))


func tick(delta_msec: int) -> int:
	if _active.is_empty():
		_start_next()
	var returned_token := _active_token
	if _active.is_empty():
		return returned_token
	_elapsed_msec += maxi(delta_msec, 0)
	while not _active.is_empty() and _elapsed_msec >= _duration_for(_active):
		var duration := _duration_for(_active)
		_elapsed_msec -= duration
		var token := _active_token
		complete_active(token)
		if duration > 0:
			break
	return returned_token


func complete_active(token: int) -> bool:
	if _active.is_empty() or token != _active_token:
		return false
	var completed := _active.duplicate(true)
	_active.clear()
	_active_token = 0
	_elapsed_msec = 0
	cue_finished.emit(completed)
	_start_next()
	return true


func skip_to_latest() -> void:
	_active.clear()
	_active_token = 0
	_elapsed_msec = 0
	_next_token += 1
	for event in _pending:
		event_ready.emit(event.duplicate(true))
	_pending.clear()
	drained.emit()


func cancel_before_sequence(minimum_sequence: int) -> void:
	if not _active.is_empty() and int(_active.get("sequence", -1)) < minimum_sequence:
		_active.clear()
		_active_token = 0
		_elapsed_msec = 0
		_next_token += 1
	var retained: Array[Dictionary] = []
	for event in _pending:
		if int(event.get("sequence", -1)) >= minimum_sequence:
			retained.append(event)
	_pending = retained
	if _active.is_empty() and _pending.is_empty():
		drained.emit()


func is_busy() -> bool:
	return not _active.is_empty() or not _pending.is_empty()


func clear() -> void:
	_active.clear()
	_pending.clear()
	_active_token = 0
	_elapsed_msec = 0
	_next_token += 1
	drained.emit()


func _start_next() -> void:
	if not _active.is_empty() or _pending.is_empty():
		if _active.is_empty() and _pending.is_empty():
			drained.emit()
		return
	_active = _pending.pop_front()
	_active_token = _next_token
	_next_token += 1
	_elapsed_msec = 0
	event_ready.emit(_active.duplicate(true))
	cue_started.emit(_active.duplicate(true), _active_token)


func _duration_for(event: Dictionary) -> int:
	return int(_durations_msec.get(StringName(event.get("kind", "")), 0))
