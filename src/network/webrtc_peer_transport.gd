class_name WebRTCPeerTransport
extends "res://src/network/peer_transport.gd"

signal signal_generated(peer_id: String, type: String, payload: Dictionary)

const SignalingClient = preload("res://src/network/signaling_client.gd")
const CHANNEL_LABEL := "game-v1"
const CHANNEL_ID := 1
const MAX_HOST_REMOTES := 7

var _signaling: SignalingClient
var _ice_urls: Array[String] = []
var _now: Callable
var _connect_timeout_msec: int
var _peers := {}
var _host_mode := false


func _init(
	signaling: SignalingClient = null,
	ice_urls: Array = [],
	now: Callable = Callable(),
	connect_timeout_msec: int = 15_000
) -> void:
	_signaling = signaling
	for url in ice_urls:
		_ice_urls.append(String(url))
	_now = now
	_connect_timeout_msec = maxi(1, connect_timeout_msec)
	if _signaling != null:
		_wire_signaling()


func host_room(signaling_url: String) -> Error:
	if _signaling == null:
		return ERR_UNCONFIGURED
	_host_mode = true
	return _signaling.begin_host(signaling_url)


func join_room(
	signaling_url: String,
	code: String,
	role: String,
	display_name: String = "Player",
	reconnect_player_id: String = ""
) -> Error:
	if _signaling == null:
		return ERR_UNCONFIGURED
	_host_mode = false
	return _signaling.begin_join(
		signaling_url, code, role, display_name, reconnect_player_id
	)


func prepare_host_peer(peer_id: String) -> Error:
	_host_mode = true
	return _create_peer(peer_id)


func connect_direct(peer_id: String = "host") -> Error:
	_host_mode = false
	var create_error := _create_peer(peer_id)
	if create_error != OK:
		return create_error
	var peer: WebRTCPeerConnection = _peers[peer_id]["connection"]
	var offer_error := peer.create_offer()
	if offer_error != OK:
		_drop_peer(peer_id, "direct_connection_failed")
	return offer_error


func apply_signal(peer_id: String, type: String, payload: Dictionary) -> Error:
	if peer_id.is_empty():
		return ERR_INVALID_PARAMETER
	if type == "offer" and not _peers.has(peer_id):
		var create_error := _create_peer(peer_id)
		if create_error != OK:
			return create_error
	if not _peers.has(peer_id):
		return ERR_DOES_NOT_EXIST
	var peer: WebRTCPeerConnection = _peers[peer_id]["connection"]
	match type:
		"offer", "answer":
			if typeof(payload.get("sdp", null)) != TYPE_STRING:
				return ERR_INVALID_DATA
			return peer.set_remote_description(type, payload["sdp"])
		"ice_candidate":
			if (
				typeof(payload.get("media", null)) != TYPE_STRING
				or typeof(payload.get("index", null)) not in [TYPE_INT, TYPE_FLOAT]
				or typeof(payload.get("name", null)) != TYPE_STRING
			):
				return ERR_INVALID_DATA
			return peer.add_ice_candidate(
				payload["media"], int(payload["index"]), payload["name"]
			)
	return ERR_INVALID_PARAMETER


func send(peer_id: String, bytes: PackedByteArray) -> Error:
	if not _peers.has(peer_id):
		return ERR_DOES_NOT_EXIST
	var channel: WebRTCDataChannel = _peers[peer_id]["channel"]
	if channel == null or channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return ERR_CONNECTION_ERROR
	return channel.put_packet(bytes)


func close_peer(peer_id: String) -> void:
	_drop_peer(peer_id, "closed")


func disconnect_peer(peer_id: String, reason: String) -> void:
	_drop_peer(peer_id, reason)


func close() -> void:
	var peer_ids: Array = _peers.keys()
	for peer_id in peer_ids:
		var record: Dictionary = _peers[peer_id]
		var channel: WebRTCDataChannel = record["channel"]
		if channel != null:
			channel.close()
		var peer: WebRTCPeerConnection = record["connection"]
		peer.close()
	_peers.clear()
	if _signaling != null:
		_signaling.close()


func reconnect_signaling() -> Error:
	return _signaling.reconnect() if _signaling != null else ERR_UNCONFIGURED


func poll() -> void:
	if _signaling != null:
		_signaling.poll()
	var peer_ids: Array = _peers.keys()
	for peer_id_variant in peer_ids:
		var peer_id := String(peer_id_variant)
		if not _peers.has(peer_id):
			continue
		var record: Dictionary = _peers[peer_id]
		var peer: WebRTCPeerConnection = record["connection"]
		if peer.poll() != OK:
			_drop_peer(peer_id, "direct_connection_failed")
			continue
		var connection_state := peer.get_connection_state()
		if connection_state in [
			WebRTCPeerConnection.STATE_DISCONNECTED,
			WebRTCPeerConnection.STATE_FAILED,
		]:
			_drop_peer(peer_id, "direct_connection_failed")
			continue
		if connection_state == WebRTCPeerConnection.STATE_CLOSED:
			_drop_peer(peer_id, "connection_closed")
			continue

		var channel: WebRTCDataChannel = record["channel"]
		if channel != null and channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			if not record["connected"]:
				record["connected"] = true
				peer_connected.emit(peer_id)
			while channel.get_available_packet_count() > 0:
				message_received.emit(peer_id, channel.get_packet())
		elif channel != null and channel.get_ready_state() == WebRTCDataChannel.STATE_CLOSED:
			_drop_peer(
				peer_id,
				"connection_closed" if record["connected"] else "direct_connection_failed"
			)
			continue
		if not record["connected"] and _now_msec() > int(record["deadline_msec"]):
			_drop_peer(peer_id, "direct_connection_failed")


