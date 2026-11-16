extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")
const GameProtocol = preload("res://src/network/game_protocol.gd")
const HostNetworkSession = preload("res://src/network/host_network_session.gd")
const ClientNetworkSession = preload("res://src/network/client_network_session.gd")
const ReconnectStore = preload("res://src/network/reconnect_store.gd")
const FakePeerTransport = preload("res://tests/network/fake_peer_transport.gd")

var _now_msec := 1000
var _token_sequence := 0


func before_each() -> void:
	_now_msec = 1000
	_token_sequence = 0


func test_heartbeat_timeout_freezes_once_and_overlapping_grace_resolves_independently() -> void:
	var state := MatchState.create(_config([&"one", &"two", &"three"], 200), 131)
	var controller := MatchController.new(state)
	var transport := FakePeerTransport.new()
	var host := _host(controller, transport, 50, 100)
	assert_eq(host.register_peer(
		"peer-two", &"two", GameTypes.RecipientRole.ACTIVE_PLAYER
	), OK)
	assert_eq(host.register_peer(
		"peer-three", &"three", GameTypes.RecipientRole.ACTIVE_PLAYER
	), OK)

	_now_msec = 1051
	host.poll()
	assert_eq(_decoded_kind_count(transport, "peer-two", "heartbeat"), 1)
	assert_eq(_decoded_kind_count(transport, "peer-three", "heartbeat"), 1)
	_now_msec = 1090
	transport.inject_message("peer-three", GameProtocol.encode(_peer_envelope(
		"heartbeat_ack", "ack-three", "three", {"timestamp_msec": 1051}
	)))
	_now_msec = 1101
	host.poll()

	assert_false(state.players[&"two"].connected)
	assert_true(state.players[&"three"].connected)
	assert_true(state.frozen)
	var first_deadline: int = state.players[&"two"].disconnect_deadline_msec
	host.poll()
	assert_eq(state.players[&"two"].disconnect_deadline_msec, first_deadline)

	_now_msec = 1191
	host.poll()
	assert_false(state.players[&"three"].connected)
	assert_true(state.frozen)
	assert_true(
		state.players[&"three"].disconnect_deadline_msec
		> state.players[&"two"].disconnect_deadline_msec
	)

	_now_msec = first_deadline
	host.poll()
	assert_false(state.players[&"two"].active)
	assert_true(state.players[&"three"].active)
	assert_true(state.frozen)
	_now_msec = state.players[&"three"].disconnect_deadline_msec
	host.poll()
	assert_false(state.players[&"three"].active)
	assert_false(state.frozen)
	assert_true(state.match_complete)
	assert_eq(state.winner_id, &"one")


func test_reconnect_rejects_wrong_token_rotates_on_success_and_sends_private_snapshot() -> void:
	var state := MatchState.create(_config([&"one", &"two"], 500), 132)
	var controller := MatchController.new(state)
	var transport := FakePeerTransport.new()
	var host := _host(controller, transport, 50, 100)
	assert_eq(host.register_peer(
		"peer-two", &"two", GameTypes.RecipientRole.ACTIVE_PLAYER
	), OK)
	var original_token: String = state.players[&"two"].reconnect_token
	assert_false(original_token.is_empty())

	transport.close_with_reason("peer-two", "connection_closed")
	assert_true(state.frozen)
	var wrong := host.reconnect_peer("peer-two-new", &"two", "wrong-token")
	assert_false(wrong.accepted)
	assert_eq(wrong.error_code, "invalid_reconnect_token")
	assert_false(host.has_peer("peer-two-new"))

	var accepted := host.reconnect_peer("peer-two-new", &"two", original_token)
	assert_true(accepted.accepted)
	assert_true(host.has_peer("peer-two-new"))
	assert_true(state.players[&"two"].connected)
	assert_false(state.frozen)
	assert_ne(state.players[&"two"].reconnect_token, original_token)
	assert_false(state.players[&"two"].reconnect_token.is_empty())
	var snapshot := _last_kind(transport, "peer-two-new", "snapshot")
	assert_eq(
		snapshot.payload.state.private_connection.reconnect_token,
		state.players[&"two"].reconnect_token
	)


func test_unregistered_direct_peer_can_reclaim_seat_with_reconnect_command() -> void:
	var state := MatchState.create(_config([&"one", &"two"], 500), 134)
	var controller := MatchController.new(state)
	var transport := FakePeerTransport.new()
	var host := _host(controller, transport, 50, 100)
	host.register_peer("peer-two", &"two", GameTypes.RecipientRole.ACTIVE_PLAYER)
	var token: String = state.players[&"two"].reconnect_token
	transport.close_with_reason("peer-two", "connection_closed")
	transport.clear_sent()

	transport.inject_message("peer-two-new", GameProtocol.encode(_peer_envelope(
		"command", "reconnect-message", "two", {
			"command_id": "reconnect-command",
			"player_id": "two",
			"kind": "reconnect",
			"payload": {"token": token},
		}
	)))

	assert_true(host.has_peer("peer-two-new"))
	assert_true(state.players[&"two"].connected)
	var command_result := _last_kind(transport, "peer-two-new", "command_result")
	var snapshot := _last_kind(transport, "peer-two-new", "snapshot")
	if command_result.is_empty() or snapshot.is_empty():
		return
	assert_true(command_result.payload.accepted)
	assert_eq(snapshot.payload.state.private_connection.reconnect_token,
		state.players[&"two"].reconnect_token)


