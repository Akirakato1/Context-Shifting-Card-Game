extends "res://tests/test_case.gd"

const RuntimeGameSession = preload("res://src/view/app/runtime_game_session.gd")
const FakePeerTransport = preload("res://tests/network/fake_peer_transport.gd")


class RuntimeTransport extends FakePeerTransport:
	var hosted_url := ""
	var joined: Dictionary = {}

	func host_room(signaling_url: String) -> Error:
		hosted_url = signaling_url
		return OK

	func join_room(
		signaling_url: String,
		code: String,
		role: String,
		display_name: String = "Player"
	) -> Error:
		joined = {
			"url": signaling_url, "code": code, "role": role,
			"display_name": display_name,
		}
		return OK


func test_host_runtime_builds_authority_after_first_active_peer_and_projects_names() -> void:
	var transport := RuntimeTransport.new()
	var runtime = RuntimeGameSession.new(transport, Callable(self, "_now"))
	var snapshots: Array[Dictionary] = []
	var results: Array[Dictionary] = []
	runtime.snapshot_applied.connect(func(snapshot: Dictionary, _sequence: int):
		snapshots.append(snapshot)
	)
	runtime.command_result_received.connect(func(message_id: String, result: Dictionary):
		results.append({"message_id": message_id, "result": result})
	)

	assert_eq(runtime.start_host("ws://127.0.0.1:8080", "Mira"), OK)
	assert_eq(transport.hosted_url, "ws://127.0.0.1:8080")
	transport.lobby_created.emit("ABC234")
	assert_eq(snapshots[-1].screen_id, "lobby")
	assert_eq(snapshots[-1].room_code, "ABC234")
	assert_eq(snapshots[-1].players[0].name, "Mira")

	transport.join_status.emit("approved", {
		"peer_id": "peer-one", "role": "active", "display_name": "Noah",
	})
	transport.peer_connected.emit("peer-one")
	var joined: Dictionary = snapshots[-1]
	assert_eq(joined.active_player_count, 2)
	assert_eq(joined.players.map(func(player): return player.name), ["Mira", "Noah"])
	assert_true(joined.has("private_hand"))
	assert_eq(joined.private_hand.size(), 6)
	assert_eq(joined.private_abilities.size(), 2)
	assert_true(transport.sent.any(func(entry):
		return entry.peer_id == "peer-one"
	))

	assert_eq(runtime.start_match(), OK)
	assert_eq(runtime.submit_command("ready-host", {
		"command_id": "ready-host-command",
		"kind": "set_ready",
		"payload": {"ready": true},
	}), OK)
	assert_eq(results[-1].message_id, "ready-host")
	assert_true(results[-1].result.accepted)
	assert_eq(snapshots[-1].screen_id, "match")
	runtime.close()


func test_join_runtime_uses_assigned_peer_id_for_authoritative_commands() -> void:
	var transport := RuntimeTransport.new()
	var runtime = RuntimeGameSession.new(transport, Callable(self, "_now"))
	assert_eq(runtime.start_join(
		"ws://127.0.0.1:8080", "abc234", "active", "Noah"
	), OK)
	assert_eq(transport.joined, {
		"url": "ws://127.0.0.1:8080", "code": "ABC234", "role": "active",
		"display_name": "Noah",
	})
	transport.join_status.emit("approved", {
		"peer_id": "peer-one", "role": "active", "display_name": "Noah",
	})
	transport.peer_connected.emit("host")
	assert_eq(runtime.submit_command("ready-guest", {
		"command_id": "ready-guest-command",
		"kind": "set_ready",
		"payload": {"ready": true},
	}), OK)
	var outbound = transport.sent[-1]
	var decoded = preload("res://src/network/game_protocol.gd").decode(outbound.bytes)
	assert_true(decoded.ok)
	assert_eq(decoded.envelope.sender_id, "peer-one")
	assert_eq(decoded.envelope.payload.player_id, "peer-one")
	runtime.close()


func _now() -> int:
	return 1000
