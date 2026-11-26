extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")
const DomainEvent = preload("res://src/core/events/domain_event.gd")
const GameProtocol = preload("res://src/network/game_protocol.gd")
const HostNetworkSession = preload("res://src/network/host_network_session.gd")
const FakePeerTransport = preload("res://tests/network/fake_peer_transport.gd")

var _now_msec := 1000


func before_each() -> void:
	_now_msec = 1000


func test_admission_enforces_capacity_role_lock_and_pending_public_only_snapshot() -> void:
	var full_active := _session([&"one", &"two", &"three", &"four"], [])
	assert_eq(
		full_active.host.admit_peer("peer-five", &"five", "active").error_code,
		"active_seats_full"
	)
	var full_spectators := _session([&"one", &"two"], [&"s1", &"s2", &"s3", &"s4"])
	assert_eq(
		full_spectators.host.admit_peer("peer-s5", &"s5", "spectator").error_code,
		"spectator_slots_full"
	)

	var fixture := _session([&"one", &"two"], [])
	fixture.host.register_peer("peer-one", &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	var admitted: Dictionary = fixture.host.admit_peer("peer-late", &"late", "active")
	assert_true(admitted.accepted)
	assert_eq(fixture.state.players[&"late"].pending, true)
	assert_eq(
		fixture.host.admit_peer("peer-late", &"late", "spectator").error_code,
		"role_change_not_allowed"
	)
	var pending_snapshot := _last_kind(fixture.transport, "peer-late", "snapshot")
	assert_false(pending_snapshot.payload.state.has("private_hand"))
	assert_false(pending_snapshot.payload.state.has("private_abilities"))
	assert_true(_player_view(pending_snapshot.payload.state, "late").pending)
	assert_true(pending_snapshot.payload.state.lobby_settings.match_started)

	fixture.host.send_snapshot("peer-one")
	var existing_snapshot := _last_kind(fixture.transport, "peer-one", "snapshot")
	assert_eq(
		existing_snapshot.payload.state.lobby_settings,
		pending_snapshot.payload.state.lobby_settings
	)


func test_command_driven_next_start_promotes_pending_player_and_sends_owner_snapshot() -> void:
	var fixture := _session([&"one", &"two"], [])
	fixture.host.register_peer("peer-one", &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	fixture.host.register_peer("peer-two", &"two", GameTypes.RecipientRole.ACTIVE_PLAYER)
	assert_true(fixture.host.admit_peer("peer-late", &"late", "active").accepted)
	fixture.transport.clear_sent()

	fixture.state.phase = GameTypes.Phase.END
	fixture.state.ability_deck.discard(fixture.state.players[&"one"].ability_hand.pop_back())
	fixture.state.players[&"one"].end_discard_complete = true
	fixture.state.players[&"two"].end_discard_complete = false
	var discard_id := str(fixture.state.players[&"two"].ability_hand[0].copy_id)
	fixture.transport.inject_message("peer-two", GameProtocol.encode(_peer_envelope(
		"command", "finish-end-message", "two", {
			"command_id": "finish-end-command",
			"player_id": "two",
			"kind": "choose_ability_discards",
			"payload": {"copy_ids": [discard_id]},
		}
	)))

	var owner_snapshot := _last_kind(fixture.transport, "peer-late", "snapshot")
	assert_eq(owner_snapshot.payload.state.private_player_id, "late")
	assert_eq(owner_snapshot.payload.state.private_hand.size(), 6)
	assert_eq(owner_snapshot.payload.state.private_abilities.size(), 2)
	var other_payloads := _all_payload_text(fixture.transport, "peer-one")
	assert_false(other_payloads.contains(owner_snapshot.payload.state.private_hand[0].card_id))
	assert_false(other_payloads.contains(owner_snapshot.payload.state.private_abilities[0].copy_id))
	assert_true(_event_kinds(fixture.transport, "peer-one").has("player_activated"))


func test_timer_driven_next_start_promotes_pending_player_and_sends_owner_snapshot() -> void:
	var fixture := _session([&"one", &"two"], [])
	fixture.host.register_peer("peer-one", &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	fixture.host.register_peer("peer-two", &"two", GameTypes.RecipientRole.ACTIVE_PLAYER)
	assert_true(fixture.host.admit_peer("peer-late", &"late", "active").accepted)
	fixture.transport.clear_sent()

	fixture.state.phase = GameTypes.Phase.END
	fixture.state.phase_started_msec = 0
	fixture.state.phase_deadline_msec = _now_msec
	fixture.host.poll()

	var owner_snapshot := _last_kind(fixture.transport, "peer-late", "snapshot")
	assert_eq(owner_snapshot.payload.state.private_player_id, "late")
	assert_eq(owner_snapshot.payload.state.private_hand.size(), 6)
	assert_eq(owner_snapshot.payload.state.private_abilities.size(), 2)
	assert_true(_event_kinds(fixture.transport, "peer-one").has("player_activated"))


func test_disconnected_transient_participants_release_their_slots() -> void:
	var fixture := _session([&"one", &"two"], [])
	for index in range(4):
		var peer_id := "peer-watch-%d" % index
		var player_id := StringName("watch-%d" % index)
		assert_true(fixture.host.admit_peer(peer_id, player_id, "spectator").accepted)
		fixture.transport.close_with_reason(peer_id, "left_lobby")
		assert_false(fixture.state.players.has(player_id))
	assert_true(fixture.host.admit_peer("peer-replacement", &"replacement", "spectator").accepted)

	assert_true(fixture.host.admit_peer("peer-late", &"late", "active").accepted)
	fixture.transport.close_with_reason("peer-late", "left_lobby")
	assert_false(fixture.state.players.has(&"late"))
	assert_true(fixture.host.admit_peer("peer-late-2", &"late-2", "active").accepted)


func test_mid_phase_spectator_gets_public_snapshot_and_never_private_or_ready() -> void:
	var fixture := _session([&"one", &"two"], [])
	fixture.state.phase = GameTypes.Phase.MAIN_1
	fixture.host.register_peer("peer-one", &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	assert_true(fixture.host.admit_peer("peer-watch", &"watch", "spectator").accepted)
	var snapshot := _last_kind(fixture.transport, "peer-watch", "snapshot")
	assert_eq(snapshot.payload.state.phase, GameTypes.Phase.MAIN_1)
	assert_false(snapshot.payload.state.has("private_hand"))
	assert_false(snapshot.payload.state.has("private_abilities"))
	assert_eq(snapshot.payload.state.players[0].get("spectator_hand", []).size(), 6)
	assert_false(JSON.stringify(snapshot.payload.state.players[0]).contains(
		str(fixture.state.players[&"one"].hand[0].card_id)
	))
	assert_true(fixture.state.players[&"watch"].spectator)
	assert_false(fixture.state.players[&"watch"].active)

	fixture.transport.clear_sent()
	fixture.host.publish_events([
		DomainEvent.new(&"public_update", {"visible": true}, &"public"),
		DomainEvent.new(&"private_update", {"secret": true}, &"player", &"one"),
	])
	assert_eq(_event_kinds(fixture.transport, "peer-watch"), ["public_update"])


func test_spectator_receives_sanitized_view_updates_only_from_the_owning_player() -> void:
	var fixture := _session([&"one", &"two"], [])
	fixture.state.phase = GameTypes.Phase.HAND_PLAY
	fixture.host.register_peer("peer-one", &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	fixture.host.register_peer("peer-two", &"two", GameTypes.RecipientRole.ACTIVE_PLAYER)
	assert_true(fixture.host.admit_peer("peer-watch", &"watch", "spectator").accepted)
	var watched: Dictionary = _last_kind(fixture.transport, "peer-watch", "snapshot").payload.state
	var view: Dictionary = _player_view(watched, "one")
	assert_eq(view.get("spectator_abilities", []).size(), fixture.state.players[&"one"].ability_hand.size())
	var original := str(fixture.state.players[&"one"].hand[0].card_id)
	var alias := str(view.spectator_hand[0].view_id)
	var body := {
		"round_number": fixture.state.round_number, "phase": GameTypes.Phase.HAND_PLAY,
		"hand_order": [original, "unknown-card"], "flipped": [original],
		"staged": [{"card_id": original, "half_index": 1, "joker_choices": []}],
	}
	var update := GameProtocol.encode(_peer_envelope("view_update", "look-1", "one", body))
	assert_false(update.is_empty(), "Live spectator views have their own wire message")
	if update.is_empty():
		return
	fixture.transport.clear_sent()
	fixture.transport.inject_message("peer-one", update)
	fixture.host.poll()
	var message := _last_kind(fixture.transport, "peer-watch", "view_update")
	if not message.is_empty():
		var watched_update: Dictionary = message.payload.views.one
		assert_eq(watched_update.hand_order, [alias])
		assert_eq(watched_update.flipped, [alias])
		assert_eq(watched_update.staged[0].view_id, alias)
		assert_false(JSON.stringify(watched_update).contains(original))
	assert_false(_received_view_update(fixture.transport, "peer-two"))
	fixture.transport.clear_sent()
	fixture.transport.inject_message("peer-watch", GameProtocol.encode(_peer_envelope("view_update", "looks-false", "watch", body)))
	fixture.host.poll()
	assert_false(_received_view_update(fixture.transport, "peer-watch"))

	fixture.transport.clear_sent()
	assert_true(fixture.host.admit_peer("peer-late", &"late", "spectator").accepted)
	var late: Dictionary = _last_kind(fixture.transport, "peer-late", "snapshot").payload.state
	assert_eq(late.spectator_views.one.hand_order, [alias])


func test_spectator_gets_viewpoint_tagged_sabotage_and_bystanders_keep_public_cue() -> void:
	var fixture := _session([&"one", &"two", &"three"], [])
	for id in ["one", "two", "three"]:
		fixture.host.register_peer("peer-" + id, StringName(id), GameTypes.RecipientRole.ACTIVE_PLAYER)
	assert_true(fixture.host.admit_peer("peer-watch", &"watch", "spectator").accepted)
	fixture.transport.clear_sent()
	var common := {"ability_id": "rank_blackout", "source_player_id": "one", "target_player_id": "two"}
	var card_id := str(fixture.state.players[&"two"].hand[0].card_id)
	fixture.host.publish_events([
		DomainEvent.new(&"sabotage_resolved", common),
		DomainEvent.new(&"sabotage_resolved", common.merged({"success": true}), &"player", &"one"),
		DomainEvent.new(&"sabotage_resolved", common.merged({
			"card_changes": [{"card_id": card_id, "before": {"first": {"effective_rank": 2}},
				"after": {"first": {"effective_rank": 9}}}],
			"request": "owner-only metadata",
		}), &"player", &"two"),
	])
	var watched: Array = _last_kind(fixture.transport, "peer-watch", "event_batch").payload.events
	assert_eq(watched.size(), 3)
	assert_eq(watched[1].observed_player_id, "one")
	assert_eq(watched[2].observed_player_id, "two")
	assert_eq(watched[2].payload.card_changes[0].after.first.effective_rank, 9)
	assert_false(JSON.stringify(watched).contains(card_id))
	assert_false(JSON.stringify(watched).contains("owner-only metadata"))
	var bystander: Array = _last_kind(fixture.transport, "peer-three", "event_batch").payload.events
	assert_eq(bystander.size(), 1)
	assert_eq(bystander[0].payload, common)


func test_late_spectator_and_active_resync_receive_same_authoritative_public_history() -> void:
	var fixture := _session([&"one", &"two"], [])
	fixture.state.record_public_events([
		DomainEvent.new(&"public_update", {"ability_id": "safe"}, &"public"),
		DomainEvent.new(&"private_update", {"card_id": "secret"}, &"player", &"two"),
	])
	fixture.host.register_peer("peer-one", &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	assert_true(fixture.host.admit_peer("peer-watch", &"watch", "spectator").accepted)
	fixture.host.send_snapshot("peer-one")
	var active: Dictionary = _last_kind(fixture.transport, "peer-one", "snapshot").payload.state
	var spectator: Dictionary = _last_kind(fixture.transport, "peer-watch", "snapshot").payload.state
	assert_eq(active.public_history, spectator.public_history)
	assert_eq(active.public_history.size(), 1)
	assert_false(JSON.stringify(spectator.public_history).contains("secret"))


func test_owner_resync_keeps_joker_choices_private() -> void:
	var fixture := _session([&"one", &"two"], [&"watcher"])
	fixture.state.active_context = GameTypes.Context.FALL
	fixture.host.register_peer("peer-one", &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	fixture.host.register_peer("peer-two", &"two", GameTypes.RecipientRole.ACTIVE_PLAYER)
	fixture.host.register_peer("peer-watch", &"watcher", GameTypes.RecipientRole.SPECTATOR)
	var joker := FullCardState.new(
		&"resync-joker-card",
		HalfCardState.new(
			&"resync-joker-half", GameTypes.Context.FLOURISH, 0, HalfCardState.NO_SUIT,
			GameTypes.HalfKind.JOKER
		),
		HalfCardState.new(
			&"resync-normal-half", GameTypes.Context.RISE, 5, GameTypes.Suit.MOUNTAIN
		),
	)
	fixture.state.players[&"one"].hand[0] = joker
	fixture.state.players[&"one"].staged_submission.assign([{
		"card_id": joker.card_id,
		"half_index": 0,
		"joker_choices": [{
			"half_index": 0,
			"context": GameTypes.Context.FALL,
			"suit": GameTypes.Suit.CLOUD,
		}],
	}])
	fixture.state.players[&"one"].has_staged_submission = true
	fixture.transport.inject_message("peer-one", GameProtocol.encode(_peer_envelope(
		"command", "joker-mimic", "one", {
			"player_id": "one", "command_id": "mimic-1", "kind": "configure_joker",
			"payload": {"card_id": str(joker.card_id), "half_index": 0,
				"context": GameTypes.Context.FALL, "suit": GameTypes.Suit.SEA},
		}
	)))
	assert_true(_last_kind(fixture.transport, "peer-one", "command_result").payload.accepted)

	for peer_id in ["peer-one", "peer-two", "peer-watch"]:
		fixture.host.send_snapshot(peer_id)
	var owner: Dictionary = _last_kind(fixture.transport, "peer-one", "snapshot").payload.state
	var opponent: Dictionary = _last_kind(fixture.transport, "peer-two", "snapshot").payload.state
	var spectator: Dictionary = _last_kind(fixture.transport, "peer-watch", "snapshot").payload.state
	assert_eq(
		owner.private_staging.staged_submission[0].joker_choices[0].context,
		GameTypes.Context.FALL
	)
	assert_eq(owner.private_hand[0].first.get("joker_suit", -1), GameTypes.Suit.SEA)
	assert_false(JSON.stringify(opponent.private_staging).contains(str(joker.card_id)))
	assert_false(spectator.has("private_staging"))
	assert_false(JSON.stringify(spectator).contains(str(joker.card_id)))
	assert_false(JSON.stringify(spectator).contains("joker_suit"))


func _session(active_ids: Array, spectator_ids: Array) -> Dictionary:
	var state := MatchState.create(_config(active_ids, spectator_ids), 5150)
	var controller := MatchController.new(state)
	var transport := FakePeerTransport.new()
	var host := HostNetworkSession.new(
		controller, transport, "match-1", &"host", Callable(self, "_now")
	)
	return {"state": state, "controller": controller, "transport": transport, "host": host}


func _now() -> int:
	return _now_msec


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


func _config(active_ids: Array, spectator_ids: Array) -> MatchConfig:
	var timers := {
		GameTypes.Phase.START: 5000,
		GameTypes.Phase.MAIN_1: 5000,
		GameTypes.Phase.HAND_PLAY: 5000,
		GameTypes.Phase.MAIN_2: 5000,
		GameTypes.Phase.END: 2000,
	}
	var abilities: Array[AbilityDefinition] = []
	for index in range(40):
		abilities.append(AbilityDefinition.new(
			StringName("ability-%d" % index), AbilityDefinition.Timing.HAND_SHAPE,
			[], &"fixture"
		))
	return MatchConfig.new(
		active_ids, spectator_ids, GameTypes.VictoryMode.SCORE_RACE, 10,
		GameTypes.InformationVisibility.PUBLIC, timers, 1000, 5000, 30000, abilities
	)


func _last_kind(transport: FakePeerTransport, peer_id: String, kind: String) -> Dictionary:
	var matches: Array = []
	for entry in transport.sent:
		if entry.peer_id != peer_id:
			continue
		var envelope: Dictionary = GameProtocol.decode(entry.bytes).envelope
		if envelope.kind == kind:
			matches.append(envelope)
	assert_true(not matches.is_empty(), "expected %s for %s" % [kind, peer_id])
	return matches[-1] if not matches.is_empty() else {}


func _player_view(snapshot: Dictionary, player_id: String) -> Dictionary:
	for player in snapshot.players:
		if player.player_id == player_id:
			return player
	return {}


func _event_kinds(transport: FakePeerTransport, peer_id: String) -> Array:
	var result: Array = []
	for entry in transport.sent:
		if entry.peer_id != peer_id:
			continue
		var envelope: Dictionary = GameProtocol.decode(entry.bytes).envelope
		if envelope.kind == "event_batch":
			result.append_array(envelope.payload.events.map(func(event): return event.kind))
	return result


func _all_payload_text(transport: FakePeerTransport, peer_id: String) -> String:
	var payloads: Array = []
	for entry in transport.sent:
		if entry.peer_id == peer_id:
			payloads.append(GameProtocol.decode(entry.bytes).envelope.payload)
	return JSON.stringify(payloads)


func _received_view_update(transport: FakePeerTransport, peer_id: String) -> bool:
	return transport.sent.any(func(entry: Dictionary) -> bool:
		return entry.peer_id == peer_id and GameProtocol.decode(entry.bytes).envelope.kind == "view_update"
	)
