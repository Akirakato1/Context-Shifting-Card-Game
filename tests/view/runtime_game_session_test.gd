extends "res://tests/test_case.gd"

const RuntimeGameSession = preload("res://src/view/app/runtime_game_session.gd")
const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const GameTypes = preload("res://src/core/common/game_types.gd")
const FakePeerTransport = preload("res://tests/network/fake_peer_transport.gd")
const GameProtocol = preload("res://src/network/game_protocol.gd")


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


func test_guest_ready_toggle_updates_both_lobbies_with_latest_choice() -> void:
	var host_transport := RuntimeTransport.new()
	var guest_transport := RuntimeTransport.new()
	var host := RuntimeGameSession.new(host_transport, Callable(self, "_now"))
	var store := ReconnectStore.new("user://runtime-ready-test-%d.json" % Time.get_ticks_usec())
	var guest := RuntimeGameSession.new(guest_transport, Callable(self, "_now"), store)
	var app_scene := preload("res://src/view/app/app_root.tscn")
	var host_app := app_scene.instantiate()
	var guest_app := app_scene.instantiate()
	Engine.get_main_loop().root.add_child(host_app)
	Engine.get_main_loop().root.add_child(guest_app)
	host_app.bind_session(host)
	guest_app.bind_session(guest)
	assert_eq(host.start_host("ws://127.0.0.1:8080", "Mira"), OK)
	host_transport.lobby_created.emit("ABC234")
	assert_eq(guest.start_join("ws://127.0.0.1:8080", "ABC234", "active", "Noah"), OK)
	var assignment := {"peer_id": "peer-one", "role": "active", "display_name": "Noah"}
	guest_transport.join_status.emit("approved", assignment)
	guest_transport.peer_connected.emit("host")
	host_transport.join_status.emit("approved", assignment)
	host_transport.peer_connected.emit("peer-one")
	_deliver(host_transport, guest_transport, "peer-one", "host")
	assert_eq(guest_app.current_screen_id(), &"lobby")
	assert_eq(host_app.presentation_state.private_state().get("lobby_unready_guests", -1), 1)
	assert_eq(host.start_match(), ERR_BUSY)
	assert_eq(host_app.current_screen_id(), &"lobby")
	var ready: CheckButton = guest_app.get_node_or_null("SafeArea/ScreenHost/LobbyScreen/Layout/Footer/ReadyButton")
	assert_true(ready != null)
	if ready != null:
		ready.button_pressed = true
		_deliver(guest_transport, host_transport, "host", "peer-one")
		_deliver(host_transport, guest_transport, "peer-one", "host")
		assert_true(host_app.presentation_state.private_state().players[1].ready)
		assert_true(guest_app.presentation_state.private_state().players[1].ready)
		assert_true(ready.button_pressed)

		ready.button_pressed = false
		ready.button_pressed = true
		for _pass in range(2):
			_deliver(guest_transport, host_transport, "host", "peer-one")
			_deliver(host_transport, guest_transport, "peer-one", "host")
		assert_true(host_app.presentation_state.private_state().players[1].ready)
		assert_true(guest_app.presentation_state.private_state().players[1].ready)
		assert_true(ready.button_pressed)

		ready.button_pressed = false
		_deliver(guest_transport, host_transport, "host", "peer-one")
		_deliver(host_transport, guest_transport, "peer-one", "host")
		assert_false(host_app.presentation_state.private_state().players[1].ready)
		assert_false(guest_app.presentation_state.private_state().players[1].ready)
		assert_false(ready.button_pressed)
		assert_eq(host.start_match(), ERR_BUSY)
		ready.button_pressed = true
		_deliver(guest_transport, host_transport, "host", "peer-one")
		_deliver(host_transport, guest_transport, "peer-one", "host")
		assert_eq(host_app.presentation_state.private_state().get("lobby_unready_guests", -1), 0)
		assert_eq(host.start_match(), OK)
		_deliver(guest_transport, host_transport, "host", "peer-one")
		_deliver(host_transport, guest_transport, "peer-one", "host")
		assert_false(host_app.presentation_state.private_state().players[1].ready)
		assert_false(guest_app.presentation_state.private_state().players[1].ready)

	host.close()
	guest.close()
	store.clear()
	host_app.queue_free()
	guest_app.queue_free()
	await Engine.get_main_loop().process_frame