func test_grace_expiry_publishes_authoritative_forfeit_to_surviving_peer() -> void:
	var state := MatchState.create(_config([&"one", &"two", &"three"], 200), 133)
	var controller := MatchController.new(state)
	var transport := FakePeerTransport.new()
	var host := _host(controller, transport, 50, 1000)
	host.register_peer("peer-two", &"two", GameTypes.RecipientRole.ACTIVE_PLAYER)
	host.register_peer("peer-three", &"three", GameTypes.RecipientRole.ACTIVE_PLAYER)
	transport.close_with_reason("peer-two", "connection_closed")
	var deadline: int = state.players[&"two"].disconnect_deadline_msec
	_now_msec = deadline - 1
	transport.inject_message("peer-three", GameProtocol.encode(_peer_envelope(
		"heartbeat_ack", "keep-three", "three", {"timestamp_msec": _now_msec}
	)))
	transport.clear_sent()
	_now_msec = deadline
	host.poll()

	assert_false(state.players[&"two"].active)
	assert_true(state.players[&"three"].active)
	assert_true(_network_event_kinds(transport, "peer-three").has("player_forfeited"))


func test_client_acks_heartbeat_ignores_signaling_loss_and_bounds_host_loss() -> void:
	var transport := FakePeerTransport.new()
	var client := ClientNetworkSession.new(
		transport, "host", "match-1", &"two", null, "", Callable(self, "_now"), 100
	)
	var failures: Array[String] = []
	client.session_failed.connect(func(reason): failures.append(reason))

	transport.transport_failed.emit("signaling_closed")
	assert_eq(failures, [])
	transport.inject_message("host", GameProtocol.encode(_host_envelope(
		"heartbeat", "heartbeat-1", {"timestamp_msec": _now_msec}
	)))
	assert_eq(_last_kind(transport, "host", "heartbeat_ack").payload.timestamp_msec, _now_msec)
	_now_msec += 101
	client.poll()
	assert_eq(failures, ["host_lost"])

	var direct_transport := FakePeerTransport.new()
	var direct_client := ClientNetworkSession.new(
		direct_transport, "host", "match-2", &"two"
	)
	var direct_failures: Array[String] = []
	direct_client.session_failed.connect(func(reason): direct_failures.append(reason))
	direct_transport.close_with_reason("host", "direct_connection_failed")
	assert_eq(direct_failures, ["direct_connection_failed"])


func test_reconnect_store_persists_verifies_expires_and_deletes_record() -> void:
	var path := "user://reconnect-session-test-%d.json" % Time.get_ticks_usec()
	var store := ReconnectStore.new(path)
	assert_eq(store.save("ABC234", &"two", "secret-token", 1500), OK)
	assert_eq(store.load_record(1200), {
		"room_code": "ABC234",
		"player_id": "two",
		"token": "secret-token",
		"expires_at": 1500,
	})
	assert_true(store.verify("abc234", &"two", "secret-token", 1200))
	assert_false(store.verify("ABC234", &"two", "wrong", 1200))
	assert_true(store.load_record(1501).is_empty())
	assert_false(FileAccess.file_exists(path))

	assert_eq(store.save("ABC234", &"two", "rotated-token", 2000), OK)
	assert_eq(store.clear(), OK)
	assert_true(store.load_record(1600).is_empty())


func test_owner_snapshot_updates_relaunch_store_with_rotated_token() -> void:
	var path := "user://reconnect-snapshot-test-%d.json" % Time.get_ticks_usec()
	var store := ReconnectStore.new(path)
	var transport := FakePeerTransport.new()
	var client := ClientNetworkSession.new(
		transport, "host", "match-1", &"two", store, "ABC234",
		Callable(self, "_now"), 5000
	)
	transport.inject_message("host", GameProtocol.encode(_host_envelope(
		"snapshot", "snapshot-1", {
			"sequence": 0,
			"state": {
				"private_player_id": "two",
				"private_connection": {"reconnect_token": "first-token"},
				"lobby_settings": {"reconnect_grace_msec": 300},
			},
		}
	)))
	assert_true(store.verify("ABC234", &"two", "first-token", _now_msec))

	transport.inject_message("host", GameProtocol.encode(_host_envelope(
		"snapshot", "snapshot-2", {
			"sequence": 0,
			"state": {
				"private_player_id": "two",
				"private_connection": {"reconnect_token": "rotated-token"},
				"lobby_settings": {"reconnect_grace_msec": 300},
			},
		}
	)))
	assert_false(store.verify("ABC234", &"two", "first-token", _now_msec))
	assert_true(store.verify("ABC234", &"two", "rotated-token", _now_msec))
	store.clear()


