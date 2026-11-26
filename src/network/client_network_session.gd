class_name ClientNetworkSession
extends RefCounted

signal command_result_received(request_message_id: String, result: Dictionary)
signal events_applied(events: Array, sequence: int)
signal snapshot_applied(snapshot: Dictionary, sequence: int)
signal snapshot_resync_requested(expected_sequence: int, received_sequence: int)
signal session_failed(reason: String)
signal spectator_views_received(views: Dictionary)

const GameProtocol = preload("res://src/network/game_protocol.gd")
const PeerTransport = preload("res://src/network/peer_transport.gd")
const ReconnectStore = preload("res://src/network/reconnect_store.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const NetworkDiagnostics = preload("res://src/network/network_diagnostics.gd")

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
var _reconnect_store: ReconnectStore
var _room_code: String
var _reconnect_token := ""
var _reconnect_grace_msec := 0
var _now: Callable
var _heartbeat_timeout_msec: int
var _last_host_message_msec: int
var _next_message_id := 1
var _failed := false


func _init(
	transport: PeerTransport,
	host_peer_id: String,
	match_id: String,
	player_id: StringName,
	reconnect_store: ReconnectStore = null,
	room_code: String = "",
	now: Callable = Callable(),
	heartbeat_timeout_msec: int = 6000
) -> void:
	_transport = transport
	_host_peer_id = host_peer_id
	_match_id = match_id
	_player_id = player_id
	_reconnect_store = reconnect_store
	_room_code = room_code.to_upper()
	_now = now
	_heartbeat_timeout_msec = maxi(1, heartbeat_timeout_msec)
	_last_host_message_msec = _now_msec()
	_transport.message_received.connect(_on_message_received)
	_transport.peer_disconnected.connect(_on_peer_disconnected)
	_transport.transport_failed.connect(_on_transport_failed)


func submit_command(message_id: String, command: Dictionary) -> Error:
	if message_id.is_empty():
		return ERR_INVALID_PARAMETER
	var payload := command.duplicate(true)
	payload["player_id"] = str(_player_id)
	if (
		payload.get("kind") == CommandKinds.SET_REPLENISHMENT_REQUEST
		and payload.get("payload") is Dictionary
		and payload["payload"].get("request") is Dictionary
	):
		var request: Dictionary = payload["payload"]["request"]
		var wire_request := {}
		for context in request:
			var wire_context: Variant = str(context) if context is int else context
			if wire_request.has(wire_context):
				return ERR_INVALID_DATA
			wire_request[wire_context] = request[context]
		payload["payload"]["request"] = wire_request
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
		_fail("transport_send_failed")
	return result


func send_view_update(payload: Dictionary) -> Error:
	var envelope := {
		"v": GameProtocol.VERSION, "kind": "view_update",
		"message_id": "client-view-%d" % _next_message_id, "match_id": _match_id,
		"sender_id": str(_player_id), "payload": payload,
	}
	_next_message_id += 1
	var bytes := GameProtocol.encode(envelope)
	return ERR_INVALID_DATA if bytes.is_empty() else _transport.send(_host_peer_id, bytes)


func poll() -> void:
	_transport.poll()
	if not _failed and _now_msec() - _last_host_message_msec > _heartbeat_timeout_msec:
		NetworkDiagnostics.log_event("client", "heartbeat_timeout")
		_fail("host_lost")


func close() -> void:
	if _transport.message_received.is_connected(_on_message_received):
		_transport.message_received.disconnect(_on_message_received)
	if _transport.peer_disconnected.is_connected(_on_peer_disconnected):
		_transport.peer_disconnected.disconnect(_on_peer_disconnected)
	if _transport.transport_failed.is_connected(_on_transport_failed):
		_transport.transport_failed.disconnect(_on_transport_failed)


func _on_message_received(peer_id: String, bytes: PackedByteArray) -> void:
	if peer_id != _host_peer_id:
		return
	_last_host_message_msec = _now_msec()
	var decoded = GameProtocol.decode(bytes)
	if not decoded.ok:
		_fail("invalid_protocol_message")
		return
	var envelope: Dictionary = decoded.envelope
	if envelope["match_id"] != _match_id or envelope["sender_id"] != "host":
		_fail("protocol_violation")
		return
	match envelope["kind"]:
		"command_result":
			_handle_command_result(envelope["payload"])
		"event_batch":
			_handle_event_batch(envelope["payload"])
		"snapshot":
			_handle_snapshot(envelope["payload"])
		"view_update":
			var views: Variant = envelope["payload"].get("views", {})
			if latest_snapshot.has("spectator_views") and views is Dictionary:
				spectator_views_received.emit(views)
		"heartbeat":
			_handle_heartbeat(envelope["payload"])
		"heartbeat_ack":
			pass
		_:
			_fail("protocol_violation")


func _handle_command_result(payload: Dictionary) -> void:
	if (
		typeof(payload.get("request_message_id", null)) != TYPE_STRING
		or typeof(payload.get("accepted", null)) != TYPE_BOOL
		or typeof(payload.get("error_code", null)) != TYPE_STRING
	):
		_fail("malformed_command_result")
		return
	command_result_received.emit(payload["request_message_id"], payload.duplicate(true))


func _handle_event_batch(payload: Dictionary) -> void:
	if (
		typeof(payload.get("sequence", null)) != TYPE_INT
		or not payload.get("events", null) is Array
	):
		_fail("malformed_event_batch")
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
		_fail("malformed_snapshot")
		return
	latest_snapshot = payload["state"].duplicate(true)
	expected_sequence = int(payload["sequence"]) + 1
	_buffered_batches.clear()
	_resync_pending = false
	_persist_reconnect_record(latest_snapshot)
	snapshot_applied.emit(latest_snapshot.duplicate(true), int(payload["sequence"]))


func _handle_heartbeat(payload: Dictionary) -> void:
	if typeof(payload.get("timestamp_msec", null)) != TYPE_INT:
		_fail("malformed_heartbeat")
		return
	var envelope := {
		"v": GameProtocol.VERSION,
		"kind": "heartbeat_ack",
		"message_id": "client-heartbeat-%d" % _next_message_id,
		"match_id": _match_id,
		"sender_id": str(_player_id),
		"payload": {"timestamp_msec": payload["timestamp_msec"]},
	}
	_next_message_id += 1
	var bytes := GameProtocol.encode(envelope)
	if bytes.is_empty() or _transport.send(_host_peer_id, bytes) != OK:
		_fail("transport_send_failed")
		return
	_refresh_reconnect_record()


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
		_fail("direct_connection_failed" if reason == "direct_connection_failed" else "host_lost")


func _on_transport_failed(reason: String) -> void:
	if reason == "direct_connection_failed":
		_fail(reason)


func _persist_reconnect_record(snapshot: Dictionary) -> void:
	if _reconnect_store == null or _room_code.is_empty():
		return
	var lobby_settings: Variant = snapshot.get("lobby_settings")
	if snapshot.get("match_complete", false) or (
		lobby_settings is Dictionary and not lobby_settings.get("match_started", true)
	):
		_reconnect_token = ""
		_reconnect_grace_msec = 0
		_reconnect_store.clear()
		return
	var private_connection: Variant = snapshot.get("private_connection")
	if not private_connection is Dictionary or not lobby_settings is Dictionary:
		return
	var token: Variant = private_connection.get("reconnect_token")
	var grace: Variant = lobby_settings.get("reconnect_grace_msec")
	if (
		typeof(token) != TYPE_STRING or String(token).is_empty()
		or typeof(grace) != TYPE_INT or int(grace) <= 0
	):
		return
	_reconnect_token = String(token)
	_reconnect_grace_msec = int(grace)
	_refresh_reconnect_record()


func _refresh_reconnect_record() -> void:
	if (
		_reconnect_store == null or _room_code.is_empty()
		or _reconnect_token.is_empty() or _reconnect_grace_msec <= 0
	):
		return
	_reconnect_store.save(
		_room_code,
		_player_id,
		_reconnect_token,
		_now_msec() + _heartbeat_timeout_msec + _reconnect_grace_msec
	)


func _fail(reason: String) -> void:
	if _failed:
		return
	_failed = true
	session_failed.emit(reason)


func _now_msec() -> int:
	return (
		int(_now.call()) if _now.is_valid()
		else int(Time.get_unix_time_from_system() * 1000.0)
	)
