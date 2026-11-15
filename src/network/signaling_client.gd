class_name SignalingClient
extends RefCounted

signal room_created(code: String)
signal join_requested(peer_id: String, role: String, join_nonce: String)
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
	_mode = "host"
	_url = url
	_reconnecting = false
	return _open_socket()


func begin_join(url: String, code: String, requested_role: String) -> Error:
	if url.is_empty() or code.is_empty() or not VALID_ROLES.has(requested_role):
		return ERR_INVALID_PARAMETER
	room_code = code.to_upper()
	host_token = ""
	join_nonce = ""
	peer_id = ""
	role = requested_role
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
	var poll_error: Error = _socket.poll()
	if poll_error != OK:
		_fail("signaling_socket_error")
		return
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
	}
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
			join_nonce = parsed["join_nonce"]
			peer_id = parsed["peer_id"]
			role = parsed["role"]
			state = State.READY
			_reconnecting = false
			join_approved.emit(peer_id, role)
		"join_requested":
			if not _has_strings(parsed, ["peer_id", "role", "join_nonce"]):
				_fail("malformed_signaling_message")
				return
			join_requested.emit(parsed["peer_id"], parsed["role"], parsed["join_nonce"])
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


func _fail(reason: String) -> void:
	if state == State.FAILED:
		return
	state = State.FAILED
	if _socket != null and _socket.get_ready_state() < SOCKET_CLOSING:
		_socket.close(1008, reason)
	failed.emit(reason)


func _now_msec() -> int:
	return int(_now.call()) if _now.is_valid() else Time.get_ticks_msec()