func test_guest_disconnect_before_start_frees_seat_without_finishing_match() -> void:
	var transport := RuntimeTransport.new()
	var runtime := RuntimeGameSession.new(transport, Callable(self, "_now"))
	var snapshots: Array[Dictionary] = []
	runtime.snapshot_applied.connect(func(snapshot: Dictionary, _sequence: int): snapshots.append(snapshot))
	assert_eq(runtime.start_host("ws://127.0.0.1:8080", "Mira"), OK)
	transport.lobby_created.emit("ABC234")
	_connect_peer(transport, "peer-one", "active")
	transport.close_with_reason("peer-one", "connection_closed")
	assert_eq(snapshots[-1].screen_id, "lobby")
	assert_eq(snapshots[-1].active_player_count, 1)
	assert_eq(snapshots[-1].players.size(), 1)
	assert_false(snapshots[-1].frozen)
	assert_false(snapshots[-1].match_complete)
	assert_eq(runtime.start_match(), ERR_UNAVAILABLE)
	_connect_peer(transport, "peer-two", "active")
	_ready_lobby_guests(runtime)
	assert_eq(runtime.start_match(), OK)
	assert_eq(snapshots[-1].phase, GameTypes.Phase.MAIN_1)
	runtime.close()


func test_last_guest_grace_expiry_awards_host_victory_with_spectator_and_pending_player() -> void:
	var time := [1000]
	var transport := RuntimeTransport.new()
	var runtime := RuntimeGameSession.new(transport, func(): return time[0])
	var snapshots: Array[Dictionary] = []
	var events: Array = []
	runtime.snapshot_applied.connect(func(snapshot: Dictionary, _sequence: int): snapshots.append(snapshot))
	runtime.events_applied.connect(func(batch: Array, _sequence: int): events.append_array(batch))
	assert_eq(runtime.start_host("ws://127.0.0.1:8080", "Mira"), OK)
	transport.lobby_created.emit("ABC234")
	assert_eq(runtime.update_lobby_setting(&"reconnect_grace_msec", 200), &"")
	_connect_peer(transport, "peer-one", "active")
	_ready_lobby_guests(runtime)
	assert_eq(runtime.start_match(), OK)
	_connect_peer(transport, "peer-pending", "active")
	_connect_peer(transport, "peer-watch", "spectator")
	transport.close_with_reason("peer-one", "connection_closed")
	time[0] = 1199
	runtime.poll()
	assert_true(snapshots[-1].frozen)
	assert_false(snapshots[-1].match_complete)

	time[0] = 1200
	runtime.poll()
	var result := snapshots[-1]
	assert_eq(result.phase, GameTypes.Phase.COMPLETE)
	assert_true(result.match_complete)
	assert_false(result.frozen)
	assert_eq(result.winner_id, "host")
	assert_eq(result.get("end_reason", ""), "last_player_standing")
	assert_eq(events.filter(func(event): return event.kind == "match_ended").size(), 1)
	var spectator := _last_snapshot(transport, "peer-watch")
	assert_eq(spectator.winner_id, "host")
	assert_eq(spectator.get("end_reason", ""), "last_player_standing")
	assert_false(spectator.has("private_hand"))
	assert_eq(runtime.reset_for_rematch(), OK)
	assert_eq(snapshots[-1].screen_id, "lobby")
	assert_eq(snapshots[-1].active_player_count, 2)
	runtime.close()


