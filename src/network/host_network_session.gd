class_name HostNetworkSession
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const DomainEvent = preload("res://src/core/events/domain_event.gd")
const GameProtocol = preload("res://src/network/game_protocol.gd")
const SnapshotProjector = preload("res://src/core/match/snapshot_projector.gd")
const PeerTransport = preload("res://src/network/peer_transport.gd")

const MAX_QUEUED_MESSAGES := 32

var _controller: Variant
var _transport: PeerTransport
var _match_id: String
var _host_id: StringName
var _now: Callable
var _peers := {}
var _player_response_cache := {}
var _recipient_sequences := {}
var _outbound_queues := {}
var _next_message_id := 1


func _init(
	controller: Variant,
	transport: PeerTransport,
	match_id: String,
	host_id: StringName,
	now: Callable = Callable()
) -> void:
	_controller = controller
	_transport = transport
	_match_id = match_id
	_host_id = host_id
	_now = now
	_transport.message_received.connect(_on_message_received)


func register_peer(peer_id: String, player_id: StringName, role: int) -> Error:
	if peer_id.is_empty() or player_id.is_empty():
		return ERR_INVALID_PARAMETER
	if role not in [
		GameTypes.RecipientRole.ACTIVE_PLAYER,
		GameTypes.RecipientRole.PENDING_PLAYER,
		GameTypes.RecipientRole.SPECTATOR,
	]:
		return ERR_INVALID_PARAMETER
	_peers[peer_id] = {"player_id": player_id, "role": role}
	if not _player_response_cache.has(player_id):
		_player_response_cache[player_id] = {}
	if not _recipient_sequences.has(player_id):
		_recipient_sequences[player_id] = 0
	_outbound_queues[peer_id] = []
	return OK


func unregister_peer(peer_id: String) -> void:
	_peers.erase(peer_id)
	_outbound_queues.erase(peer_id)


func publish_events(events: Array) -> void:
	if events.is_empty():
		return
	var peer_ids: Array = _peers.keys()
	for peer_id_variant in peer_ids:
		var peer_id := String(peer_id_variant)
		if not _peers.has(peer_id):
			continue
		var registration: Dictionary = _peers[peer_id]
		var projected := _project_events(events, registration["player_id"])
		if projected.is_empty():
			continue
		var recipient_id: StringName = registration["player_id"]
		_recipient_sequences[recipient_id] = int(_recipient_sequences[recipient_id]) + 1
		_send_envelope(peer_id, _envelope("event_batch", {
			"sequence": _recipient_sequences[recipient_id],
			"events": projected,
		}))


func send_snapshot(peer_id: String) -> Error:
	if not _peers.has(peer_id):
		return ERR_DOES_NOT_EXIST
	var registration: Dictionary = _peers[peer_id]
	var player_id: StringName = registration["player_id"]
	var snapshot := SnapshotProjector.for_recipient(
		_controller.state, player_id, registration["role"]
	)
	return _send_envelope(peer_id, _envelope("snapshot", {
		"sequence": int(_recipient_sequences.get(player_id, 0)),
		"state": snapshot,
	}))


func poll() -> void:
	_transport.poll()
	var peer_ids: Array = _outbound_queues.keys()
	for peer_id_variant in peer_ids:
		var peer_id := String(peer_id_variant)
		if not _peers.has(peer_id):
			continue
		var queue: Array = _outbound_queues[peer_id]
		while not queue.is_empty():
			var result := _transport.send(peer_id, queue[0])
			if result == ERR_BUSY:
				break
			if result != OK:
				_disconnect(peer_id, "transport_send_failed")
				break
			queue.pop_front()