func test_heartbeat_refreshes_relaunch_record_through_host_detection_window() -> void:
	var path := "user://reconnect-heartbeat-test-%d.json" % Time.get_ticks_usec()
	var store := ReconnectStore.new(path)
	var transport := FakePeerTransport.new()
	var client := ClientNetworkSession.new(
		transport, "host", "match-1", &"two", store, "ABC234",
		Callable(self, "_now"), 100
	)
	transport.inject_message("host", GameProtocol.encode(_host_envelope(
		"snapshot", "snapshot-1", {
			"sequence": 0,
			"state": {
				"private_player_id": "two",
				"private_connection": {"reconnect_token": "relaunch-token"},
				"lobby_settings": {"reconnect_grace_msec": 300},
			},
		}
	)))
	assert_eq(store.load_record(_now_msec).expires_at, 1400)

	_now_msec = 1100
	transport.inject_message("host", GameProtocol.encode(_host_envelope(
		"heartbeat", "heartbeat-1", {"timestamp_msec": _now_msec}
	)))
	assert_true(store.verify("ABC234", &"two", "relaunch-token", 1500))
	assert_false(store.verify("ABC234", &"two", "relaunch-token", 1501))


func _host(
	controller: MatchController,
	transport: FakePeerTransport,
	heartbeat_interval_msec: int,
	heartbeat_timeout_msec: int
) -> HostNetworkSession:
	return HostNetworkSession.new(
		controller, transport, "match-1", &"one", Callable(self, "_now"),
		heartbeat_interval_msec, heartbeat_timeout_msec, Callable(self, "_token")
	)


func _config(player_ids: Array, reconnect_grace_msec: int) -> MatchConfig:
	var abilities: Array[AbilityDefinition] = []
	for index in range(24):
		abilities.append(AbilityDefinition.new(
			StringName("ability-%d" % index), AbilityDefinition.Timing.HAND_SHAPE,
			[], &"noop"
		))
	return MatchConfig.new(
		player_ids, [], GameTypes.VictoryMode.SCORE_RACE, 100,
		GameTypes.InformationVisibility.PUBLIC,
		{
			GameTypes.Phase.START: 5000,
			GameTypes.Phase.MAIN_1: 5000,
			GameTypes.Phase.HAND_PLAY: 5000,
			GameTypes.Phase.MAIN_2: 5000,
			GameTypes.Phase.END: 2000,
		},
		1000, 5000, reconnect_grace_msec, abilities
	)


func _now() -> int:
	return _now_msec


func _token(_player_id: StringName) -> String:
	_token_sequence += 1
	return "network-token-%d" % _token_sequence


func _peer_envelope(
	kind: String,
	message_id: String,
	sender_id: String,
	payload: Dictionary
) -> Dictionary:
	return {
		"v": 1, "kind": kind, "message_id": message_id,
		"match_id": "match-1", "sender_id": sender_id, "payload": payload,
	}


func _host_envelope(kind: String, message_id: String, payload: Dictionary) -> Dictionary:
	return _peer_envelope(kind, message_id, "host", payload)


func _last_kind(transport: FakePeerTransport, peer_id: String, kind: String) -> Dictionary:
	var matches: Array = []
	for entry in transport.sent:
		if entry.peer_id != peer_id:
			continue
		var decoded = GameProtocol.decode(entry.bytes)
		if decoded.ok and decoded.envelope.kind == kind:
			matches.append(decoded.envelope)
	assert_true(not matches.is_empty(), "expected %s for %s" % [kind, peer_id])
	return matches[-1] if not matches.is_empty() else {}


func _decoded_kind_count(
	transport: FakePeerTransport,
	peer_id: String,
	kind: String
) -> int:
	var count := 0
	for entry in transport.sent:
		if entry.peer_id != peer_id:
			continue
		var decoded = GameProtocol.decode(entry.bytes)
		if decoded.ok and decoded.envelope.kind == kind:
			count += 1
	return count


func _network_event_kinds(transport: FakePeerTransport, peer_id: String) -> Array:
	var result: Array = []
	for entry in transport.sent:
		if entry.peer_id != peer_id:
			continue
		var decoded = GameProtocol.decode(entry.bytes)
		if decoded.ok and decoded.envelope.kind == "event_batch":
			for event: Dictionary in decoded.envelope.payload.events:
				result.append(event.kind)
	return result