func test_confirmed_guest_leave_forfeits_immediately_and_host_can_reopen_lobby() -> void:
	var host_transport := RuntimeTransport.new()
	var guest_transport := RuntimeTransport.new()
	var host := RuntimeGameSession.new(host_transport, Callable(self, "_now"))
	var store := ReconnectStore.new("user://runtime-leave-test-%d.json" % Time.get_ticks_usec())
	var guest := RuntimeGameSession.new(guest_transport, Callable(self, "_now"), store)
	var guest_app := preload("res://src/view/app/app_root.tscn").instantiate()
	Engine.get_main_loop().root.add_child(guest_app)
	guest_app.bind_session(guest)
	var host_snapshots: Array[Dictionary] = []
	host.snapshot_applied.connect(func(snapshot: Dictionary, _sequence: int): host_snapshots.append(snapshot))
	assert_eq(host.start_host("ws://127.0.0.1:8080", "Mira"), OK)
	host_transport.lobby_created.emit("ABC234")
	assert_eq(guest.start_join("ws://127.0.0.1:8080", "ABC234", "active", "Noah"), OK)
	guest_transport.join_status.emit("approved", {"peer_id": "peer-one", "role": "active"})
	guest_transport.peer_connected.emit("host")
	_connect_peer(host_transport, "peer-one", "active")
	_ready_lobby_guests(host)
	assert_eq(host.start_match(), OK)
	_deliver(host_transport, guest_transport, "peer-one", "host")
	assert_eq(guest_app.current_screen_id(), &"match")
	assert_false(store.load_record(_now()).is_empty())
	guest_app.get_node("SafeArea/ScreenHost").get_child(0).get_node("ConfirmLeave").confirmed.emit()
	assert_eq(guest_app.current_screen_id(), &"match")
	assert_false(host_snapshots[-1].match_complete)
	_deliver(guest_transport, host_transport, "host", "peer-one")
	_deliver(host_transport, guest_transport, "peer-one", "host")
	await Engine.get_main_loop().process_frame
	assert_eq(guest_app.current_screen_id(), &"menu")
	assert_true(store.load_record(_now()).is_empty())
	assert_eq(host_snapshots[-1].winner_id, "host")
	assert_eq(host_snapshots[-1].get("end_reason", ""), "last_player_standing")
	assert_false(host_snapshots[-1].frozen)
	assert_eq(host.start_rematch(), ERR_UNAVAILABLE)
	assert_eq(host.reset_for_rematch(), OK)
	assert_eq(host_snapshots[-1].screen_id, "lobby")
	assert_eq(host_snapshots[-1].active_player_count, 1)
	_connect_peer(host_transport, "peer-two", "active")
	_ready_lobby_guests(host)
	assert_eq(host.start_match(), OK)
	host.close()
	guest.close()
	store.clear()
	guest_app.queue_free()
	await Engine.get_main_loop().process_frame


func _ready_lobby_guests(runtime: RuntimeGameSession) -> void:
	var controller := runtime._controller as MatchController
	for player_id: StringName in controller.state.seat_order:
		if player_id != &"host":
			assert_true(controller.submit(GameCommand.new(
				&"ready-for-start", player_id, &"set_lobby_ready", {"ready": true}
			), _now()).accepted)


func _deliver(from: RuntimeTransport, to: RuntimeTransport, recipient: String, sender: String) -> void:
	var packets := from.sent.duplicate()
	from.clear_sent()
	for packet in packets:
		if packet.peer_id == recipient:
			to.inject_message(sender, packet.bytes)


func _connect_peer(transport: RuntimeTransport, id: String, role: String) -> void:
	transport.join_status.emit("approved", {"peer_id": id, "role": role, "display_name": id})
	transport.peer_connected.emit(id)


