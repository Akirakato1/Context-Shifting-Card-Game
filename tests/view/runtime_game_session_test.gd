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

	var opening_abilities: Array = snapshots[-1].private_abilities.map(func(ability): return ability.copy_id)
	transport.clear_sent()
	assert_eq(runtime.start_match(), OK)
	assert_eq(snapshots[-1].phase, GameTypes.Phase.MAIN_1)
	assert_eq(snapshots[-1].private_abilities.map(func(ability): return ability.copy_id), opening_abilities)
	assert_eq(snapshots[-1].phase_deadline_msec, _now() + runtime._controller.state.config.public_hard_limit_msec)
	var guest_opening := transport.sent.filter(
		func(entry): return entry.peer_id == "peer-two"
	)
	var guest_snapshot = preload("res://src/network/game_protocol.gd").decode(
		guest_opening[-1].bytes
	).envelope.payload.state
	assert_eq(guest_snapshot.phase, GameTypes.Phase.MAIN_1)
	assert_eq(
		guest_snapshot.private_abilities.map(func(ability): return ability.copy_id),
		peer_two_snapshot.private_abilities.map(func(ability): return ability.copy_id)
	)
	assert_eq(runtime.submit_command("ready-host", {
		"command_id": "ready-host-command",
		"kind": "set_ready",
		"payload": {"ready": true},
	}), OK)
	assert_eq(results[-1].message_id, "ready-host")
	assert_true(results[-1].result.accepted)
	assert_eq(snapshots[-1].screen_id, "match")
	runtime.close()


func test_runtime_config_uses_recipe_with_all_four_ability_categories() -> void:
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
	var timing_counts := {}
	for definition in definitions:
		counts[definition.id] = int(counts.get(definition.id, 0)) + 1
		timing_counts[definition.timing] = int(timing_counts.get(definition.timing, 0)) + 1
	assert_eq(definitions.size(), 90)
	assert_eq(counts.size(), 54)
	assert_eq(timing_counts[AbilityDefinition.Timing.HAND_MANIPULATION], 45)
	assert_eq(timing_counts[AbilityDefinition.Timing.HAND_SHAPE], 18)
	assert_eq(timing_counts[AbilityDefinition.Timing.SABOTAGE], 12)
	assert_eq(timing_counts[AbilityDefinition.Timing.FIELD], 15)
	assert_false(definitions.any(func(definition):
		return str(definition.id).begins_with("placeholder_ability_")
	))
	var contexts: Array = runtime._controller.state.config.context_definitions
	var contexts_by_id := {}
	for definition in contexts:
		contexts_by_id[definition.id] = definition
	assert_eq(contexts.size(), 40)
	assert_eq(contexts_by_id.all_contexts_1.priority, 10)
	assert_eq(contexts_by_id.all_contexts_1.multiplier.numerator, 5)
	assert_eq(contexts_by_id.all_contexts_1.multiplier.denominator, 4)
	assert_eq(contexts_by_id.rise_12.priority, 160)
	assert_eq(contexts_by_id.rise_12.multiplier.numerator, 5)
	assert_eq(contexts_by_id.rise_12.multiplier.denominator, 1)
	assert_false(contexts.any(func(definition):
		return definition.multiplier.numerator == 1 and definition.multiplier.denominator == 1
	))
	runtime.close()


