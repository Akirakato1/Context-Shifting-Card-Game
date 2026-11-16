extends "res://tests/test_case.gd"

const SignalingClient = preload("res://src/network/signaling_client.gd")

var _now_msec := 1000
var _socket_queue: Array = []


class FakeSocket extends RefCounted:
	var ready_state := 0
	var connect_urls: Array[String] = []
	var sent: Array[String] = []
	var inbound: Array[PackedByteArray] = []

	func connect_to_url(url: String) -> Error:
		connect_urls.append(url)
		return OK

	func poll() -> Error:
		return OK

	func get_ready_state() -> int:
		return ready_state

	func send_text(message: String) -> Error:
		sent.append(message)
		return OK

	func get_available_packet_count() -> int:
		return inbound.size()

	func get_packet() -> PackedByteArray:
		return inbound.pop_front()

	func close(_code: int = 1000, _reason: String = "") -> void:
		ready_state = 3

	func open() -> void:
		ready_state = 1

	func queue_message(message: Dictionary) -> void:
		inbound.append(JSON.stringify(message).to_utf8_buffer())


class VoidPollSocket extends RefCounted:
	var ready_state := 0

	func connect_to_url(_url: String) -> Error:
		return OK

	func poll() -> void:
		pass

	func get_ready_state() -> int:
		return ready_state

	func send_text(_message: String) -> Error:
		return OK

	func get_available_packet_count() -> int:
		return 0

	func get_packet() -> PackedByteArray:
		return PackedByteArray()

	func close(_code: int = 1000, _reason: String = "") -> void:
		ready_state = 3


func before_each() -> void:
	_now_msec = 1000
	_socket_queue.clear()


func test_socket_poll_supports_the_real_void_return_contract() -> void:
	_socket_queue.append(VoidPollSocket.new())
	var client = _client()
	assert_eq(client.begin_host("ws://127.0.0.1:9"), OK)
	client.poll()
	assert_eq(client.state, SignalingClient.State.CONNECTING)


func test_host_receives_code_approves_join_and_routes_signals() -> void:
	var socket := FakeSocket.new()
	_socket_queue.append(socket)
	var client = _client()
	var requested: Array = []
	var routed: Array = []
	client.join_requested.connect(func(peer_id, role, nonce, display_name):
		requested.append([peer_id, role, nonce, display_name])
	)
	client.signal_received.connect(func(type, peer_id, payload):
		routed.append([type, peer_id, payload])
	)

	assert_eq(client.begin_host("wss://signal.example"), OK)
	socket.open()
	client.poll()
	assert_eq(_sent(socket, 0), {"v": 1, "type": "host_room"})

	socket.queue_message(_server("room_created", {
		"code": "AB3D5F", "host_token": "host-secret",
	}))
	client.poll()
	assert_eq(client.state, SignalingClient.State.READY)
	assert_eq(client.room_code, "AB3D5F")

	socket.queue_message(_server("join_requested", {
		"code": "AB3D5F", "peer_id": "peer-1", "role": "active",
		"join_nonce": "nonce-1", "display_name": "Mira",
	}))
	client.poll()
	assert_eq(requested, [["peer-1", "active", "nonce-1", "Mira"]])
	assert_eq(client.approve_join("nonce-1"), OK)
	assert_eq(_sent(socket, 1), {
		"v": 1, "type": "approve_join", "code": "AB3D5F",
		"host_token": "host-secret", "join_nonce": "nonce-1",
	})

	assert_eq(client.send_signal("peer-1", "answer", {"sdp": "answer-sdp"}), OK)
	assert_eq(_sent(socket, 2)["peer_id"], "peer-1")
	assert_eq(_sent(socket, 2)["host_token"], "host-secret")
	socket.queue_message(_server("ice_candidate", {
		"code": "AB3D5F", "peer_id": "peer-1",
		"payload": {"media": "0", "index": 0, "name": "candidate"},
	}))
	client.poll()
	assert_eq(routed[0][0], "ice_candidate")
	assert_eq(routed[0][1], "peer-1")