func _last_snapshot(transport: RuntimeTransport, peer_id: String) -> Dictionary:
	for index in range(transport.sent.size() - 1, -1, -1):
		var packet := transport.sent[index]
		if packet.peer_id == peer_id:
			var decoded := GameProtocol.decode(packet.bytes)
			if decoded.ok and decoded.envelope.kind == "snapshot":
				return decoded.envelope.payload.state
	return {}


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
	assert_eq(joined.private_abilities.size(), 3)
	assert_true(transport.sent.any(func(entry):
		return entry.peer_id == "peer-one"
	))
	for _index in range(3):
		runtime.poll()
	assert_false(runtime._controller.state.config.match_started)
	assert_eq(runtime._controller.state.phase, GameTypes.Phase.START)
	assert_eq(runtime._controller.state.players[&"host"].ability_hand.size(), 3)
	assert_eq(runtime.submit_command("lobby-ready", {
		"command_id": "lobby-ready-command",
		"kind": "set_ready",
		"payload": {"ready": true},
	}), OK)
	assert_true(results[-1].result.accepted)
	assert_false(runtime._controller.state.config.match_started)
	assert_eq(runtime._controller.state.phase, GameTypes.Phase.START)
	assert_eq(runtime._controller.state.players[&"host"].ability_hand.size(), 3)

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
	assert_eq(peer_two_snapshot.private_abilities.size(), 3)
	var failures: Array[String] = []
	runtime.session_failed.connect(func(reason: String): failures.append(reason))
	transport.transport_failed.emit("signaling_closed")
	assert_eq(transport.signaling_reconnects, 1)
	assert_true(failures.is_empty())

	var opening_abilities: Array = snapshots[-1].private_abilities.map(func(ability): return ability.copy_id)
	transport.clear_sent()
	_ready_lobby_guests(runtime)
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
	assert_eq(snapshots[-1].private_hand.size(), 6)
	assert_eq(snapshots[-1].private_abilities.size(), 3)
	assert_eq(runtime.start_match(), ERR_ALREADY_IN_USE)
	assert_eq(runtime.submit_command("invalid-start-request", {
		"command_id": "invalid-start-request-command",
		"kind": "set_replenishment_request",
		"payload": {"request": {0: 2}},
	}), OK)
	assert_false(results[-1].result.accepted)
	assert_eq(results[-1].result.error_code, "command_not_allowed_in_phase")
	assert_eq(runtime.submit_command("ready-host", {
		"command_id": "ready-host-command",
		"kind": "set_ready",
		"payload": {"ready": true},
	}), OK)
	assert_eq(results[-1].message_id, "ready-host")
	assert_true(results[-1].result.accepted)
	assert_eq(snapshots[-1].screen_id, "match")
	runtime.close()


