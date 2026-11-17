class_name SignalingClient
extends RefCounted

signal room_created(code: String)
signal ice_servers_received(servers: Array, relay_available: bool)
signal join_requested(
	peer_id: String,
	role: String,
	join_nonce: String,
	display_name: String,
	reconnect_player_id: String
)
signal join_approved(peer_id: String, role: String)
signal signal_received(type: String, peer_id: String, payload: Dictionary)
signal failed(reason: String)

const VERSION := 1
const SIGNAL_TYPES: Array[String] = ["offer", "answer", "ice_candidate"]
const VALID_ROLES: Array[String] = ["active", "spectator"]
const SOCKET_CONNECTING := 0
const SOCKET_OPEN := 1
const SOCKET_CLOSING := 2
const SOCKET_CLOSED := 3
const MAX_ICE_SERVERS := 8
const MAX_URLS_PER_SERVER := 8
const MAX_URL_LENGTH := 2048
const MAX_CREDENTIAL_LENGTH := 1024

enum State {
	IDLE,
	CONNECTING,
	WAITING,
	READY,
	FAILED,
	CLOSED,
}

var state: int = State.IDLE
var room_code := ""
var host_token := ""
var join_nonce := ""
var peer_id := ""
var role := ""
var display_name := ""
var reconnect_player_id := ""

var _socket_factory: Callable
var _now: Callable
var _timeout_msec: int
var _socket: Variant
var _url := ""
var _mode := ""
var _deadline_msec := 0
var _initial_message_sent := false
var _reconnecting := false


func _init(
	socket_factory: Callable = Callable(),
	now: Callable = Callable(),
	timeout_msec: int = 10_000
) -> void:
	_socket_factory = socket_factory
	_now = now
	_timeout_msec = maxi(1, timeout_msec)


func begin_host(url: String) -> Error:
	if url.is_empty():
		return ERR_INVALID_PARAMETER
	room_code = ""
	host_token = ""
	join_nonce = ""
	peer_id = ""
	role = "active"
	display_name = "Host"
	reconnect_player_id = ""
	_mode = "host"
	_url = url
	_reconnecting = false
	return _open_socket()


func begin_join(
	url: String,
	code: String,
	requested_role: String,
	requested_display_name: String = "Player",
	requested_reconnect_player_id: String = ""
) -> Error:
	requested_display_name = requested_display_name.strip_edges()
	if (
		url.is_empty() or code.is_empty() or not VALID_ROLES.has(requested_role)
		or requested_display_name.is_empty() or requested_display_name.length() > 32
	):
		return ERR_INVALID_PARAMETER
	room_code = code.to_upper()
	host_token = ""
	join_nonce = ""
	peer_id = ""
	role = requested_role
	display_name = requested_display_name
	reconnect_player_id = requested_reconnect_player_id
	_mode = "join"
	_url = url
	_reconnecting = false
	return _open_socket()


func reconnect() -> Error:
	if _url.is_empty() or _mode.is_empty():
		return ERR_UNCONFIGURED
	_reconnecting = true
	return _open_socket()


func approve_join(nonce: String) -> Error:
	if (
		_mode != "host" or state != State.READY or room_code.is_empty()
		or host_token.is_empty() or nonce.is_empty()
	):
		return ERR_UNCONFIGURED
	return _send({
		"v": VERSION,
		"type": "approve_join",
		"code": room_code,
		"host_token": host_token,
		"join_nonce": nonce,
	})


func send_signal(remote_peer_id: String, type: String, payload: Dictionary) -> Error:
	if state != State.READY or not SIGNAL_TYPES.has(type):
		return ERR_UNCONFIGURED
	var message := {
		"v": VERSION,
		"type": type,
		"code": room_code,
		"payload": payload.duplicate(true),
	}
	if _mode == "host":
		if remote_peer_id.is_empty() or host_token.is_empty():
			return ERR_INVALID_PARAMETER
		message["host_token"] = host_token
		message["peer_id"] = remote_peer_id
	else:
		if join_nonce.is_empty():
			return ERR_UNCONFIGURED
		message["join_nonce"] = join_nonce
	return _send(message)


