class_name HostNetworkSession
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const DomainEvent = preload("res://src/core/events/domain_event.gd")
const GameProtocol = preload("res://src/network/game_protocol.gd")
const SnapshotProjector = preload("res://src/core/match/snapshot_projector.gd")
const PeerTransport = preload("res://src/network/peer_transport.gd")

const MAX_QUEUED_MESSAGES := 32
const DEFAULT_HEARTBEAT_INTERVAL_MSEC := 2000
const DEFAULT_HEARTBEAT_TIMEOUT_MSEC := 6000

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
var _next_join_command_id := 1
var _next_reconnect_command_id := 1
var _heartbeat_interval_msec: int
var _heartbeat_timeout_msec: int
var _token_provider: Callable


func _init(
	controller: Variant,
	transport: PeerTransport,
	match_id: String,
	host_id: StringName,
	now: Callable = Callable(),
	heartbeat_interval_msec: int = DEFAULT_HEARTBEAT_INTERVAL_MSEC,
	heartbeat_timeout_msec: int = DEFAULT_HEARTBEAT_TIMEOUT_MSEC,
	token_provider: Callable = Callable()
) -> void:
	_controller = controller
	_transport = transport
	_match_id = match_id
	_host_id = host_id
	_now = now
	_heartbeat_interval_msec = maxi(1, heartbeat_interval_msec)
	_heartbeat_timeout_msec = maxi(_heartbeat_interval_msec + 1, heartbeat_timeout_msec)
	_token_provider = token_provider
	_transport.message_received.connect(_on_message_received)
	_transport.peer_disconnected.connect(_on_peer_disconnected)


func register_peer(peer_id: String, player_id: StringName, role: int) -> Error:
	if peer_id.is_empty() or player_id.is_empty():
		return ERR_INVALID_PARAMETER
	if role not in [
		GameTypes.RecipientRole.ACTIVE_PLAYER,
		GameTypes.RecipientRole.PENDING_PLAYER,
		GameTypes.RecipientRole.SPECTATOR,
	]:
		return ERR_INVALID_PARAMETER
	if _peers.has(peer_id):
		var existing: Dictionary = _peers[peer_id]
		if existing["player_id"] != player_id or existing["role"] != role:
			return ERR_ALREADY_IN_USE
		return ERR_ALREADY_EXISTS
	var now_msec := _now_msec()
	_peers[peer_id] = {
		"player_id": player_id,
		"role": role,
		"last_seen_msec": now_msec,
		"last_heartbeat_msec": now_msec,
	}
	if role == GameTypes.RecipientRole.ACTIVE_PLAYER:
		_ensure_reconnect_token(player_id)
	if not _player_response_cache.has(player_id):
		_player_response_cache[player_id] = {}
	if not _recipient_sequences.has(player_id):
		_recipient_sequences[player_id] = 0
	_outbound_queues[peer_id] = []
	return OK


func has_peer(peer_id: String) -> bool:
	return _peers.has(peer_id)


func reconnect_peer(peer_id: String, player_id: StringName, token: String) -> Dictionary:
	if peer_id.is_empty() or player_id.is_empty() or token.is_empty():
		return {"accepted": false, "error_code": "malformed_reconnect"}
	if _peers.has(peer_id):
		return {"accepted": false, "error_code": "peer_already_admitted"}
	var command := GameCommand.new(
		StringName("network-reconnect-%d" % _next_reconnect_command_id),
		player_id,
		CommandKinds.RECONNECT,
		{"token": token}
	)
	_next_reconnect_command_id += 1
	var result = _controller.submit(command, _now_msec())
	if not result.accepted:
		return {"accepted": false, "error_code": str(result.error_code)}
	for existing_peer_id_variant in _peers.keys():
		var existing_peer_id := String(existing_peer_id_variant)
		if _peers[existing_peer_id]["player_id"] == player_id:
			unregister_peer(existing_peer_id)
	if register_peer(peer_id, player_id, GameTypes.RecipientRole.ACTIVE_PLAYER) != OK:
		return {"accepted": false, "error_code": "peer_registration_failed"}
	publish_events(result.events)
	send_snapshot(peer_id)
	return {"accepted": true, "error_code": ""}


func admit_peer(peer_id: String, player_id: StringName, requested_role: String) -> Dictionary:
	if requested_role not in ["active", "spectator"]:
		return {"accepted": false, "error_code": "invalid_role"}
	if _peers.has(peer_id):
		var existing: Dictionary = _peers[peer_id]
		if existing["player_id"] != player_id or (
			(requested_role == "spectator") != (
				existing["role"] == GameTypes.RecipientRole.SPECTATOR
			)
		):
			return {"accepted": false, "error_code": "role_change_not_allowed"}
		return {"accepted": false, "error_code": "peer_already_admitted"}

	var command_kind := (
		CommandKinds.JOIN_ACTIVE if requested_role == "active"
		else CommandKinds.JOIN_SPECTATOR
	)
	var command := GameCommand.new(
		StringName("network-join-%d" % _next_join_command_id), player_id, command_kind
	)
	_next_join_command_id += 1
	var result = _controller.submit(command, _now_msec())
	if not result.accepted:
		return {"accepted": false, "error_code": str(result.error_code)}

	var network_role := (
		GameTypes.RecipientRole.PENDING_PLAYER if requested_role == "active"
		else GameTypes.RecipientRole.SPECTATOR
	)
	if register_peer(peer_id, player_id, network_role) != OK:
		return {"accepted": false, "error_code": "peer_registration_failed"}
	publish_events([DomainEvent.new(
		&"participant_joined",
		{"player_id": str(player_id), "role": requested_role},
		&"public"
	)])
	send_snapshot(peer_id)
	return {"accepted": true, "error_code": ""}


