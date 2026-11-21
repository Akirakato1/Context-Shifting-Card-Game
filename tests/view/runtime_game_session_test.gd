extends "res://tests/test_case.gd"

const RuntimeGameSession = preload("res://src/view/app/runtime_game_session.gd")
const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const FakePeerTransport = preload("res://tests/network/fake_peer_transport.gd")


class RuntimeTransport extends FakePeerTransport:
	var hosted_url := ""
	var joined: Dictionary = {}
	var signaling_reconnects := 0
	var relay_fallback := false

	func host_room(signaling_url: String) -> Error:
		hosted_url = signaling_url
		return OK

	func reconnect_signaling() -> Error:
		signaling_reconnects += 1
		return OK

	func has_relay_fallback() -> bool:
		return relay_fallback

	func join_room(
		signaling_url: String,
		code: String,
		role: String,
		display_name: String = "Player",
		reconnect_player_id: String = ""
	) -> Error:
		joined = {
			"url": signaling_url, "code": code, "role": role,
			"display_name": display_name,
			"reconnect_player_id": reconnect_player_id,
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

	transport.clear_sent()
	transport.join_status.emit("approved", {
		"peer_id": "peer-two", "role": "active", "display_name": "Iris",
	})
	transport.peer_connected.emit("peer-two")
	var third_player: Dictionary = snapshots[-1].players.filter(
		func(player): return player.player_id == "peer-two"
	)[0]
	assert_false(third_player.pending)
	var peer_two_messages := transport.sent.filter(
		func(entry): return entry.peer_id == "peer-two"
	)
	var peer_two_snapshot = preload("res://src/network/game_protocol.gd").decode(
		peer_two_messages[-1].bytes
	).envelope.payload.state
	assert_eq(peer_two_snapshot.private_hand.size(), 6)
	assert_eq(peer_two_snapshot.private_abilities.size(), 2)
	var failures: Array[String] = []
	runtime.session_failed.connect(func(reason: String): failures.append(reason))
	transport.transport_failed.emit("signaling_closed")
	assert_eq(transport.signaling_reconnects, 1)
	assert_true(failures.is_empty())

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


func test_runtime_config_uses_twenty_eight_real_manipulation_cards() -> void:
	var transport := RuntimeTransport.new()
	var runtime = RuntimeGameSession.new(transport, Callable(self, "_now"))
	assert_eq(runtime.start_host("ws://127.0.0.1:8080", "Mira"), OK)
	transport.lobby_created.emit("ABC234")
	transport.join_status.emit("approved", {
		"peer_id": "peer-one", "role": "active", "display_name": "Noah",
	})
	transport.peer_connected.emit("peer-one")

	var definitions: Array = runtime._controller.state.config.ability_definitions
	var counts := {}
	for definition in definitions:
		counts[definition.id] = int(counts.get(definition.id, 0)) + 1
	assert_eq(definitions.size(), 28)
	assert_eq(counts.size(), 14)
	for count in counts.values():
		assert_eq(count, 2)
	assert_false(definitions.any(func(definition):
		return str(definition.id).begins_with("placeholder_ability_")
	))
	runtime.close()


func test_ability_catalog_projects_name_rules_text_timing_and_schema() -> void:
	var definitions: Array = []
	for definition in AbilityCatalog.manipulation_definitions(1):
		definitions.append({
			"id": str(definition.id), "timing": definition.timing,
			"tags": definition.tags, "effect_id": str(definition.effect_id),
			"choice_schema": definition.choice_schema,
			"display_name": definition.display_name,
			"rules_text": definition.rules_text,
		})
	var runtime = RuntimeGameSession.new(RuntimeTransport.new(), Callable(self, "_now"))
	var catalog: Dictionary = runtime._ability_catalog(definitions)

	assert_eq(catalog.size(), 14)
	assert_eq(catalog.context_exchange.label, "Context Exchange")
	assert_true(catalog.context_exchange.rules_text.contains("Swap the contexts"))
	assert_eq(
		catalog.context_exchange.timing,
		preload("res://src/core/abilities/ability_definition.gd").Timing.HAND_MANIPULATION
	)
	assert_eq(catalog.context_exchange.choice_schema.steps[0].kind, "full_card")


func test_join_runtime_uses_assigned_peer_id_for_authoritative_commands() -> void:
	var transport := RuntimeTransport.new()
	var runtime = RuntimeGameSession.new(transport, Callable(self, "_now"))
	assert_eq(runtime.start_join(
		"ws://127.0.0.1:8080", "abc234", "active", "Noah"
	), OK)
	assert_eq(transport.joined, {
		"url": "ws://127.0.0.1:8080", "code": "ABC234", "role": "active",
		"display_name": "Noah", "reconnect_player_id": "",
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


func test_direct_failure_reports_whether_relay_fallback_was_available() -> void:
	var transport := RuntimeTransport.new()
	var runtime = RuntimeGameSession.new(transport, Callable(self, "_now"))
	var failures: Array[String] = []
	runtime.session_failed.connect(func(reason: String): failures.append(reason))
	assert_eq(runtime.start_join(
		"ws://127.0.0.1:8080", "ABC234", "active", "Noah"
	), OK)

	transport.transport_failed.emit("direct_connection_failed")
	assert_eq(failures, ["relay_unavailable"])
	runtime.close()

	transport = RuntimeTransport.new()
	transport.relay_fallback = true
	runtime = RuntimeGameSession.new(transport, Callable(self, "_now"))
	failures.clear()
	runtime.session_failed.connect(func(reason: String): failures.append(reason))
	assert_eq(runtime.start_join(
		"ws://127.0.0.1:8080", "ABC234", "active", "Noah"
	), OK)
	transport.transport_failed.emit("direct_connection_failed")
	assert_eq(failures, ["direct_connection_failed"])
	runtime.close()


func test_retry_uses_saved_player_identity_and_reconnect_token() -> void:
	var store = preload("res://src/network/reconnect_store.gd").new(
		"user://runtime-session-reconnect-test.json"
	)
	store.clear()
	var first := RuntimeTransport.new()
	var second := RuntimeTransport.new()
	var replacements: Array = [second]
	var runtime = RuntimeGameSession.new(
		first, Callable(self, "_now"), store,
		func(): return replacements.pop_front()
	)
	var connections: Array[String] = []
	runtime.connection_state_changed.connect(func(state: Dictionary):
		connections.append(str(state.status))
	)
	assert_eq(runtime.start_join(
		"ws://127.0.0.1:8080", "ABC234", "active", "Noah"
	), OK)
	first.join_status.emit("approved", {
		"peer_id": "old-player", "role": "active", "display_name": "Noah",
	})
	first.peer_connected.emit("host")
	var snapshot_envelope := {
		"v": 1, "kind": "snapshot", "message_id": "host-snapshot",
		"match_id": "shift-match", "sender_id": "host",
		"payload": {"sequence": 0, "state": {
			"match_complete": false,
			"private_connection": {"reconnect_token": "secret-token"},
			"lobby_settings": {"reconnect_grace_msec": 30000},
		}},
	}
	first.inject_message(
		"host", preload("res://src/network/game_protocol.gd").encode(snapshot_envelope)
	)
	first.peer_disconnected.emit("host", "network_lost")
	assert_eq(runtime.retry_connection(), OK)
	assert_eq(second.joined.reconnect_player_id, "old-player")
	second.join_status.emit("approved", {
		"peer_id": "new-route", "role": "active", "display_name": "Noah",
		"reconnect_player_id": "old-player",
	})
	second.peer_connected.emit("host")
	var reconnect_message = preload("res://src/network/game_protocol.gd").decode(
		second.sent[-1].bytes
	)
	assert_true(reconnect_message.ok)
	assert_eq(reconnect_message.envelope.sender_id, "old-player")
	assert_eq(reconnect_message.envelope.payload.kind, "reconnect")
	assert_eq(reconnect_message.envelope.payload.payload.token, "secret-token")
	second.inject_message("host", preload("res://src/network/game_protocol.gd").encode({
		"v": 1, "kind": "command_result", "message_id": "host-result",
		"match_id": "shift-match", "sender_id": "host",
		"payload": {
			"request_message_id": "runtime-reconnect-message",
			"accepted": true, "error_code": "",
		},
	}))
	assert_eq(connections[-1], "connected")
	runtime.close()
	store.clear()


func _now() -> int:
	return 1000
