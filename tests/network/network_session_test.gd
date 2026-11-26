extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")
const DomainEvent = preload("res://src/core/events/domain_event.gd")
const GameProtocol = preload("res://src/network/game_protocol.gd")
const HostNetworkSession = preload("res://src/network/host_network_session.gd")
const ClientNetworkSession = preload("res://src/network/client_network_session.gd")
const FakePeerTransport = preload("res://tests/network/fake_peer_transport.gd")

var _now_msec := 100


func before_each() -> void:
	_now_msec = 100


func test_host_is_only_authority_and_deduplicates_network_message_ids() -> void:
	var state := MatchState.create(_config(), 77)
	var controller := MatchController.new(state)
	var transport := FakePeerTransport.new()
	var host = _host(controller, transport)
	host.register_peer("peer-one", &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	host.register_peer("peer-two", &"two", GameTypes.RecipientRole.ACTIVE_PLAYER)

	var command := _command_envelope("network-1", "one", "command-1", "set_ready", {"ready": true})
	transport.inject_message("peer-one", GameProtocol.encode(command))
	assert_eq(state.phase, GameTypes.Phase.MAIN_1)
	assert_false(state.players[&"one"].ready)
	assert_eq(state.accepted_command_ids[&"one"].size(), 1)
	var peer_one_messages := _decoded_for(transport, "peer-one")
	assert_eq(peer_one_messages.map(func(message): return message.kind), [
		"command_result", "event_batch", "snapshot",
	])
	assert_true(peer_one_messages[0]["payload"]["accepted"])
	assert_eq(_decoded_for(transport, "peer-two").map(func(message): return message.kind), [
		"event_batch", "snapshot",
	])
	var peer_one_snapshot := _latest_snapshot(transport, "peer-one")
	assert_true(peer_one_snapshot.players[0].has("hand_count"))
	assert_false(peer_one_snapshot.players[0].has("hand"))

	transport.inject_message("peer-one", GameProtocol.encode(command))
	assert_eq(state.accepted_command_ids[&"one"].size(), 1)
	assert_eq(_decoded_for(transport, "peer-one").size(), 4)

	transport.clear_sent()
	transport.inject_message("peer-one", GameProtocol.encode(
		_command_envelope("network-2", "two", "command-2", "set_ready", {"ready": true})
	))
	var mismatch_messages := _decoded_for(transport, "peer-one")
	assert_eq(mismatch_messages.size(), 1)
	if mismatch_messages.is_empty():
		return
	var mismatch: Dictionary = mismatch_messages[0]
	assert_false(mismatch["payload"]["accepted"])
	assert_eq(mismatch["payload"]["error_code"], "sender_mismatch")
	assert_false(state.players[&"two"].ready)

	transport.clear_sent()
	transport.inject_message("peer-one", GameProtocol.encode(
		_command_envelope("network-3", "one", "command-3", "not_a_command", {})
	))
	assert_eq(_decoded_for(transport, "peer-one").size(), 1)
	assert_eq(_decoded_for(transport, "peer-two"), [])
	assert_false(_decoded_for(transport, "peer-one")[0]["payload"]["accepted"])


func test_clients_cannot_author_events_or_snapshots() -> void:
	for forbidden_kind in ["event_batch", "snapshot"]:
		var controller := MatchController.new(MatchState.create(_config(), 88))
		var transport := FakePeerTransport.new()
		var host = _host(controller, transport)
		host.register_peer("peer-one", &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
		transport.inject_message("peer-one", GameProtocol.encode(_envelope(
			forbidden_kind, "forbidden-%s" % forbidden_kind, "one", {}
		)))
		assert_eq(transport.closed, [{
			"peer_id": "peer-one", "reason": "protocol_violation",
		}])


func test_guest_replenishment_request_round_trips_through_public_reveal_and_history() -> void:
	var state := MatchState.create(_config(), 78)
	state.round_number = 2
	var player = state.players[&"one"]
	var removed: FullCardState = player.hand.pop_back()
	state.piles[removed.first.base_context].discard(removed.first)
	state.piles[removed.second.base_context].discard(removed.second)
	var controller := MatchController.new(state)
	var host_transport := FakePeerTransport.new()
	var guest_transport := FakePeerTransport.new()
	var host = _host(controller, host_transport)
	var guest := ClientNetworkSession.new(guest_transport, "host", "match-1", &"one")
	host.register_peer("peer-one", &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	host.register_peer("peer-two", &"two", GameTypes.RecipientRole.ACTIVE_PLAYER)
	var request := {GameTypes.Context.RISE: 2}
	var wire_request := {str(GameTypes.Context.RISE): 2}
	assert_eq(guest.submit_command("draw", {
		"command_id": "draw-command", "kind": "set_replenishment_request",
		"payload": {"request": request},
	}), OK)
	var guest_messages := _decoded_for(guest_transport, "host")
	assert_eq(guest_messages.size(), 1)
	if guest_messages.is_empty():
		return
	assert_eq(guest_messages[0].payload.payload.request, wire_request)
	assert_eq(request, {GameTypes.Context.RISE: 2}, "guest must keep the caller's request intact")
	host_transport.inject_message("peer-one", guest_transport.sent[0].bytes)
	assert_eq(state.start_requests.get(&"one"), request)
	assert_eq(_latest_snapshot(host_transport, "peer-two").get("replacement_requests"), {
		"one": wire_request,
	})

	host_transport.clear_sent()
	host_transport.inject_message("peer-one", GameProtocol.encode(_command_envelope(
		"ready", "one", "ready-command", "set_ready", {"ready": true}
	)))
	assert_eq(state.phase, GameTypes.Phase.MAIN_1)
	assert_eq(player.hand.size(), 6)
	assert_eq(host_transport.closed, [])
	var completed_request := {"0": 2, "1": 0, "2": 0}
	var recorded_reveals := state.public_history.filter(
		func(event): return event.kind == "replenishment_requests_revealed"
	)
	assert_eq(recorded_reveals.size(), 1)
	if recorded_reveals.size() == 1:
		assert_eq(recorded_reveals[0].payload.requests.one, {0: 2, 1: 0, 2: 0})
	for peer_id in ["peer-one", "peer-two"]:
		var reveals := []
		for message in _decoded_for(host_transport, peer_id):
			if message.kind == "event_batch":
				reveals.append_array(message.payload.events.filter(
					func(event): return event.kind == "replenishment_requests_revealed"
				))
		assert_eq(reveals.size(), 1)
		if reveals.size() == 1:
			assert_eq(reveals[0].payload.requests.one, completed_request)
		var history: Array = _latest_snapshot(host_transport, peer_id).get("public_history", [])
		var history_reveals := history.filter(
			func(event): return event.kind == "replenishment_requests_revealed"
		)
		assert_eq(history_reveals.size(), 1)
		if history_reveals.size() == 1:
			assert_eq(history_reveals[0].payload.requests.one, completed_request)


func test_host_rejects_noncanonical_and_unknown_replenishment_context_keys() -> void:
	var state := MatchState.create(_config(), 79)
	state.players[&"one"].hand.pop_back()
	var controller := MatchController.new(state)
	var transport := FakePeerTransport.new()
	var host = _host(controller, transport)
	host.register_peer("peer-one", &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	var invalid_requests := [{"0": 1, "00": 1}, {"01": 2}, {"+1": 2}, {"3": 2}]
	for index in range(invalid_requests.size()):
		transport.clear_sent()
		transport.inject_message("peer-one", GameProtocol.encode(_command_envelope(
			"invalid-draw-%d" % index, "one", "invalid-command-%d" % index,
			"set_replenishment_request", {"request": invalid_requests[index]}
		)))
		var messages := _decoded_for(transport, "peer-one")
		assert_eq(messages.size(), 1)
		if messages.size() == 1:
			assert_false(messages[0].payload.accepted)
			assert_eq(messages[0].payload.error_code, "unknown_context")
		assert_false(state.start_requests.has(&"one"))
	assert_eq(transport.closed, [])


func test_guest_rejects_duplicate_integer_and_string_replenishment_context_keys() -> void:
	var transport := FakePeerTransport.new()
	var guest := ClientNetworkSession.new(transport, "host", "match-1", &"one")
	assert_eq(guest.submit_command("draw", {
		"command_id": "draw-command", "kind": "set_replenishment_request",
		"payload": {"request": {0: 1, "0": 1}},
	}), ERR_INVALID_DATA)
	assert_eq(transport.sent, [])


func test_event_projection_never_leaks_owner_attacker_or_host_data() -> void:
	var controller := MatchController.new(MatchState.create(_config(), 99))
	var transport := FakePeerTransport.new()
	var host = _host(controller, transport)
	host.register_peer("peer-one", &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	host.register_peer("peer-two", &"two", GameTypes.RecipientRole.ACTIVE_PLAYER)
	host.register_peer("peer-watch", &"watcher", GameTypes.RecipientRole.SPECTATOR)
	var events: Array[DomainEvent] = [
		DomainEvent.new(&"public_event", {"value": "public"}, &"public"),
		DomainEvent.new(&"owner_event", {"secret": "owner"}, &"player", &"one"),
		DomainEvent.new(&"attacker_event", {"secret": "attacker"}, &"player", &"two"),
		DomainEvent.new(&"host_event", {"secret": "host"}, &"host"),
	]

	host.publish_events(events)
	assert_eq(_event_kinds(transport, "peer-one"), ["public_event", "owner_event"])
	assert_eq(_event_kinds(transport, "peer-two"), ["public_event", "attacker_event"])
	assert_eq(_event_kinds(transport, "peer-watch"), ["public_event"])
	for entry in transport.sent:
		var outbound_events: Array = GameProtocol.decode(entry.bytes).envelope["payload"]["events"]
		assert_false(outbound_events.any(func(event): return event["kind"] == "host_event"))

	host.publish_events([DomainEvent.new(&"second_public", {}, &"public")])
	for peer_id in ["peer-one", "peer-two", "peer-watch"]:
		var messages := _decoded_for(transport, peer_id)
		assert_eq(messages[0]["payload"]["sequence"], 1)
		assert_eq(messages[1]["payload"]["sequence"], 2)


func test_client_orders_batches_buffers_small_gaps_and_requests_resync_for_large_gaps() -> void:
	var transport := FakePeerTransport.new()
	var client = ClientNetworkSession.new(transport, "host", "match-1", &"one")
	var applied: Array = []
	var resyncs: Array = []
	client.events_applied.connect(func(events, sequence): applied.append([sequence, events]))
	client.snapshot_resync_requested.connect(func(expected, received):
		resyncs.append([expected, received])
	)

	transport.inject_message("host", GameProtocol.encode(_event_envelope(2, "second")))
	assert_eq(applied, [])
	transport.inject_message("host", GameProtocol.encode(_event_envelope(1, "first")))
	assert_eq(applied.map(func(entry): return entry[0]), [1, 2])
	assert_eq(applied[0][1][0]["kind"], "first")
	assert_eq(applied[1][1][0]["kind"], "second")

	transport.inject_message("host", GameProtocol.encode(_event_envelope(20, "too-far")))
	assert_eq(resyncs, [[3, 20]])

	var snapshot := _envelope("snapshot", "snapshot-1", "host", {
		"sequence": 9, "state": {"phase": 2, "private_player_id": "one"},
	})
	transport.inject_message("host", GameProtocol.encode(snapshot))
	assert_eq(client.latest_snapshot["private_player_id"], "one")
	assert_eq(client.expected_sequence, 10)


func test_outbound_payload_and_queue_limits_disconnect_slow_peer() -> void:
	var controller := MatchController.new(MatchState.create(_config(), 111))
	var oversized_transport := FakePeerTransport.new()
	var oversized_host = _host(controller, oversized_transport)
	oversized_host.register_peer("peer-one", &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	oversized_host.publish_events([DomainEvent.new(
		&"huge", {"blob": "x".repeat(GameProtocol.MAX_ENVELOPE_BYTES)}, &"public"
	)])
	assert_eq(oversized_transport.closed, [{
		"peer_id": "peer-one", "reason": "protocol_payload_too_large",
	}])

	var slow_transport := FakePeerTransport.new()
	slow_transport.send_error = ERR_BUSY
	var slow_host = _host(controller, slow_transport)
	slow_host.register_peer("peer-slow", &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	for index in range(HostNetworkSession.MAX_QUEUED_MESSAGES + 1):
		slow_host.publish_events([DomainEvent.new(
			&"queued", {"index": index}, &"public"
		)])
	assert_eq(slow_transport.closed[-1], {
		"peer_id": "peer-slow", "reason": "outbound_backpressure",
	})


func test_guest_deadline_draft_uses_the_newest_joker_choice_without_broadcasting_edits() -> void:
	var state := MatchState.create(_config(), 121)
	state.phase = GameTypes.Phase.HAND_PLAY
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	var joker := HalfCardState.new(&"draft-joker", 0, 0, HalfCardState.NO_SUIT, GameTypes.HalfKind.JOKER)
	state.players[&"one"].hand[0] = FullCardState.new(
		&"draft-card", joker, HalfCardState.new(&"draft-normal", state.active_context, 5, GameTypes.Suit.MOUNTAIN)
	)
	var controller := MatchController.new(state)
	var transport := FakePeerTransport.new()
	var host = _host(controller, transport)
	host.register_peer("peer-one", &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	host.register_peer("peer-two", &"two", GameTypes.RecipientRole.ACTIVE_PLAYER)
	transport.clear_sent()
	for rank in [4, 6]:
		transport.inject_message("peer-one", GameProtocol.encode(_command_envelope(
			"draft-message-%d" % rank, "one", "draft-command-%d" % rank, "update_hand_draft", {
				"round_number": state.round_number,
				"cards": [{"card_id": "draft-card", "half_index": 0, "joker_choices": [
					{"half_index": 0, "context": state.active_context, "suit": 1, "rank": rank},
				]}],
			}
		)))
	var responses := _decoded_for(transport, "peer-one")
	assert_eq(responses.map(func(message): return message.kind), ["command_result", "command_result"])
	for response in responses:
		assert_true(response.payload.accepted)
	transport.inject_message("peer-one", GameProtocol.encode(_command_envelope(
		"inactive-draft-message", "one", "inactive-draft-command", "update_hand_draft", {
			"round_number": state.round_number,
			"cards": [{"card_id": "draft-card", "half_index": 0, "joker_choices": [
				{"half_index": 0, "context": GameTypes.Context.FALL, "suit": 2, "rank": 10},
			]}],
		}
	)))
	assert_eq(_decoded_for(transport, "peer-one")[-1].payload.error_code, "joker_context_not_active")
	assert_true(_decoded_for(transport, "peer-two").is_empty())
	assert_eq(joker.joker_rank, 0, "Private timed drafts do not change the live Joker")
	_now_msec = state.phase_deadline_msec
	host.poll()
	var reveal := _network_event(transport, "peer-two", "hand_revealed", "one")
	assert_false(reveal.is_empty())
	if not reveal.is_empty():
		assert_eq(reveal.payload.cards[0].halves[0].rank, 6)


func test_resolved_joker_reveal_is_sanitized_for_every_network_role() -> void:
	var state := MatchState.create(_config(), 121)
	state.active_context = GameTypes.Context.FALL
	state.phase = GameTypes.Phase.HAND_PLAY
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	var joker := FullCardState.new(
		&"network-joker-card",
		HalfCardState.new(
			&"network-joker-half", GameTypes.Context.FLOURISH, 0, HalfCardState.NO_SUIT,
			GameTypes.HalfKind.JOKER
		),
		HalfCardState.new(
			&"network-normal-half", state.active_context, 5, GameTypes.Suit.MOUNTAIN
		),
	)
	state.players[&"one"].hand[0] = joker
	var controller := MatchController.new(state)
	var transport := FakePeerTransport.new()
	var host = _host(controller, transport)
	host.register_peer("peer-one", &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	host.register_peer("peer-two", &"two", GameTypes.RecipientRole.ACTIVE_PLAYER)
	host.register_peer("peer-watch", &"watcher", GameTypes.RecipientRole.SPECTATOR)
	controller.submit(GameCommand.new(
		&"stage-one", &"one", CommandKinds.STAGE_HAND, {"cards": [{
			"card_id": joker.card_id,
			"half_index": 0,
			"joker_choices": [{
				"half_index": 0,
				"context": GameTypes.Context.FALL,
				"suit": GameTypes.Suit.SEA,
			}],
		}]}
	), 1)
	controller.submit(GameCommand.new(
		&"pass-two", &"two", CommandKinds.STAGE_HAND, {"cards": []}
	), 1)
	controller.submit(GameCommand.new(&"lock-one", &"one", CommandKinds.LOCK_HAND), 2)
	var resolved := controller.submit(GameCommand.new(
		&"lock-two", &"two", CommandKinds.LOCK_HAND
	), 2)
	host.publish_events(resolved.events)

	for peer_id in ["peer-one", "peer-two", "peer-watch"]:
		var reveal := _network_event(transport, peer_id, "hand_revealed", "one")
		assert_eq(reveal.payload.cards[0].halves[0].context, GameTypes.Context.FALL)
		assert_eq(reveal.payload.cards[0].halves[0].rank, 0)
		assert_eq(reveal.payload.cards[0].halves[0].suit, GameTypes.Suit.SEA)
		var encoded := JSON.stringify(reveal.payload.cards)
		assert_false(encoded.contains("copy_id"))
		assert_false(encoded.contains("base_context"))
		assert_false(encoded.contains("joker_choices"))


func test_reconnect_owner_receives_modified_values_without_public_target_history() -> void:
	var state := MatchState.create(_config(), 122)
	state.phase = GameTypes.Phase.HAND_PLAY
	var owner_player = state.players[&"one"]
	var card = owner_player.hand[0]
	var half = card.second if card.first.is_joker() else card.first
	half.apply_overrides(GameTypes.Context.FALL, 10, GameTypes.Suit.SEA)
	owner_player.pending_manipulation = {
		"copy_id": owner_player.ability_hand[0].copy_id,
	}
	owner_player.completed_manipulation_ids.assign([&"low_roll"])
	var controller := MatchController.new(state)
	var transport := FakePeerTransport.new()
	var host = _host(controller, transport)
	host.register_peer("peer-one", &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	host.register_peer("peer-two", &"two", GameTypes.RecipientRole.ACTIVE_PLAYER)
	host.register_peer("peer-watch", &"watcher", GameTypes.RecipientRole.SPECTATOR)
	host.send_snapshot("peer-one")
	host.send_snapshot("peer-two")
	host.send_snapshot("peer-watch")

	var owner_snapshot: Dictionary = _latest_snapshot(transport, "peer-one")
	var opponent_snapshot: Dictionary = _latest_snapshot(transport, "peer-two")
	var spectator_snapshot: Dictionary = _latest_snapshot(transport, "peer-watch")
	var secret_card_id := str(card.card_id)
	assert_eq(owner_snapshot.private_hand[0].first.effective_context if half == card.first else owner_snapshot.private_hand[0].second.effective_context, GameTypes.Context.FALL)
	assert_eq(owner_snapshot.private_staging.completed_manipulation_ids, ["low_roll"])
	assert_false(JSON.stringify(owner_snapshot).contains("choices"))
	assert_false(JSON.stringify(owner_snapshot).contains("random_roll"))
	assert_false(JSON.stringify(opponent_snapshot).contains(secret_card_id))
	assert_false(JSON.stringify(spectator_snapshot).contains(secret_card_id))
	assert_false(opponent_snapshot.has("completed_manipulation_ids"))
	assert_false(spectator_snapshot.has("private_staging"))


func _host(controller, transport: FakePeerTransport):
	return HostNetworkSession.new(
		controller, transport, "match-1", &"host", Callable(self, "_now")
	)


func _config() -> MatchConfig:
	var timers := {
		GameTypes.Phase.START: 5000,
		GameTypes.Phase.MAIN_1: 5000,
		GameTypes.Phase.HAND_PLAY: 5000,
		GameTypes.Phase.MAIN_2: 5000,
		GameTypes.Phase.END: 2000,
	}
	var abilities: Array[AbilityDefinition] = []
	for index in range(20):
		abilities.append(AbilityDefinition.new(
			StringName("ability-%d" % index), AbilityDefinition.Timing.HAND_SHAPE,
			[], &"fixture"
		))
	return MatchConfig.new(
		[&"one", &"two"], [&"watcher"], GameTypes.VictoryMode.SCORE_RACE, 10,
		GameTypes.InformationVisibility.PUBLIC, timers, 1000, 5000, 30000, abilities,
		[NormalHandDefinition.new(
			&"high_card", 1, 1, &"high_card", Rational.new(1, 1)
		)], []
	)


func _command_envelope(
	message_id: String, sender_id: String, command_id: String, kind: String, payload: Dictionary
) -> Dictionary:
	return _envelope("command", message_id, sender_id, {
		"command_id": command_id,
		"player_id": sender_id,
		"kind": kind,
		"payload": payload,
	})


func _event_envelope(sequence: int, kind: String) -> Dictionary:
	return _envelope("event_batch", "event-%d" % sequence, "host", {
		"sequence": sequence, "events": [{"kind": kind, "payload": {}}],
	})


func _envelope(
	kind: String, message_id: String, sender_id: String, payload: Dictionary
) -> Dictionary:
	return {
		"v": 1, "kind": kind, "message_id": message_id,
		"match_id": "match-1", "sender_id": sender_id, "payload": payload,
	}


func _decoded_for(transport: FakePeerTransport, peer_id: String) -> Array:
	var result: Array = []
	for entry in transport.sent:
		if entry.peer_id == peer_id:
			var decoded = GameProtocol.decode(entry.bytes)
			assert_true(decoded.ok)
			if decoded.ok:
				result.append(decoded.envelope)
	return result


func _latest_snapshot(transport: FakePeerTransport, peer_id: String) -> Dictionary:
	var messages := _decoded_for(transport, peer_id)
	for index in range(messages.size() - 1, -1, -1):
		if messages[index].kind == "snapshot":
			return messages[index].payload.state
	return {}


func _event_kinds(transport: FakePeerTransport, peer_id: String) -> Array:
	var messages := _decoded_for(transport, peer_id)
	return messages[0]["payload"]["events"].map(func(event): return event["kind"])


func _network_event(
	transport: FakePeerTransport,
	peer_id: String,
	kind: String,
	player_id: String
) -> Dictionary:
	for message: Dictionary in _decoded_for(transport, peer_id):
		if message.kind != "event_batch":
			continue
		for event: Dictionary in message.payload.events:
			if event.kind == kind and event.payload.get("player_id") == player_id:
				return event
	return {}


func _now() -> int:
	return _now_msec