func remote_peer_ids() -> Array[String]:
	var result: Array[String] = []
	for peer_id in _peers:
		result.append(String(peer_id))
	result.sort()
	return result


func is_reliable_ordered(peer_id: String) -> bool:
	if not _peers.has(peer_id):
		return false
	var channel: WebRTCDataChannel = _peers[peer_id]["channel"]
	return channel != null and channel.get_label() == CHANNEL_LABEL and channel.is_ordered()


func _create_peer(peer_id: String) -> Error:
	if peer_id.is_empty() or _peers.has(peer_id):
		return ERR_ALREADY_EXISTS if _peers.has(peer_id) else ERR_INVALID_PARAMETER
	if _host_mode and _peers.size() >= MAX_HOST_REMOTES:
		return ERR_BUSY
	if not _host_mode and not _peers.is_empty():
		return ERR_BUSY

	var peer := WebRTCPeerConnection.new()
	var ice_servers: Array = []
	for url in _ice_urls:
		ice_servers.append({"urls": [url]})
	var initialize_error := peer.initialize({"iceServers": ice_servers})
	if initialize_error != OK:
		return initialize_error
	peer.session_description_created.connect(_on_session_description.bind(peer_id))
	peer.ice_candidate_created.connect(_on_ice_candidate.bind(peer_id))
	var channel := peer.create_data_channel(CHANNEL_LABEL, {
		"negotiated": true,
		"id": CHANNEL_ID,
		"ordered": true,
		"protocol": "shift-game-v1",
	})
	if channel == null:
		peer.close()
		return ERR_CANT_CREATE
	channel.write_mode = WebRTCDataChannel.WRITE_MODE_BINARY
	_peers[peer_id] = {
		"connection": peer,
		"channel": channel,
		"connected": false,
		"deadline_msec": _now_msec() + _connect_timeout_msec,
	}
	return OK


func _on_session_description(type: String, sdp: String, peer_id: String) -> void:
	if not _peers.has(peer_id):
		return
	var peer: WebRTCPeerConnection = _peers[peer_id]["connection"]
	if peer.set_local_description(type, sdp) != OK:
		_drop_peer(peer_id, "direct_connection_failed")
		return
	var payload := {"sdp": sdp}
	signal_generated.emit(peer_id, type, payload)
	if _signaling != null:
		_signaling.send_signal(peer_id, type, payload)


func _on_ice_candidate(media: String, index: int, name: String, peer_id: String) -> void:
	if not _peers.has(peer_id):
		return
	var payload := {"media": media, "index": index, "name": name}
	signal_generated.emit(peer_id, "ice_candidate", payload)
	if _signaling != null:
		_signaling.send_signal(peer_id, "ice_candidate", payload)


func _wire_signaling() -> void:
	_signaling.room_created.connect(func(code): lobby_created.emit(code))
	_signaling.join_requested.connect(_on_join_requested)
	_signaling.join_approved.connect(_on_join_approved)
	_signaling.signal_received.connect(_on_signaling_signal)
	_signaling.failed.connect(func(reason): transport_failed.emit(reason))


func _on_join_requested(
	peer_id: String,
	role: String,
	nonce: String,
	display_name: String,
	reconnect_player_id: String
) -> void:
	if not _host_mode:
		return
	var result := prepare_host_peer(peer_id)
	if result == OK:
		_signaling.approve_join(nonce)
		join_status.emit("approved", {
			"peer_id": peer_id, "role": role, "display_name": display_name,
			"reconnect_player_id": reconnect_player_id,
		})
	else:
		join_status.emit("rejected", {"peer_id": peer_id, "role": role, "error": result})


func _on_join_approved(assigned_peer_id: String, role: String) -> void:
	if _host_mode:
		return
	join_status.emit("approved", {
		"peer_id": assigned_peer_id, "role": role,
		"display_name": _signaling.display_name,
		"reconnect_player_id": _signaling.reconnect_player_id,
	})
	var result := connect_direct("host")
	if result != OK:
		transport_failed.emit("direct_connection_failed")


func _on_signaling_signal(type: String, remote_peer_id: String, payload: Dictionary) -> void:
	var local_peer_id := remote_peer_id if _host_mode else "host"
	var result := apply_signal(local_peer_id, type, payload)
	if result != OK:
		transport_failed.emit("invalid_signaling_payload")


func _drop_peer(peer_id: String, reason: String) -> void:
	if not _peers.has(peer_id):
		return
	var record: Dictionary = _peers[peer_id]
	var channel: WebRTCDataChannel = record["channel"]
	if channel != null:
		channel.close()
	var peer: WebRTCPeerConnection = record["connection"]
	peer.close()
	_peers.erase(peer_id)
	peer_disconnected.emit(peer_id, reason)


func _now_msec() -> int:
	return int(_now.call()) if _now.is_valid() else Time.get_ticks_msec()