func _on_message_received(peer_id: String, bytes: PackedByteArray) -> void:
	if not _peers.has(peer_id):
		_disconnect(peer_id, "unauthorized_peer")
		return
	var decoded = GameProtocol.decode(bytes)
	if not decoded.ok:
		_disconnect(peer_id, "invalid_protocol_message")
		return
	var envelope: Dictionary = decoded.envelope
	if envelope["match_id"] != _match_id or envelope["kind"] != "command":
		_disconnect(peer_id, "protocol_violation")
		return

	var registration: Dictionary = _peers[peer_id]
	var player_id: StringName = registration["player_id"]
	var response_cache: Dictionary = _player_response_cache[player_id]
	var message_id: String = envelope["message_id"]
	if response_cache.has(message_id):
		_enqueue_or_send(peer_id, response_cache[message_id])
		return

	var payload: Dictionary = envelope["payload"]
	if (
		envelope["sender_id"] != str(player_id)
		or payload.get("player_id", "") != str(player_id)
	):
		_send_command_result(peer_id, player_id, message_id, false, &"sender_mismatch")
		return
	if not _valid_command_payload(payload):
		_send_command_result(peer_id, player_id, message_id, false, &"malformed_command")
		return

	var command := GameCommand.new(
		StringName(payload["command_id"]),
		player_id,
		StringName(payload["kind"]),
		payload["payload"]
	)
	var result = _controller.submit(command, _now_msec())
	_send_command_result(
		peer_id, player_id, message_id, result.accepted, result.error_code
	)
	if result.accepted and not result.events.is_empty():
		publish_events(result.events)


func _send_command_result(
	peer_id: String,
	player_id: StringName,
	request_message_id: String,
	accepted: bool,
	error_code: StringName
) -> void:
	var envelope := _envelope("command_result", {
		"request_message_id": request_message_id,
		"accepted": accepted,
		"error_code": str(error_code),
	})
	var bytes := GameProtocol.encode(envelope)
	if bytes.is_empty():
		_disconnect(peer_id, "protocol_payload_too_large")
		return
	_player_response_cache[player_id][request_message_id] = bytes
	_enqueue_or_send(peer_id, bytes)


func _send_envelope(peer_id: String, envelope: Dictionary) -> Error:
	var bytes := GameProtocol.encode(envelope)
	if bytes.is_empty():
		_disconnect(peer_id, "protocol_payload_too_large")
		return ERR_INVALID_DATA
	return _enqueue_or_send(peer_id, bytes)


func _enqueue_or_send(peer_id: String, bytes: PackedByteArray) -> Error:
	if not _peers.has(peer_id):
		return ERR_DOES_NOT_EXIST
	var queue: Array = _outbound_queues[peer_id]
	if not queue.is_empty():
		return _append_to_queue(peer_id, queue, bytes)
	var result := _transport.send(peer_id, bytes)
	if result == OK:
		return OK
	if result == ERR_BUSY:
		return _append_to_queue(peer_id, queue, bytes)
	_disconnect(peer_id, "transport_send_failed")
	return result


func _append_to_queue(peer_id: String, queue: Array, bytes: PackedByteArray) -> Error:
	if queue.size() >= MAX_QUEUED_MESSAGES:
		_disconnect(peer_id, "outbound_backpressure")
		return ERR_OUT_OF_MEMORY
	queue.append(bytes)
	return OK


func _project_events(events: Array, recipient_id: StringName) -> Array:
	var projected: Array = []
	for event in events:
		if not event is DomainEvent:
			continue
		if event.audience == &"public" or (
			event.audience == &"player" and event.recipient_id == recipient_id
		):
			projected.append({
				"kind": str(event.kind),
				"payload": event.payload.duplicate(true),
			})
	return projected


func _valid_command_payload(payload: Dictionary) -> bool:
	return (
		typeof(payload.get("command_id", null)) == TYPE_STRING
		and not String(payload["command_id"]).is_empty()
		and typeof(payload.get("kind", null)) == TYPE_STRING
		and not String(payload["kind"]).is_empty()
		and payload.get("payload", null) is Dictionary
	)


func _envelope(kind: String, payload: Dictionary) -> Dictionary:
	var message_id := "host-%d" % _next_message_id
	_next_message_id += 1
	return {
		"v": GameProtocol.VERSION,
		"kind": kind,
		"message_id": message_id,
		"match_id": _match_id,
		"sender_id": str(_host_id),
		"payload": payload,
	}


func _disconnect(peer_id: String, reason: String) -> void:
	_transport.disconnect_peer(peer_id, reason)
	unregister_peer(peer_id)


func _now_msec() -> int:
	return int(_now.call()) if _now.is_valid() else Time.get_ticks_msec()