func test_host_switches_victory_defaults_and_starts_an_untimed_match() -> void:
	var transport := RuntimeTransport.new()
	var runtime = RuntimeGameSession.new(transport, Callable(self, "_now"))
	var snapshots: Array[Dictionary] = []
	runtime.snapshot_applied.connect(func(snapshot: Dictionary, _sequence: int):
		snapshots.append(snapshot)
	)
	assert_eq(runtime.start_host("ws://127.0.0.1:8080", "Mira"), OK)
	transport.lobby_created.emit("ABC234")
	assert_eq(snapshots[-1].settings.victory_target, 1_000)
	assert_false(snapshots[-1].settings.has("base_score_mode"))
	assert_eq(runtime.update_lobby_setting(&"base_score_mode", 1), &"invalid_setting")
	assert_eq(runtime.update_lobby_setting(&"victory_mode", GameTypes.VictoryMode.ROUND_WIN_RACE), &"")
	assert_eq(snapshots[-1].settings.victory_target, 10)
	assert_eq(runtime.update_lobby_setting(&"victory_target", 7), &"")
	assert_eq(runtime.update_lobby_setting(&"victory_mode", GameTypes.VictoryMode.ROUND_WIN_RACE), &"")
	assert_eq(snapshots[-1].settings.victory_target, 7)
	assert_eq(runtime.update_lobby_setting(&"no_time_limit", true), &"")

	transport.join_status.emit("approved", {
		"peer_id": "peer-one", "role": "active", "display_name": "Noah",
	})
	transport.peer_connected.emit("peer-one")
	assert_eq(runtime.update_lobby_setting(&"victory_mode", GameTypes.VictoryMode.SCORE_RACE), &"")
	assert_eq(snapshots[-1].settings.victory_target, 1_000)
	assert_eq(runtime.update_lobby_setting(&"no_time_limit", false), &"")
	assert_eq(runtime.update_lobby_setting(&"hand_timer_msec", 65_000), &"")
	assert_eq(runtime.update_lobby_setting(&"no_time_limit", true), &"")
	assert_true(snapshots[-1].settings.get("no_time_limit", false))
	assert_eq(snapshots[-1].settings.hand_timer_msec, 65_000)
	var guest_snapshot: Dictionary = GameProtocol.decode(transport.sent[-1].bytes).envelope.payload.state
	assert_true(guest_snapshot.settings.get("no_time_limit", false))
	assert_eq(guest_snapshot.settings.victory_target, 1_000)
	assert_false(guest_snapshot.settings.has("base_score_mode"))
	_ready_lobby_guests(runtime)
	assert_eq(runtime.start_match(), OK)
	var state: MatchState = runtime._controller.state
	var saved_config := state.config.to_dict()
	assert_true(MatchConfig.from_dict(saved_config).no_time_limit)
	saved_config.erase("no_time_limit")
	assert_false(MatchConfig.from_dict(saved_config).no_time_limit)
	assert_eq(state.phase_deadline_msec, -1)
	var late := _now() + 500_000
	runtime._controller.tick(late)
	assert_eq(state.phase, GameTypes.Phase.MAIN_1)
	for player_id in state.seat_order:
		var ready := GameCommand.new(&"ready-untimed", player_id, &"set_ready", {"ready": true})
		assert_true(runtime._controller.submit(ready, late).accepted)
	assert_eq(state.phase, GameTypes.Phase.HAND_PLAY)
	assert_eq(state.phase_deadline_msec, -1)
	assert_eq(runtime.update_lobby_setting(&"no_time_limit", false), &"config_locked")
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
	assert_eq(definitions.size(), 98)
	assert_eq(counts.size(), 50)
	assert_eq(timing_counts[AbilityDefinition.Timing.HAND_MANIPULATION], 60)
	assert_eq(timing_counts[AbilityDefinition.Timing.HAND_SHAPE], 8)
	assert_eq(timing_counts[AbilityDefinition.Timing.SABOTAGE], 13)
	assert_eq(timing_counts[AbilityDefinition.Timing.FIELD], 17)
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
	assert_eq(contexts_by_id.rise_12.priority, 101)
	assert_eq(contexts_by_id.rise_12.multiplier.numerator, 11)
	assert_eq(contexts_by_id.rise_12.multiplier.denominator, 4)
	assert_eq(contexts.filter(func(definition):
		return definition.multiplier.numerator == 1 and definition.multiplier.denominator == 1
	).size(), 3)
	var normals: Array = runtime._controller.state.config.normal_definitions
	var normals_by_id := {}
	var normal_categories := {}
	for definition in normals:
		normals_by_id[definition.id] = definition
		normal_categories[definition.broad_category_id] = true
	assert_eq(normals.size(), 18)
	assert_eq(normal_categories.keys().size(), 5)
	assert_eq(normals_by_id.pair.priority, 20)
	assert_eq(normals_by_id.pair.multiplier.numerator, 5)
	assert_eq(normals_by_id.pair.multiplier.denominator, 4)
	assert_eq(normals_by_id.four_house.rule_parameters.group_sizes, [4, 2])
	assert_eq(normals_by_id.six_kind.priority, 190)
	assert_eq(normals_by_id.six_kind.multiplier.numerator, 6)
	assert_eq(normals_by_id.six_kind.multiplier.denominator, 1)
	assert_false(normals.all(func(definition):
		return definition.multiplier.numerator == 1 and definition.multiplier.denominator == 1
	))
	runtime.close()


