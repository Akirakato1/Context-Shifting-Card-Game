class_name PresentationState
extends RefCounted

signal changed(state: Dictionary, sequence: int)
signal sequence_gap(expected: int, received: int)

var _state: Dictionary = {}
var _sequence := -1
var _recent_events: Array[Dictionary] = []


func apply_snapshot(snapshot: Dictionary, sequence: int = 0) -> bool:
	if sequence < _sequence:
		return false
	_state = snapshot.duplicate(true)
	_sequence = sequence
	_recent_events.clear()
	changed.emit(_state.duplicate(true), _sequence)
	return true


func apply_event(event: Dictionary, sequence: int) -> bool:
	if sequence < _sequence:
		return false
	if _sequence >= 0 and sequence > _sequence + 1:
		sequence_gap.emit(_sequence + 1, sequence)
		return false
	var patch: Variant = event.get("state_patch", {})
	if patch is Dictionary:
		_deep_merge(_state, patch)
	_recent_events.append(event.duplicate(true))
	if _recent_events.size() > 32:
		_recent_events.pop_front()
	_sequence = sequence
	_state["last_event"] = event.duplicate(true)
	changed.emit(_state.duplicate(true), _sequence)
	return true


func public_state() -> Dictionary:
	var result := _state.duplicate(true)
	for key in result.keys():
		if str(key).begins_with("private_"):
			result.erase(key)
	result.erase("required_ability_discards")
	return result


func private_state() -> Dictionary:
	return _state.duplicate(true)


func recent_events() -> Array[Dictionary]:
	return _recent_events.duplicate(true)


func sequence() -> int:
	return _sequence


func clear() -> void:
	_state.clear()
	_recent_events.clear()
	_sequence = -1
	changed.emit({}, _sequence)


func _deep_merge(target: Dictionary, patch: Dictionary) -> void:
	for key in patch:
		var incoming: Variant = patch[key]
		if target.get(key) is Dictionary and incoming is Dictionary:
			_deep_merge(target[key], incoming)
		else:
			target[key] = incoming.duplicate(true) if incoming is Array or incoming is Dictionary else incoming