func poll() -> void:
	if _socket == null or state == State.FAILED or state == State.CLOSED:
		return
	_socket.poll()
	var socket_state: int = _socket.get_ready_state()
	if socket_state == SOCKET_OPEN and not _initial_message_sent:
		if _send_initial_message() != OK:
			_fail("signaling_send_failed")
			return
		_initial_message_sent = true
		state = State.WAITING
		_deadline_msec = _now_msec() + _timeout_msec

	while socket_state == SOCKET_OPEN and _socket.get_available_packet_count() > 0:
		_handle_packet(_socket.get_packet())
		if state == State.FAILED:
			return

	if socket_state == SOCKET_CLOSED and state != State.CLOSED:
		_fail("signaling_closed")
		return
	if (state == State.CONNECTING or state == State.WAITING) and _now_msec() > _deadline_msec:
		_fail("signaling_timeout")


func close() -> void:
	if _socket != null and _socket.get_ready_state() < SOCKET_CLOSING:
		_socket.close(1000, "client_closed")
	state = State.CLOSED


func _open_socket() -> Error:
	if _socket != null and _socket.get_ready_state() < SOCKET_CLOSING:
		_socket.close(1000, "reconnecting")
	_socket = _socket_factory.call() if _socket_factory.is_valid() else WebSocketPeer.new()
	if _socket == null:
		state = State.FAILED
		return ERR_CANT_CREATE
	var connect_error: Error = _socket.connect_to_url(_url)
	if connect_error != OK:
		state = State.FAILED
		return connect_error
	state = State.CONNECTING
	_initial_message_sent = false
	_deadline_msec = _now_msec() + _timeout_msec
	return OK


func _send_initial_message() -> Error:
	if _mode == "host":
		var message := {"v": VERSION, "type": "host_room"}
		if _reconnecting and not room_code.is_empty() and not host_token.is_empty():
			message["code"] = room_code
			message["host_token"] = host_token
			message["reconnect"] = true
		return _send(message)
	var join_message := {
		"v": VERSION,
		"type": "join_room",
		"code": room_code,
		"role": role,
		"display_name": display_name,
	}
	if not reconnect_player_id.is_empty():
		join_message["reconnect_player_id"] = reconnect_player_id
	if _reconnecting:
		join_message["reconnect"] = true
	return _send(join_message)


func _send(message: Dictionary) -> Error:
	if _socket == null or _socket.get_ready_state() != SOCKET_OPEN:
		return ERR_CONNECTION_ERROR
	return _socket.send_text(JSON.stringify(message))


func _handle_packet(bytes: PackedByteArray) -> void:
	var parsed = JSON.parse_string(bytes.get_string_from_utf8())
	if (
		not parsed is Dictionary or parsed.get("v") != VERSION
		or typeof(parsed.get("type", null)) != TYPE_STRING
	):
		_fail("malformed_signaling_message")
		return
	var type: String = parsed["type"]
	match type:
		"room_created":
			if not _has_strings(parsed, ["code", "host_token"]):
				_fail("malformed_signaling_message")
				return
			if not _apply_ice_server_payload(parsed):
				return
			room_code = String(parsed["code"]).to_upper()
			host_token = parsed["host_token"]
			state = State.READY
			_reconnecting = false
			room_created.emit(room_code)
		"join_pending":
			if not _has_strings(parsed, ["code", "role", "join_nonce", "peer_id"]):
				_fail("malformed_signaling_message")
				return
			room_code = String(parsed["code"]).to_upper()
			role = parsed["role"]
			join_nonce = parsed["join_nonce"]
			peer_id = parsed["peer_id"]
			state = State.WAITING
			_deadline_msec = _now_msec() + _timeout_msec
		"join_approved":
			if not _has_strings(parsed, ["role", "join_nonce", "peer_id"]):
				_fail("malformed_signaling_message")
				return
			if not join_nonce.is_empty() and parsed["join_nonce"] != join_nonce:
				_fail("join_nonce_mismatch")
				return
			if not _apply_ice_server_payload(parsed):
				return
			join_nonce = parsed["join_nonce"]
			peer_id = parsed["peer_id"]
			role = parsed["role"]
			state = State.READY
			_reconnecting = false
			join_approved.emit(peer_id, role)
		"join_requested":
			if not _has_strings(parsed, ["peer_id", "role", "join_nonce", "display_name"]):
				_fail("malformed_signaling_message")
				return
			join_requested.emit(
				parsed["peer_id"], parsed["role"], parsed["join_nonce"],
				parsed["display_name"], str(parsed.get("reconnect_player_id", ""))
			)
		"offer", "answer", "ice_candidate":
			if not _has_strings(parsed, ["peer_id"]) or not parsed.get("payload") is Dictionary:
				_fail("malformed_signaling_message")
				return
			signal_received.emit(type, parsed["peer_id"], parsed["payload"].duplicate(true))
		"error":
			if typeof(parsed.get("error", null)) != TYPE_STRING:
				_fail("malformed_signaling_message")
			else:
				_fail(parsed["error"])
		"room_closed":
			_fail("host_closed")
		_:
			_fail("unknown_signaling_message")