func test_runtime_end_discard_uses_owner_choices_and_rejects_wrong_count() -> void:
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
	transport.lobby_created.emit("ABC234")
	transport.join_status.emit("approved", {
		"peer_id": "peer-one", "role": "active", "display_name": "Noah",
	})
	transport.peer_connected.emit("peer-one")
	_ready_lobby_guests(runtime)
	assert_eq(runtime.start_match(), OK)

	var state = runtime._controller.state
	var host = state.players[&"host"]
	host.ability_hand.append_array(state.ability_deck.draw(&"host", 2, state.rng))
	state.ability_deck.discard(state.players[&"peer-one"].ability_hand.pop_back())
	state.phase = GameTypes.Phase.MAIN_2
	state.phase_started_msec = 1000
	state.phase_deadline_msec = 6000
	state.reaction_deadline_msec = 1000
	host.ready = true
	state.players[&"peer-one"].ready = true
	var end_events: Array = runtime._controller.tick(1000)
	runtime._host_session.publish_state_change(end_events)

	assert_eq(snapshots[-1].phase, GameTypes.Phase.END)
	assert_eq(snapshots[-1].private_abilities.size(), 5)
	assert_eq(snapshots[-1].required_ability_discards, 3)
	var chosen_ids := [
		str(host.ability_hand[0].copy_id), str(host.ability_hand[1].copy_id),
		str(host.ability_hand[2].copy_id),
	]
	assert_eq(runtime.submit_command("wrong-end-discard", {
		"command_id": "wrong-end-discard-command",
		"kind": "choose_ability_discards",
		"payload": {"copy_ids": [chosen_ids[0]]},
	}), OK)
	assert_false(results[-1].result.accepted)
	assert_eq(results[-1].result.error_code, "incorrect_discard_count")
	assert_eq(host.ability_hand.size(), 5)

	assert_eq(runtime.submit_command("chosen-end-discard", {
		"command_id": "chosen-end-discard-command",
		"kind": "choose_ability_discards",
		"payload": {"copy_ids": chosen_ids},
	}), OK)
	assert_true(results[-1].result.accepted)
	assert_eq(host.ability_hand.size(), 2)
	for copy_id in chosen_ids:
		assert_false(host.ability_hand.any(func(ability):
			return str(ability.copy_id) == copy_id
		))
	assert_eq(snapshots[-1].phase, GameTypes.Phase.START)
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
	assert_eq(snapshots[-1].get("ability_catalog", {}).size(), 60)
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
	recipe[&"even_rank_favor"] = 1
	assert_eq(runtime.update_lobby_setting(&"ability_deck_recipe", recipe), &"")
	var latest: Dictionary = snapshots[-1]
	assert_eq(latest.get("ability_catalog", {}).get("context_exchange", {}).get("copies"), 0)
	assert_eq(latest.get("ability_catalog", {}).get("mirror_rank", {}).get("copies"), 5)
	assert_eq(latest.get("ability_catalog", {}).get("even_rank_favor", {}).get("copies"), 1)
	assert_eq(latest.private_hand, previous_hand)
	assert_eq(latest.get("private_connection", {}), previous_connection)
	var deck_cards: Array = runtime._controller.state.ability_deck.to_dict().cards
	assert_eq(deck_cards.size(), 96)
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
	_ready_lobby_guests(runtime)
	assert_eq(runtime.start_match(), OK)
	assert_eq(runtime.update_lobby_setting(&"ability_deck_recipe", recipe), &"config_locked")

	var guest_token: String = runtime._controller.state.players[&"peer-one"].reconnect_token
	runtime._controller.state.match_complete = true
	runtime._controller.state.phase = GameTypes.Phase.COMPLETE
	assert_eq(runtime.reset_for_rematch(), OK)
	assert_eq(snapshots[-1].screen_id, "lobby")
	assert_eq(snapshots[-1].get("ability_catalog", {}).get("mirror_rank", {}).get("copies"), 5)
	assert_eq(runtime._controller.state.players[&"peer-one"].reconnect_token, guest_token)
	_ready_lobby_guests(runtime)
	assert_eq(runtime.start_match(), OK)
	assert_eq(snapshots[-1].phase, GameTypes.Phase.MAIN_1)
	assert_eq(snapshots[-1].private_abilities.size(), 3)
	runtime.close()