func sync_player_activation(player_id: StringName) -> Error:
	if not _controller.state.players.has(player_id):
		return ERR_DOES_NOT_EXIST
	var player = _controller.state.players[player_id]
	if not player.active or player.pending:
		return ERR_BUSY
	var peer_id := ""
	for candidate in _peers:
		if _peers[candidate]["player_id"] == player_id:
			peer_id = candidate
			break
	if peer_id.is_empty():
		return ERR_DOES_NOT_EXIST
	if _peers[peer_id]["role"] != GameTypes.RecipientRole.PENDING_PLAYER:
		return ERR_ALREADY_EXISTS
	_peers[peer_id]["role"] = GameTypes.RecipientRole.ACTIVE_PLAYER
	_ensure_reconnect_token(player_id)
	publish_events([DomainEvent.new(
		&"player_activated", {"player_id": str(player_id)}, &"public"
	)])
	return send_snapshot(peer_id)


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
		var projected := _project_events(
			events, registration["player_id"], registration["role"]
		)
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
	snapshot["lobby_settings"] = _controller.state.config.to_dict()
	return _send_envelope(peer_id, _envelope("snapshot", {
		"sequence": int(_recipient_sequences.get(player_id, 0)),
		"state": snapshot,
	}))


func poll() -> void:
	_transport.poll()
	var now_msec := _now_msec()
	var heartbeat_peer_ids: Array = _peers.keys()
	for peer_id_variant in heartbeat_peer_ids:
		var peer_id := String(peer_id_variant)
		if not _peers.has(peer_id):
			continue
		var registration: Dictionary = _peers[peer_id]
		if now_msec - int(registration["last_seen_msec"]) > _heartbeat_timeout_msec:
			_disconnect(peer_id, "heartbeat_timeout")
			continue
		if now_msec - int(registration["last_heartbeat_msec"]) >= _heartbeat_interval_msec:
			registration["last_heartbeat_msec"] = now_msec
			_send_envelope(peer_id, _envelope("heartbeat", {
				"timestamp_msec": now_msec,
			}))
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
	var controller_events: Array = _controller.tick(now_msec)
	if not controller_events.is_empty():
		publish_events(controller_events)


func _on_message_received(peer_id: String, bytes: PackedByteArray) -> void:
	if not _peers.has(peer_id):
		_disconnect(peer_id, "unauthorized_peer")
		return
	var decoded = GameProtocol.decode(bytes)
	if not decoded.ok:
		_disconnect(peer_id, "invalid_protocol_message")
		return
	var envelope: Dictionary = decoded.envelope
	if envelope["match_id"] != _match_id:
		_disconnect(peer_id, "protocol_violation")
		return

	var registration: Dictionary = _peers[peer_id]
	var player_id: StringName = registration["player_id"]
	registration["last_seen_msec"] = _now_msec()
	if envelope["kind"] == "heartbeat_ack":
		if (
			envelope["sender_id"] != str(player_id)
			or typeof(envelope["payload"].get("timestamp_msec", null)) != TYPE_INT
		):
			_disconnect(peer_id, "protocol_violation")
		return
	if envelope["kind"] == "heartbeat":
		if (
			envelope["sender_id"] != str(player_id)
			or typeof(envelope["payload"].get("timestamp_msec", null)) != TYPE_INT
		):
			_disconnect(peer_id, "protocol_violation")
			return
		_send_envelope(peer_id, _envelope("heartbeat_ack", {
			"timestamp_msec": envelope["payload"]["timestamp_msec"],
		}))
		return
	if envelope["kind"] != "command":
		_disconnect(peer_id, "protocol_violation")
		return
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


func _project_events(events: Array, recipient_id: StringName, role: int) -> Array:
	var projected: Array = []
	for event in events:
		if not event is DomainEvent:
			continue
		if event.audience == &"public" or (
			event.audience == &"player"
			and role == GameTypes.RecipientRole.ACTIVE_PLAYER
			and event.recipient_id == recipient_id
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
	if _peers.has(peer_id):
		_on_peer_disconnected(peer_id, reason)


func _on_peer_disconnected(peer_id: String, reason: String) -> void:
	if not _peers.has(peer_id):
		return
	var registration: Dictionary = _peers[peer_id]
	var player_id: StringName = registration["player_id"]
	var role: int = registration["role"]
	unregister_peer(peer_id)
	if role != GameTypes.RecipientRole.ACTIVE_PLAYER:
		return
	if not _controller.state.players.has(player_id):
		return
	var player = _controller.state.players[player_id]
	if not player.connected:
		return
	_controller.notify_player_disconnected(player_id, _now_msec())
	publish_events([DomainEvent.new(
		&"player_disconnected",
		{
			"player_id": str(player_id),
			"reason": reason,
			"reconnect_deadline_msec": player.disconnect_deadline_msec,
		},
		&"public"
	)])


func _ensure_reconnect_token(player_id: StringName) -> void:
	if not _controller.state.players.has(player_id):
		return
	var player = _controller.state.players[player_id]
	if player.reconnect_token.is_empty():
		player.reconnect_token = _new_reconnect_token(player_id)


func _new_reconnect_token(player_id: StringName) -> String:
	if _token_provider.is_valid():
		var provided: Variant = _token_provider.call(player_id)
		if provided is String and not provided.is_empty():
			return provided
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(32).hex_encode()


func _now_msec() -> int:
	return int(_now.call()) if _now.is_valid() else Time.get_ticks_msec()
