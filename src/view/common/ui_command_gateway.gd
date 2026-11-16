class_name UICommandGateway
extends RefCounted

signal command_sent(message_id: String, command: Dictionary)
signal command_completed(kind: StringName, message_id: String, result: Dictionary)
signal command_blocked(kind: StringName, reason: StringName)

var _session: Variant
var _input_locked := false
var _next_id := 1
var _in_flight_by_kind: Dictionary = {}
var _kind_by_request: Dictionary = {}


func bind_session(session: Variant) -> void:
	if (
		_session != null and _session.has_signal("command_result_received")
		and _session.command_result_received.is_connected(handle_command_result)
	):
		_session.command_result_received.disconnect(handle_command_result)
	_session = session
	clear_in_flight()
	if (
		_session != null and _session.has_signal("command_result_received")
		and not _session.command_result_received.is_connected(handle_command_result)
	):
		_session.command_result_received.connect(handle_command_result)


func send(kind: StringName, payload: Dictionary = {}) -> String:
	if _input_locked:
		command_blocked.emit(kind, &"input_locked")
		return ""
	if _session == null or not _session.has_method("submit_command"):
		command_blocked.emit(kind, &"session_unavailable")
		return ""
	if _in_flight_by_kind.has(kind):
		command_blocked.emit(kind, &"duplicate_in_flight")
		return ""
	var message_id := "ui-message-%d" % _next_id
	var command_id := "ui-command-%d" % _next_id
	_next_id += 1
	var command := {
		"command_id": command_id,
		"kind": str(kind),
		"payload": payload.duplicate(true),
	}
	_in_flight_by_kind[kind] = message_id
	_kind_by_request[message_id] = kind
	var result: Error = _session.submit_command(message_id, command)
	if result != OK:
		_in_flight_by_kind.erase(kind)
		_kind_by_request.erase(message_id)
		command_blocked.emit(kind, &"send_failed")
		return ""
	command_sent.emit(message_id, command.duplicate(true))
	return message_id


func handle_command_result(request_message_id: String, result: Dictionary) -> void:
	if not _kind_by_request.has(request_message_id):
		return
	var kind: StringName = _kind_by_request[request_message_id]
	_kind_by_request.erase(request_message_id)
	_in_flight_by_kind.erase(kind)
	command_completed.emit(kind, request_message_id, result.duplicate(true))


func set_input_locked(locked: bool) -> void:
	_input_locked = locked


func input_locked() -> bool:
	return _input_locked


func clear_in_flight() -> void:
	_in_flight_by_kind.clear()
	_kind_by_request.clear()
