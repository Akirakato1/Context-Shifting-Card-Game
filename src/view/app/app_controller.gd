class_name AppController
extends Control

signal presentation_changed(state: Dictionary, sequence: int)
signal connection_changed(state: Dictionary)
signal screen_requested(screen_id: StringName, payload: Dictionary)

const PresentationState = preload("res://src/view/common/presentation_state.gd")
const PresentationQueue = preload("res://src/view/common/presentation_queue.gd")
const UICommandGateway = preload("res://src/view/common/ui_command_gateway.gd")

var presentation_state: PresentationState
var presentation_queue: PresentationQueue
var command_gateway: UICommandGateway
var _session: Variant
var _connection := {"status": "idle", "reason": ""}


func _init() -> void:
	presentation_state = PresentationState.new()
	presentation_queue = PresentationQueue.new()
	command_gateway = UICommandGateway.new()
	presentation_state.changed.connect(_on_presentation_changed)
	presentation_queue.event_ready.connect(_on_event_ready)


func bind_session(session: Variant) -> void:
	_session = session
	command_gateway.bind_session(session)
	if session == null:
		_set_connection("idle", "")
		return
	_connect_if_present(session, "snapshot_applied", _on_snapshot_applied)
	_connect_if_present(session, "events_applied", _on_events_applied)
	_connect_if_present(session, "command_result_received", _on_command_result)
	_connect_if_present(session, "session_failed", _on_session_failed)
	_connect_if_present(session, "connection_state_changed", _on_connection_state_changed)
	_set_connection("connected", "")


func advance_presentation(delta_msec: int) -> void:
	presentation_queue.tick(delta_msec)


func connection_state() -> Dictionary:
	return _connection.duplicate(true)


func request_screen(screen_id: StringName, payload: Dictionary = {}) -> void:
	screen_requested.emit(screen_id, payload.duplicate(true))


func _process(delta: float) -> void:
	if _session != null and _session.has_method("poll"):
		_session.poll()
	advance_presentation(int(delta * 1000.0))


func _on_snapshot_applied(snapshot: Dictionary, sequence: int) -> void:
	presentation_queue.cancel_before_sequence(sequence + 1)
	presentation_state.apply_snapshot(snapshot, sequence)


func _on_events_applied(events: Array, sequence: int) -> void:
	var queued: Array[Dictionary] = []
	for event in events:
		if event is Dictionary:
			var item: Dictionary = event.duplicate(true)
			item["sequence"] = sequence
			queued.append(item)
	presentation_queue.enqueue(queued)


func _on_event_ready(event: Dictionary) -> void:
	presentation_state.apply_event(event, int(event.get("sequence", presentation_state.sequence())))


func _on_command_result(_request_message_id: String, _result: Dictionary) -> void:
	pass


func _on_session_failed(reason: String) -> void:
	command_gateway.set_input_locked(true)
	presentation_queue.skip_to_latest()
	_set_connection("failed", reason)


func _on_connection_state_changed(value: Variant) -> void:
	if value is Dictionary:
		_connection = value.duplicate(true)
		connection_changed.emit(_connection.duplicate(true))
	else:
		_set_connection(str(value), "")


func _on_presentation_changed(state: Dictionary, sequence: int) -> void:
	presentation_changed.emit(state.duplicate(true), sequence)


func _set_connection(status: String, reason: String) -> void:
	_connection = {"status": status, "reason": reason}
	connection_changed.emit(_connection.duplicate(true))


func _connect_if_present(target: Variant, signal_name: String, callable: Callable) -> void:
	if target.has_signal(signal_name):
		var signal_value: Signal = target.get(signal_name)
		if not signal_value.is_connected(callable):
			signal_value.connect(callable)