func _has_strings(message: Dictionary, keys: Array) -> bool:
	for key in keys:
		if typeof(message.get(key, null)) != TYPE_STRING or String(message[key]).is_empty():
			return false
	return true


func _apply_ice_server_payload(message: Dictionary) -> bool:
	var has_servers := message.has("ice_servers")
	var has_relay_available := message.has("relay_available")
	if not has_servers and not has_relay_available:
		return true
	if has_servers != has_relay_available or not message["relay_available"] is bool:
		_fail("malformed_signaling_message")
		return false
	var normalization := _normalize_ice_servers(message["ice_servers"])
	if not bool(normalization.get("ok", false)):
		_fail("malformed_signaling_message")
		return false
	var servers: Array = normalization["servers"]
	var relay_available: bool = message["relay_available"]
	if relay_available and not _has_turn_server(servers):
		_fail("malformed_signaling_message")
		return false
	ice_servers_received.emit(servers.duplicate(true), relay_available)
	return true


func _normalize_ice_servers(value: Variant) -> Dictionary:
	if not value is Array or value.is_empty() or value.size() > MAX_ICE_SERVERS:
		return {"ok": false}
	var normalized: Array = []
	for entry_variant in value:
		if not entry_variant is Dictionary:
			return {"ok": false}
		var entry: Dictionary = entry_variant
		var source_urls: Array = []
		if entry.get("urls") is String:
			source_urls = [entry["urls"]]
		elif entry.get("urls") is Array:
			source_urls = entry["urls"]
		else:
			return {"ok": false}
		if source_urls.is_empty() or source_urls.size() > MAX_URLS_PER_SERVER:
			return {"ok": false}
		var urls: Array[String] = []
		for url_variant in source_urls:
			if not url_variant is String:
				return {"ok": false}
			var url: String = url_variant
			if (
				url.is_empty() or url.length() > MAX_URL_LENGTH
				or not _is_ice_url(url)
			):
				return {"ok": false}
			urls.append(url)
		var has_username := entry.has("username")
		var has_credential := entry.has("credential")
		if has_username != has_credential:
			return {"ok": false}
		var clean_entry := {"urls": urls}
		if has_username:
			if (
				not entry["username"] is String or not entry["credential"] is String
				or String(entry["username"]).is_empty()
				or String(entry["credential"]).is_empty()
				or String(entry["username"]).length() > MAX_CREDENTIAL_LENGTH
				or String(entry["credential"]).length() > MAX_CREDENTIAL_LENGTH
			):
				return {"ok": false}
			clean_entry["username"] = entry["username"]
			clean_entry["credential"] = entry["credential"]
		normalized.append(clean_entry)
	return {"ok": true, "servers": normalized}


func _has_turn_server(servers: Array) -> bool:
	for entry_variant in servers:
		var entry: Dictionary = entry_variant
		if not entry.has("username") or not entry.has("credential"):
			continue
		for url_variant in entry["urls"]:
			var url: String = url_variant
			if url.to_lower().begins_with("turn:") or url.to_lower().begins_with("turns:"):
				return true
	return false


func _is_ice_url(url: String) -> bool:
	var lowered := url.to_lower()
	return (
		lowered.begins_with("stun:") or lowered.begins_with("stuns:")
		or lowered.begins_with("turn:") or lowered.begins_with("turns:")
	)


func _fail(reason: String) -> void:
	if state == State.FAILED:
		return
	state = State.FAILED
	if _socket != null and _socket.get_ready_state() < SOCKET_CLOSING:
		_socket.close(1008, reason)
	failed.emit(reason)


func _now_msec() -> int:
	return int(_now.call()) if _now.is_valid() else Time.get_ticks_msec()