func test_results_rematch_starts_fresh_round_in_the_same_room() -> void:
	var app = preload("res://src/view/app/app_root.tscn").instantiate()
	Engine.get_main_loop().root.add_child(app)
	var transport := RuntimeTransport.new()
	var runtime := RuntimeGameSession.new(transport, Callable(self, "_now"))
	app.bind_session(runtime)
	assert_eq(runtime.start_host("ws://127.0.0.1:8080", "Mira"), OK)
	transport.lobby_created.emit("ABC234")
	transport.join_status.emit("approved", {
		"peer_id": "peer-one", "role": "active", "display_name": "Noah",
	})
	transport.peer_connected.emit("peer-one")
	assert_eq(runtime.update_lobby_setting(&"victory_target", 25), &"")
	_ready_lobby_guests(runtime)
	assert_eq(runtime.start_match(), OK)
	transport.join_status.emit("approved", {
		"peer_id": "peer-late", "role": "active", "display_name": "Ren",
	})
	transport.peer_connected.emit("peer-late")
	transport.join_status.emit("approved", {
		"peer_id": "peer-watch", "role": "spectator", "display_name": "Iris",
	})
	transport.peer_connected.emit("peer-watch")
	var completed: MatchState = runtime._controller.state
	assert_true(completed.players[&"peer-late"].pending)
	var guest_token: String = completed.players[&"peer-one"].reconnect_token
	completed.round_number = 4
	completed.players[&"host"].match_score = 25
	completed.players[&"host"].round_wins = 1
	completed.match_complete = true
	completed.winner_id = &"host"
	completed.phase = GameTypes.Phase.COMPLETE
	runtime._host_session.publish_state_change([])
	assert_eq(app.current_screen_id(), &"results")
	var screens: Array[String] = []
	runtime.snapshot_applied.connect(func(snapshot: Dictionary, _sequence: int):
		screens.append(snapshot.screen_id)
	)
	transport.clear_sent()
	app.get_node("SafeArea/ScreenHost").get_child(0).get_node("Layout/Actions/RematchButton").pressed.emit()

	assert_eq(app.current_screen_id(), &"match")
	assert_eq(screens, ["match"])
	var snapshot: Dictionary = app.presentation_state.private_state()
	assert_eq(snapshot.phase, GameTypes.Phase.MAIN_1)
	assert_eq(snapshot.round_number, 1)
	assert_false(snapshot.match_complete)
	assert_eq(snapshot.winner_id, "")
	assert_eq(snapshot.room_code, "ABC234")
	assert_eq(snapshot.settings.victory_target, 25)
	assert_eq(snapshot.players.map(func(player): return player.name), ["Mira", "Noah", "Ren", "Iris"])
	assert_true(snapshot.players.all(func(player): return player.match_score == 0 and player.round_wins == 0))
	assert_eq(runtime.update_lobby_setting(&"victory_target", 30), &"config_locked")

	var peer_snapshots := {}
	for entry in transport.sent:
		var envelope: Dictionary = GameProtocol.decode(entry.bytes).envelope
		if envelope.kind != "snapshot":
			continue
		var projected: Dictionary = envelope.payload.state
		assert_eq(projected.phase, GameTypes.Phase.MAIN_1)
		assert_eq(projected.room_code, "ABC234")
		peer_snapshots[entry.peer_id] = projected
	assert_eq(peer_snapshots.size(), 3)
	assert_eq(peer_snapshots.get("peer-one", {}).get("private_connection", {}).get("reconnect_token"), guest_token)
	assert_eq(peer_snapshots.get("peer-late", {}).get("private_player_id"), "peer-late")
	assert_eq(peer_snapshots.get("peer-late", {}).get("private_hand", []).size(), 6)
	assert_eq(peer_snapshots.get("peer-watch", {}).get("local_role"), "spectator")
	assert_false(peer_snapshots.get("peer-watch", {}).has("private_hand"))
	runtime.close()
	app.queue_free()
	await Engine.get_main_loop().process_frame


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

	assert_eq(catalog.size(), 17)
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
		"kind": "set_lobby_ready",
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
	first.peer_disconnected.emit("host", "connection_lost")
	assert_eq(runtime.retry_connection(), OK)
	assert_eq(runtime.retry_connection(), ERR_BUSY)
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