func test_host_recipe_updates_existing_deck_and_public_catalog_before_start() -> void:
	var transport := RuntimeTransport.new()
	var clock_value := [1000]
	var runtime = RuntimeGameSession.new(transport, func(): return clock_value[0])
	var snapshots: Array[Dictionary] = []
	runtime.snapshot_applied.connect(func(snapshot: Dictionary, _sequence: int):
		snapshots.append(snapshot)
	)
	assert_eq(runtime.start_host("ws://127.0.0.1:8080", "Mira"), OK)
	transport.lobby_created.emit("ABC234")
	assert_eq(snapshots[-1].get("ability_catalog", {}).size(), 54)
	var recipe := AbilityCatalog.provisional_deck_recipe()
	recipe[&"context_exchange"] = 1
	assert_eq(runtime.update_lobby_setting(&"ability_deck_recipe", recipe), &"")
	transport.join_status.emit("approved", {
		"peer_id": "peer-one", "role": "active", "display_name": "Noah",
	})
	transport.peer_connected.emit("peer-one")
	assert_eq(snapshots[-1].get("ability_catalog", {}).get("context_exchange", {}).get("copies"), 1)
	var previous_hand: Array = snapshots[-1].private_hand
	var previous_connection: Dictionary = snapshots[-1].get("private_connection", {})
	# A lobby can remain open past the round's Start timer while the host edits.
	_transport_heartbeat(transport, 1000)
	runtime.poll()
	for step in range(1, 5):
		clock_value[0] += 6000
		_transport_heartbeat(transport, clock_value[0])
		runtime.poll()
	assert_eq(runtime._controller.state.phase, GameTypes.Phase.START)
	transport.clear_sent()
	recipe[&"context_exchange"] = 0
	recipe[&"mirror_rank"] = 5
	assert_eq(runtime.update_lobby_setting(&"ability_deck_recipe", recipe), &"")
	var latest: Dictionary = snapshots[-1]
	assert_eq(latest.get("ability_catalog", {}).get("context_exchange", {}).get("copies"), 0)
	assert_eq(latest.get("ability_catalog", {}).get("mirror_rank", {}).get("copies"), 5)
	assert_eq(latest.private_hand, previous_hand)
	assert_eq(latest.get("private_connection", {}), previous_connection)
	var deck_cards: Array = runtime._controller.state.ability_deck.to_dict().cards
	assert_eq(deck_cards.size(), 89)
	assert_eq(deck_cards.filter(func(card): return card.definition.id == "context_exchange").size(), 0)
	assert_eq(deck_cards.filter(func(card): return card.definition.id == "mirror_rank").size(), 5)
	var guest_received_recipe := false
	for entry in transport.sent:
		var decoded := preload("res://src/network/game_protocol.gd").decode(entry.bytes)
		if decoded.envelope.get("kind") != "snapshot":
			continue
		var guest: Dictionary = decoded.envelope.payload.state
		assert_eq(guest.get("ability_catalog", {}), latest.get("ability_catalog", {}))
		assert_eq(guest.get("scoring_catalog", {}), latest.get("scoring_catalog", {}))
		guest_received_recipe = true
	assert_true(guest_received_recipe)

	assert_eq(runtime.update_lobby_setting(&"ability_deck_recipe", {"unrecognized": 2}), &"invalid_ability_deck_recipe")
	assert_eq(runtime.update_lobby_setting(&"ability_deck_recipe", {"mirror_rank": 2}), &"insufficient_ability_cards")
	assert_eq(runtime._controller.state.ability_deck.to_dict().cards, deck_cards)
	assert_eq(runtime.start_match(), OK)
	assert_eq(runtime.update_lobby_setting(&"ability_deck_recipe", recipe), &"config_locked")

	var guest_token: String = runtime._controller.state.players[&"peer-one"].reconnect_token
	runtime._controller.state.match_complete = true
	runtime._controller.state.phase = GameTypes.Phase.COMPLETE
	assert_eq(runtime.reset_for_rematch(), OK)
	assert_eq(snapshots[-1].screen_id, "lobby")
	assert_eq(snapshots[-1].get("ability_catalog", {}).get("mirror_rank", {}).get("copies"), 5)
	assert_eq(runtime._controller.state.players[&"peer-one"].reconnect_token, guest_token)
	assert_eq(runtime.start_match(), OK)
	assert_eq(snapshots[-1].phase, GameTypes.Phase.MAIN_1)
	assert_eq(snapshots[-1].private_abilities.size(), 2)
	runtime.close()


func _transport_heartbeat(transport: RuntimeTransport, timestamp: int) -> void:
	transport.inject_message("peer-one", preload("res://src/network/game_protocol.gd").encode({
		"v": 1, "kind": "heartbeat_ack", "message_id": "ack-%d" % timestamp,
		"match_id": "shift-match", "sender_id": "peer-one",
		"payload": {"timestamp_msec": timestamp},
	}))


func test_ability_catalog_projects_card_text_timing_schema_and_fixed_context() -> void:
	var definitions: Array = []
	for definition in AbilityCatalog.manipulation_definitions(1):
		definitions.append({
			"id": str(definition.id), "timing": definition.timing,
			"tags": definition.tags, "effect_id": str(definition.effect_id),
			"effect_parameters": definition.effect_parameters,
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
	assert_eq(catalog.context_exchange.context_emblem, -1)
	assert_eq(catalog.flourish_infusion.context_emblem, 1)


func test_join_runtime_uses_assigned_peer_id_for_authoritative_commands() -> void:
	var transport := RuntimeTransport.new()
	var runtime = RuntimeGameSession.new(transport, Callable(self, "_now"))
	assert_eq(runtime.start_join(
		"ws://127.0.0.1:8080", "abc234", "active", "Noah"
	), OK)
	assert_eq(runtime.update_lobby_setting(&"ability_deck_recipe", {"mirror_rank": 20}), &"host_only")
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
