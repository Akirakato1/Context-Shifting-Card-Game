extends "res://tests/test_case.gd"

const WebRTCPeerTransport = preload("res://src/network/webrtc_peer_transport.gd")

var _now_msec := 1000


func before_each() -> void:
	_now_msec = 1000


func test_loopback_star_peers_exchange_reliable_ordered_binary_packets() -> void:
	var host = _transport()
	var client = _transport()
	var host_connected: Array[String] = []
	var client_connected: Array[String] = []
	var host_messages: Array = []
	var client_messages: Array = []
	var signal_errors: Array[int] = []
	host.peer_connected.connect(func(peer_id): host_connected.append(peer_id))
	client.peer_connected.connect(func(peer_id): client_connected.append(peer_id))
	host.message_received.connect(func(peer_id, bytes): host_messages.append([peer_id, bytes]))
	client.message_received.connect(func(peer_id, bytes): client_messages.append([peer_id, bytes]))
	var host_relay := func(_peer_id, type, payload):
		var result = client.apply_signal("host", type, payload)
		if result != OK:
			signal_errors.append(result)
	var client_relay := func(_peer_id, type, payload):
		var result = host.apply_signal("client-1", type, payload)
		if result != OK:
			signal_errors.append(result)
	host.signal_generated.connect(host_relay)
	client.signal_generated.connect(client_relay)

	assert_eq(host.prepare_host_peer("client-1"), OK)
	assert_eq(client.connect_direct("host"), OK)
	if not await _poll_until(
		func(): return not host_connected.is_empty() and not client_connected.is_empty(),
		[host, client]
	):
		host.signal_generated.disconnect(host_relay)
		client.signal_generated.disconnect(client_relay)
		host.close()
		client.close()
		host = null
		client = null
		await _settle_native_resources()
		return

	assert_eq(host_connected, ["client-1"])
	assert_eq(client_connected, ["host"])
	assert_eq(signal_errors, [])
	assert_eq(host.remote_peer_ids(), ["client-1"])
	assert_eq(client.remote_peer_ids(), ["host"])
	assert_true(host.is_reliable_ordered("client-1"))
	assert_true(client.is_reliable_ordered("host"))

	assert_eq(client.send("host", "from-client".to_utf8_buffer()), OK)
	assert_eq(host.send("client-1", "from-host".to_utf8_buffer()), OK)
	if not await _poll_until(
		func(): return host_messages.size() == 1 and client_messages.size() == 1,
		[host, client]
	):
		host.signal_generated.disconnect(host_relay)
		client.signal_generated.disconnect(client_relay)
		host.close()
		client.close()
		host = null
		client = null
		await _settle_native_resources()
		return
	assert_eq(host_messages[0], ["client-1", "from-client".to_utf8_buffer()])
	assert_eq(client_messages[0], ["host", "from-host".to_utf8_buffer()])

	host.close_peer("client-1")
	client.poll()
	assert_eq(host.remote_peer_ids(), [])
	host.signal_generated.disconnect(host_relay)
	client.signal_generated.disconnect(client_relay)
	host.close()
	client.close()
	host = null
	client = null
	await _settle_native_resources()


func test_host_capacity_is_seven_and_unconnected_peer_times_out_cleanly() -> void:
	var host = _transport(25)
	for index in range(7):
		assert_eq(host.prepare_host_peer("peer-%d" % index), OK)
	assert_eq(host.prepare_host_peer("peer-7"), ERR_BUSY)
	var failures: Array = []
	host.peer_disconnected.connect(func(peer_id, reason): failures.append([peer_id, reason]))

	_now_msec += 26
	host.poll()
	assert_eq(failures.size(), 7)
	for failure in failures:
		assert_eq(failure[1], "direct_connection_failed")
	assert_eq(host.remote_peer_ids(), [])
	host.close()
	host = null
	await _settle_native_resources()


func _transport(timeout_msec: int = 5000):
	return WebRTCPeerTransport.new(null, [], Callable(self, "_now"), timeout_msec)


func _now() -> int:
	return _now_msec


func _poll_until(condition: Callable, transports: Array) -> bool:
	for _iteration in range(2000):
		for transport in transports:
			transport.poll()
		if condition.call():
			return true
		await Engine.get_main_loop().process_frame
	assert_true(false, "timed out waiting for direct WebRTC loopback")
	return false


func _settle_native_resources() -> void:
	for _frame in range(4):
		await Engine.get_main_loop().process_frame
