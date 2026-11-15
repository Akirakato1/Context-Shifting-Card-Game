class_name ClientNetworkSession
extends RefCounted

signal command_result_received(request_message_id: String, result: Dictionary)
signal events_applied(events: Array, sequence: int)
signal snapshot_applied(snapshot: Dictionary, sequence: int)
signal snapshot_resync_requested(expected_sequence: int, received_sequence: int)
signal session_failed(reason: String)

const GameProtocol = preload("res://src/network/game_protocol.gd")
const PeerTransport = preload("res://src/network/peer_transport.gd")

const MAX_BUFFERED_BATCHES := 8
const MAX_SEQUENCE_GAP := 8

var latest_snapshot: Dictionary = {}
var expected_sequence := 1

var _transport: PeerTransport
var _host_peer_id: String
var _match_id: String
var _player_id: StringName
var _buffered_batches := {}
var _resync_pending := false


func _init(
	transport: PeerTransport,
	host_peer_id: String,
	match_id: String,
	player_id: StringName
) -> void:
	_transport = transport
	_host_peer_id = host_peer_id
	_match_id = match_id
	_player_id = player_id
	_transport.message_received.connect(_on_message_received)
	_transport.peer_disconnected.connect(_on_peer_disconnected)


func submit_command(message_id: String, command: Dictionary) -> Error:
	if message_id.is_empty():
		return ERR_INVALID_PARAMETER
	var payload := command.duplicate(true)
	payload["player_id"] = str(_player_id)
	var envelope := {
		"v": GameProtocol.VERSION,
		"kind": "command",
		"message_id": message_id,
		"match_id": _match_id,
		"sender_id": str(_player_id),
		"payload": payload,
	}
	var bytes := GameProtocol.encode(envelope)
	if bytes.is_empty():
		return ERR_INVALID_DATA
	var result := _transport.send(_host_peer_id, bytes)
	if result != OK:
		session_failed.emit("transport_send_failed")
	return result


func poll() -> void:
	_transport.poll()


func _on_message_received(peer_id: String, bytes: PackedByteArray) -> void:
	if peer_id != _host_peer_id:
		return
	var decoded = GameProtocol.decode(bytes)
	if not decoded.ok:
		session_failed.emit("invalid_protocol_message")
		return
	var envelope: Dictionary = decoded.envelope
	if envelope["match_id"] != _match_id or envelope["sender_id"] != "host":
		session_failed.emit("protocol_violation")
		return
	match envelope["kind"]:
		"command_result":
			_handle_command_result(envelope["payload"])
		"event_batch":
			_handle_event_batch(envelope["payload"])
		"snapshot":
			_handle_snapshot(envelope["payload"])
		_:
			session_failed.emit("protocol_violation")


func _handle_command_result(payload: Dictionary) -> void:
	if (
		typeof(payload.get("request_message_id", null)) != TYPE_STRING
		or typeof(payload.get("accepted", null)) != TYPE_BOOL
		or typeof(payload.get("error_code", null)) != TYPE_STRING
	):
		session_failed.emit("malformed_command_result")
		return
	command_result_received.emit(payload["request_message_id"], payload.duplicate(true))


func _handle_event_batch(payload: Dictionary) -> void:
	if (
		typeof(payload.get("sequence", null)) != TYPE_INT
		or not payload.get("events", null) is Array
	):
		session_failed.emit("malformed_event_batch")
		return
	var sequence: int = payload["sequence"]
	if sequence < expected_sequence:
		return
	if sequence == expected_sequence:
		_apply_batch(sequence, payload["events"])
		_drain_buffered()
		return
	if (
		sequence - expected_sequence > MAX_SEQUENCE_GAP
		or _buffered_batches.size() >= MAX_BUFFERED_BATCHES
	):
		_buffered_batches.clear()
		if not _resync_pending:
			_resync_pending = true
			snapshot_resync_requested.emit(expected_sequence, sequence)
		return
	_buffered_batches[sequence] = payload["events"].duplicate(true)


func _handle_snapshot(payload: Dictionary) -> void:
	if (
		typeof(payload.get("sequence", null)) != TYPE_INT
		or not payload.get("state", null) is Dictionary
	):
		session_failed.emit("malformed_snapshot")
		return
	latest_snapshot = payload["state"].duplicate(true)
	expected_sequence = int(payload["sequence"]) + 1
	_buffered_batches.clear()
	_resync_pending = false
	snapshot_applied.emit(latest_snapshot.duplicate(true), int(payload["sequence"]))


func _apply_batch(sequence: int, events: Array) -> void:
	events_applied.emit(events.duplicate(true), sequence)
	expected_sequence = sequence + 1


func _drain_buffered() -> void:
	while _buffered_batches.has(expected_sequence):
		var sequence := expected_sequence
		var events: Array = _buffered_batches[sequence]
		_buffered_batches.erase(sequence)
		_apply_batch(sequence, events)


func _on_peer_disconnected(peer_id: String, reason: String) -> void:
	if peer_id == _host_peer_id:
		session_failed.emit(reason)