func test_join_sends_role_then_uses_approved_nonce_for_offer_and_answer() -> void:
	var socket := FakeSocket.new()
	_socket_queue.append(socket)
	var client = _client()
	var approved: Array = []
	var routed: Array = []
	client.join_approved.connect(func(peer_id, role): approved.append([peer_id, role]))
	client.signal_received.connect(func(type, peer_id, payload):
		routed.append([type, peer_id, payload])
	)

	assert_eq(client.begin_join("wss://signal.example", "ab3d5f", "spectator", "Mira"), OK)
	socket.open()
	client.poll()
	assert_eq(_sent(socket, 0), {
		"v": 1, "type": "join_room", "code": "AB3D5F", "role": "spectator",
		"display_name": "Mira",
	})
	socket.queue_message(_server("join_pending", {
		"code": "AB3D5F", "role": "spectator", "join_nonce": "nonce-2",
		"peer_id": "peer-2",
	}))
	socket.queue_message(_server("join_approved", {
		"code": "AB3D5F", "role": "spectator", "join_nonce": "nonce-2",
		"peer_id": "peer-2",
	}))
	client.poll()
	assert_eq(client.state, SignalingClient.State.READY)
	assert_eq(approved, [["peer-2", "spectator"]])

	assert_eq(client.send_signal("host", "offer", {"sdp": "offer-sdp"}), OK)
	assert_eq(_sent(socket, 1), {
		"v": 1, "type": "offer", "code": "AB3D5F", "join_nonce": "nonce-2",
		"payload": {"sdp": "offer-sdp"},
	})
	socket.queue_message(_server("answer", {
		"code": "AB3D5F", "peer_id": "peer-2", "payload": {"sdp": "answer-sdp"},
	}))
	client.poll()
	assert_eq(routed, [["answer", "peer-2", {"sdp": "answer-sdp"}]])


func test_room_errors_host_close_and_timeout_have_bounded_failure_states() -> void:
	for server_error in ["room_not_found", "active_seats_full", "spectator_slots_full"]:
		var socket := FakeSocket.new()
		_socket_queue.append(socket)
		var client = _client()
		var failures: Array[String] = []
		client.failed.connect(func(reason): failures.append(reason))
		client.begin_join("wss://signal.example", "AB3D5F", "active")
		socket.open()
		client.poll()
		socket.queue_message(_server("error", {"error": server_error}))
		client.poll()
		assert_eq(failures, [server_error])
		assert_eq(client.state, SignalingClient.State.FAILED)

	var close_socket := FakeSocket.new()
	_socket_queue.append(close_socket)
	var close_client = _client()
	var close_failures: Array[String] = []
	close_client.failed.connect(func(reason): close_failures.append(reason))
	close_client.begin_join("wss://signal.example", "AB3D5F", "active")
	close_socket.open()
	close_client.poll()
	close_socket.queue_message(_server("room_closed", {"code": "AB3D5F"}))
	close_client.poll()
	assert_eq(close_failures, ["host_closed"])

	var timeout_socket := FakeSocket.new()
	_socket_queue.append(timeout_socket)
	var timeout_client = _client(50)
	var timeout_failures: Array[String] = []
	timeout_client.failed.connect(func(reason): timeout_failures.append(reason))
	timeout_client.begin_host("wss://signal.example")
	_now_msec += 51
	timeout_client.poll()
	assert_eq(timeout_failures, ["signaling_timeout"])
	assert_eq(timeout_socket.ready_state, 3)


func test_reconnect_preserves_host_room_credentials() -> void:
	var first := FakeSocket.new()
	var second := FakeSocket.new()
	_socket_queue.append(first)
	_socket_queue.append(second)
	var client = _client()
	client.begin_host("wss://signal.example")
	first.open()
	client.poll()
	first.queue_message(_server("room_created", {
		"code": "AB3D5F", "host_token": "host-secret",
	}))
	client.poll()

	assert_eq(client.reconnect(), OK)
	second.open()
	client.poll()
	assert_eq(_sent(second, 0), {
		"v": 1, "type": "host_room", "code": "AB3D5F",
		"host_token": "host-secret", "reconnect": true,
	})


func _client(timeout_msec: int = 1000):
	return SignalingClient.new(
		Callable(self, "_make_socket"), Callable(self, "_now"), timeout_msec
	)


func _make_socket():
	return _socket_queue.pop_front()


func _now() -> int:
	return _now_msec


func _server(type: String, fields: Dictionary) -> Dictionary:
	var result := {"v": 1, "type": type}
	result.merge(fields)
	return result


func _sent(socket: FakeSocket, index: int) -> Dictionary:
	var message: Dictionary = JSON.parse_string(socket.sent[index])
	message["v"] = int(message["v"])
	return message
