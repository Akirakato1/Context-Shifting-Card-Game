extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const EventKinds = preload("res://src/core/events/event_kinds.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")
const SnapshotProjector = preload("res://src/core/match/snapshot_projector.gd")


func test_public_card_ids_are_opaque_and_reveals_use_sanitized_effective_faces() -> void:
	var state := _state(101)
	for player_id in state.seat_order:
		for card in state.players[player_id].hand:
			assert_false(str(card.card_id).contains(str(card.first.copy_id)))
			assert_false(str(card.card_id).contains(str(card.second.copy_id)))
	state.phase = GameTypes.Phase.HAND_PLAY
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	var controller := MatchController.new(state)
	for player_id in state.seat_order:
		var card = _eligible_card(state, player_id)
		controller.submit(_stage(
			StringName("stage-%s" % player_id), player_id, card
		), 1)
	var first := controller.submit(_lock(&"lock-one", &"one"), 2)
	assert_true(first.accepted)
	var resolved := controller.submit(_lock(&"lock-two", &"two"), 2)
	var reveal = _event_for_player(resolved.events, EventKinds.HAND_REVEALED, &"one")
	assert_true(reveal != null)
	assert_eq(reveal.payload.cards.size(), 1)
	var public_card: Dictionary = reveal.payload.cards[0]
	assert_true(public_card.has("selected_half_index"))
	assert_eq(public_card.halves.size(), 2)
	for half: Dictionary in public_card.halves:
		assert_true(half.has("context"))
		assert_true(half.has("rank"))
		assert_true(half.has("suit"))
		assert_false(half.has("copy_id"))
		assert_false(half.has("base_context"))


func test_public_abilities_use_definition_parameters_and_reject_client_authored_effects() -> void:
	var state := _main_one_state(102)
	state.players[&"one"].ability_hand[0].definition = AbilityDefinition.new(
		&"fixed-buff", AbilityDefinition.Timing.HAND_SHAPE, [], &"score_modifier",
		0, &"", {"operation": &"add", "numerator": 2, "denominator": 1}
	)
	var controller := MatchController.new(state)
	controller.tick(0)
	var malicious := controller.submit(GameCommand.new(
		&"malicious", &"one", CommandKinds.PLAY_PUBLIC_ABILITY, {
			"copy_id": state.players[&"one"].ability_hand[0].copy_id,
			"target_player_id": &"two",
			"effect": {"operation": &"multiply", "numerator": 999, "denominator": 1},
		}
	), 10)
	assert_false(malicious.accepted)
	assert_eq(malicious.error_code, &"unexpected_effect_payload")
	assert_eq(state.players[&"two"].score_modifiers.size(), 0)

	var accepted := controller.submit(GameCommand.new(
		&"fixed", &"one", CommandKinds.PLAY_PUBLIC_ABILITY, {
			"copy_id": state.players[&"one"].ability_hand[0].copy_id,
			"target_player_id": &"two",
		}
	), 11)
	assert_true(accepted.accepted)
	assert_eq(state.players[&"two"].score_modifiers.size(), 1)
	assert_eq(state.players[&"two"].score_modifiers[0].value.numerator, 2)


func test_manipulation_choice_schema_and_malformed_values_reject_without_mutation() -> void:
	var state := _hand_play_state(103)
	state.players[&"one"].ability_hand[0].definition = AbilityDefinition.new(
		&"set-ten", AbilityDefinition.Timing.HAND_MANIPULATION, [], &"manipulate_half",
		0, &"", {}, {
			"contexts": [GameTypes.Context.A], "ranks": [10],
			"suits": [GameTypes.Suit.ONE],
		}
	)
	var ability = state.players[&"one"].ability_hand[0]
	var card = state.players[&"one"].hand[0]
	card.first.apply_overrides(GameTypes.Context.A, card.first.effective_rank(), GameTypes.Suit.ONE)
	var controller := MatchController.new(state)
	assert_true(controller.submit(GameCommand.new(
		&"begin", &"one", CommandKinds.STAGE_MANIPULATION, {"copy_id": ability.copy_id}
	), 1).accepted)
	var before := state.to_dict()
	var malformed := controller.submit(GameCommand.new(
		&"bad-type", &"one", CommandKinds.COMMIT_MANIPULATION, {
			"card_id": card.card_id, "half_index": 0, "context": GameTypes.Context.A,
			"rank": "ten", "suit": GameTypes.Suit.ONE,
		}
	), 2)
	assert_eq(malformed.error_code, &"malformed_command")
	assert_eq(state.to_dict(), before)
	var disallowed := controller.submit(GameCommand.new(
		&"bad-choice", &"one", CommandKinds.COMMIT_MANIPULATION, {
			"card_id": card.card_id, "half_index": 0, "context": GameTypes.Context.A,
			"rank": 9, "suit": GameTypes.Suit.ONE,
		}
	), 3)
	assert_eq(disallowed.error_code, &"manipulation_choice_not_allowed")
	assert_eq(card.first.effective_rank(), card.first.base_rank)


func test_first_malformed_phase_command_does_not_start_clock_or_mutate_state() -> void:
	var state := _main_one_state(116)
	var controller := MatchController.new(state)
	var before := state.to_dict()
	var malformed := controller.submit(GameCommand.new(
		&"malformed", &"one", CommandKinds.PLAY_PUBLIC_ABILITY,
		{"copy_id": 123, "target_player_id": &"two"}
	), 9000)
	assert_eq(malformed.error_code, &"malformed_command")
	assert_eq(state.to_dict(), before)


func test_every_interactive_phase_rejects_commands_after_deadline_without_mutation() -> void:
	var start := _state(104)
	var start_controller := MatchController.new(start)
	start_controller.tick(0)
	var start_before := start.to_dict()
	var late_start := start_controller.submit(GameCommand.new(
		&"late-start", &"one", CommandKinds.SET_READY, {"ready": true}
	), 5001)
	assert_eq(late_start.error_code, &"phase_deadline_passed")
	assert_eq(start.to_dict(), start_before)

	var hand := _hand_play_state(105)
	var hand_controller := MatchController.new(hand)
	hand_controller.tick(0)
	var hand_before := hand.to_dict()
	var late_hand := hand_controller.submit(_stage(
		&"late-hand", &"one", _eligible_card(hand, &"one")
	), 5001)
	assert_eq(late_hand.error_code, &"phase_deadline_passed")
	assert_eq(hand.to_dict(), hand_before)

	var ending := _state(106)
	ending.phase = GameTypes.Phase.END
	ending.phase_started_msec = -1
	ending.phase_deadline_msec = -1
	var end_controller := MatchController.new(ending)
	end_controller.tick(0)
	var end_before := ending.to_dict()
	var late_end := end_controller.submit(GameCommand.new(
		&"late-end", &"one", CommandKinds.CHOOSE_ABILITY_DISCARDS, {"copy_ids": []}
	), 2001)
	assert_eq(late_end.error_code, &"phase_deadline_passed")
	assert_eq(ending.to_dict(), end_before)


func test_locked_hand_cannot_be_revised_or_manipulated() -> void:
	var state := _hand_play_state(107)
	var controller := MatchController.new(state)
	var card = _eligible_card(state, &"one")
	assert_true(controller.submit(_stage(&"stage", &"one", card), 1).accepted)
	assert_true(controller.submit(_lock(&"lock", &"one"), 2).accepted)
	var before := state.to_dict()
	var revised := controller.submit(_stage(&"revise", &"one", card), 3)
	assert_eq(revised.error_code, &"hand_already_locked")
	assert_eq(state.to_dict(), before)
	var manipulation := controller.submit(GameCommand.new(
		&"manipulate", &"one", CommandKinds.STAGE_MANIPULATION,
		{"copy_id": state.players[&"one"].ability_hand[0].copy_id}
	), 4)
	assert_eq(manipulation.error_code, &"hand_already_locked")
	assert_eq(state.to_dict(), before)


func test_end_transaction_disconnect_uses_full_disconnect_path_for_player_and_host() -> void:
	var state := _main_two_state(108)
	var controller := MatchController.new(state)
	controller.end_transaction_probe = func(): controller.notify_player_disconnected(&"two", 123)
	controller.submit(_ready(&"r1", &"one"), 10)
	controller.submit(_ready(&"r2", &"two"), 10)
	assert_false(state.players[&"two"].connected)
	assert_eq(state.players[&"two"].disconnect_deadline_msec, 30123)
	assert_true(state.frozen)

	var host_state := _main_two_state(109)
	var host_controller := MatchController.new(host_state)
	host_controller.end_transaction_probe = func(): host_controller.notify_player_disconnected(&"one", 222)
	host_controller.submit(_ready(&"hr1", &"one"), 10)
	host_controller.submit(_ready(&"hr2", &"two"), 10)
	assert_true(host_state.match_complete)
	assert_eq(host_state.phase, GameTypes.Phase.COMPLETE)
	assert_eq(host_state.winner_id, &"")


func test_phase_state_round_trip_and_public_projection_preserve_resync_information() -> void:
	var state := _resolved_main_two_state(110)
	state.reaction_deadline_msec = 4444
	var snapshot := state.to_dict()
	var restored := MatchState.from_dict(snapshot)
	assert_eq(restored.to_dict(), snapshot)
	assert_eq(restored.players[&"one"].submitted_faces.size(), 1)
	assert_true(restored.players[&"one"].locked_normal != null)
	assert_true(restored.players[&"one"].locked_context != null)
	assert_true(restored.players[&"one"].provisional_score != null)

	var projected := SnapshotProjector.for_recipient(
		state, &"watcher", GameTypes.RecipientRole.SPECTATOR
	)
	assert_eq(projected.phase_deadline_msec, state.phase_deadline_msec)
	assert_eq(projected.reaction_deadline_msec, 4444)
	var public_one := _projected_player(projected.players, &"one")
	assert_true(public_one.has("revealed_submission"))
	assert_eq(public_one.revealed_submission.cards.size(), 1)
	assert_true(public_one.revealed_submission.has("normal_category"))
	assert_true(public_one.revealed_submission.has("provisional_score"))


func test_joker_draft_and_resolved_views_survive_canonical_round_trip() -> void:
	var state := _hand_play_state(112)
	var joker := FullCardState.new(
		&"roundtrip-joker",
		HalfCardState.new(
			&"roundtrip-joker-half", GameTypes.Context.B, 0, HalfCardState.NO_SUIT,
			GameTypes.HalfKind.JOKER
		),
		HalfCardState.new(
			&"roundtrip-normal-half", state.active_context, 6, GameTypes.Suit.ONE
		),
	)
	state.players[&"one"].hand[0] = joker
	var controller := MatchController.new(state)
	var staged := GameCommand.new(
		&"stage-joker", &"one", CommandKinds.STAGE_HAND, {"cards": [{
			"card_id": joker.card_id,
			"half_index": 0,
			"joker_choices": [{
				"half_index": 0,
				"context": GameTypes.Context.C,
				"suit": GameTypes.Suit.THREE,
			}],
		}]}
	)
	assert_true(controller.submit(staged, 1).accepted)
	assert_true(controller.submit(GameCommand.new(
		&"pass-two", &"two", CommandKinds.STAGE_HAND, {"cards": []}
	), 1).accepted)

	var draft_snapshot := state.to_dict()
	var restored_draft := MatchState.from_dict(draft_snapshot)
	assert_eq(restored_draft.to_dict(), draft_snapshot)
	assert_eq(
		restored_draft.players[&"one"].staged_submission[0]["joker_choices"][0]["context"],
		GameTypes.Context.C
	)

	controller.submit(_lock(&"lock-original-one", &"one"), 2)
	controller.submit(_lock(&"lock-original-two", &"two"), 2)
	var restored_controller := MatchController.new(restored_draft)
	restored_controller.submit(_lock(&"lock-restored-one", &"one"), 2)
	restored_controller.submit(_lock(&"lock-restored-two", &"two"), 2)
	assert_eq(
		restored_draft.players[&"one"].submitted_card_views,
		state.players[&"one"].submitted_card_views
	)

	var resolved_snapshot := state.to_dict()
	var restored_resolved := MatchState.from_dict(resolved_snapshot)
	assert_eq(restored_resolved.to_dict(), resolved_snapshot)
	assert_eq(
		restored_resolved.players[&"one"].submitted_card_views,
		state.players[&"one"].submitted_card_views
	)

	var legacy_snapshot: Dictionary = resolved_snapshot.duplicate(true)
	for player_data: Dictionary in legacy_snapshot.players:
		player_data.erase("submitted_card_views")
		for selection: Dictionary in player_data.get("staged_submission", []):
			selection.erase("joker_choices")
	var restored_legacy := MatchState.from_dict(legacy_snapshot)
	assert_true(restored_legacy.players[&"one"].submitted_card_views.is_empty())
	assert_eq(
		restored_legacy.players[&"one"].staged_submission[0].get("joker_choices", []), []
	)


func test_controller_replay_and_partial_start_requests_survive_state_round_trip() -> void:
	var state := _state(111)
	var removed = state.players[&"one"].hand.pop_back()
	state.piles[removed.first.base_context].discard(removed.first)
	state.piles[removed.second.base_context].discard(removed.second)
	state.start_prepared_round = 0
	var controller := MatchController.new(state)
	var command := GameCommand.new(
		&"request", &"one", CommandKinds.SET_REPLENISHMENT_REQUEST,
		{"request": {GameTypes.Context.A: 1}}
	)
	assert_true(controller.submit(command, 1).accepted)
	var restored := MatchState.from_dict(state.to_dict())
	var restored_controller := MatchController.new(restored)
	assert_eq(restored_controller.submit(command, 2).error_code, &"duplicate_command")
	assert_true(restored.start_requests.has(&"one"))


func test_replenishment_context_counts_private_cards_and_context_advance_are_evented() -> void:
	var state := _state(112, GameTypes.InformationVisibility.PRIVATE)
	var removed = state.players[&"one"].hand.pop_back()
	state.piles[removed.first.base_context].discard(removed.first)
	state.piles[removed.second.base_context].discard(removed.second)
	state.start_prepared_round = 0
	var controller := MatchController.new(state)
	controller.submit(GameCommand.new(
		&"request", &"one", CommandKinds.SET_REPLENISHMENT_REQUEST,
		{"request": {GameTypes.Context.A: 1}}
	), 1)
	controller.submit(_ready(&"one-ready", &"one"), 2)
	var completed := controller.submit(_ready(&"two-ready", &"two"), 2)
	var request_event = _first_event(completed.events, EventKinds.REPLENISHMENT_REQUESTS_REVEALED)
	assert_true(request_event != null)
	assert_eq(request_event.payload.counts.one, 1)
	assert_false(request_event.payload.has("requests"))
	var replenished = _recipient_event(completed.events, EventKinds.HAND_REPLENISHED, &"one")
	assert_true(replenished.payload.cards[0].first.has("rank"))
	assert_true(replenished.payload.cards[0].second.has("effective_context"))

	var end_state := _state(113)
	end_state.phase = GameTypes.Phase.END
	end_state.phase_started_msec = -1
	end_state.phase_deadline_msec = -1
	for player_id in end_state.seat_order:
		end_state.players[player_id].end_discard_complete = true
	var end_controller := MatchController.new(end_state)
	end_controller.tick(0)
	var end_events := end_controller.tick(2001)
	assert_true(_first_event(end_events, EventKinds.CONTEXT_ADVANCED) != null)


func test_main_two_score_recalculation_emits_authoritative_public_update() -> void:
	var state := _resolved_main_two_state(117)
	state.players[&"one"].ability_hand[0].definition = AbilityDefinition.new(
		&"late-buff", AbilityDefinition.Timing.HAND_SHAPE, [], &"score_modifier",
		0, &"", {"operation": &"add", "numerator": 3, "denominator": 1}
	)
	var controller := MatchController.new(state)
	var result := controller.submit(GameCommand.new(
		&"late-buff", &"one", CommandKinds.PLAY_PUBLIC_ABILITY, {
			"copy_id": state.players[&"one"].ability_hand[0].copy_id,
			"target_player_id": &"one",
		}
	), 10)
	var update = _first_event(result.events, EventKinds.PROVISIONAL_SCORE_UPDATED)
	assert_true(update != null)
	assert_eq(update.payload.player_id, "one")
	assert_eq(update.payload.provisional_score, state.players[&"one"].provisional_score.final_score)


func test_reconnect_and_forfeit_validate_identity_replay_and_visibility() -> void:
	var state := _main_one_state(114)
	var controller := MatchController.new(state)
	controller.notify_player_disconnected(&"two", 10)
	var token: String = state.players[&"two"].reconnect_token
	assert_false(token.is_empty())
	assert_false(token.contains("two"))
	assert_false(token.contains(str(state.seed)))
	assert_eq(controller.submit(GameCommand.new(
		&"", &"two", CommandKinds.RECONNECT, {"token": token}
	), 11).error_code, &"malformed_command")
	var reconnect := GameCommand.new(&"reconnect", &"two", CommandKinds.RECONNECT, {"token": token})
	assert_true(controller.submit(reconnect, 12).accepted)
	assert_eq(controller.submit(reconnect, 13).error_code, &"duplicate_command")

	var forfeit_state := _main_one_state(115)
	var forfeit_controller := MatchController.new(forfeit_state)
	assert_eq(forfeit_controller.submit(GameCommand.new(
		&"spectator-forfeit", &"watcher", CommandKinds.FORFEIT
	), 1).error_code, &"not_active_player")
	var forfeited := forfeit_controller.submit(GameCommand.new(
		&"forfeit", &"two", CommandKinds.FORFEIT
	), 2)
	assert_true(forfeited.accepted)
	assert_true(_first_event(forfeited.events, EventKinds.ABILITIES_DISCARDED) != null)
	assert_eq(forfeit_controller.submit(GameCommand.new(
		&"forfeit", &"two", CommandKinds.FORFEIT
	), 3).error_code, &"duplicate_command")


func test_config_requires_every_known_phase_timer() -> void:
	var timers := _timers()
	timers.erase(GameTypes.Phase.END)
	assert_eq(_config(timers).validate(), &"missing_phase_timer")
	var extra := _timers()
	extra[99] = 100
	assert_eq(_config(extra).validate(), &"unknown_phase_timer")


func _state(
	seed_value: int,
	visibility: int = GameTypes.InformationVisibility.PUBLIC
) -> MatchState:
	return MatchState.create(_config(_timers(), visibility), seed_value)


func _main_one_state(seed_value: int) -> MatchState:
	var state := _state(seed_value)
	state.phase = GameTypes.Phase.MAIN_1
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	return state


func _hand_play_state(seed_value: int) -> MatchState:
	var state := _state(seed_value)
	state.phase = GameTypes.Phase.HAND_PLAY
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	return state


func _main_two_state(seed_value: int) -> MatchState:
	var state := _resolved_main_two_state(seed_value)
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	return state


func _resolved_main_two_state(seed_value: int) -> MatchState:
	var state := _hand_play_state(seed_value)
	var controller := MatchController.new(state)
	for player_id in state.seat_order:
		controller.submit(_stage(
			StringName("stage-%s" % player_id), player_id, _eligible_card(state, player_id)
		), 1)
	controller.submit(_lock(&"lock-one", &"one"), 2)
	controller.submit(_lock(&"lock-two", &"two"), 2)
	return state


func _config(
	timers: Dictionary,
	visibility: int = GameTypes.InformationVisibility.PUBLIC
) -> MatchConfig:
	var abilities: Array[AbilityDefinition] = []
	for index in range(20):
		abilities.append(AbilityDefinition.new(
			StringName("ability-%d" % index), AbilityDefinition.Timing.HAND_SHAPE, [], &"noop"
		))
	return MatchConfig.new(
		[&"one", &"two"], [&"watcher"], GameTypes.VictoryMode.SCORE_RACE, 100,
		visibility, timers, 1000, 5000, 30000, abilities,
		_default_normal_definitions(), _default_context_definitions()
	)


func _timers() -> Dictionary:
	return {
		GameTypes.Phase.START: 5000, GameTypes.Phase.MAIN_1: 5000,
		GameTypes.Phase.HAND_PLAY: 5000, GameTypes.Phase.MAIN_2: 5000,
		GameTypes.Phase.END: 2000,
	}


func _default_normal_definitions() -> Array:
	const Rational = preload("res://src/core/common/rational.gd")
	const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")
	return [NormalHandDefinition.new(&"high_card", 1, 1, &"high_card", Rational.new(1, 1))]


func _default_context_definitions() -> Array:
	const Rational = preload("res://src/core/common/rational.gd")
	const ContextHandDefinition = preload("res://src/core/scoring/context_hand_definition.gd")
	return [ContextHandDefinition.new(
		&"one-a", 1, {GameTypes.Context.A: 1}, Rational.new(1, 1)
	)]


func _eligible_card(state: MatchState, player_id: StringName):
	for card in state.players[player_id].hand:
		if not card.eligible_half_indexes(state.active_context).is_empty():
			return card
	return null


func _stage(id: StringName, player_id: StringName, card) -> GameCommand:
	var half_index: int = card.eligible_half_indexes(GameTypes.Context.A)[0]
	return GameCommand.new(id, player_id, CommandKinds.STAGE_HAND, {
		"cards": [{"card_id": card.card_id, "half_index": half_index}],
	})


func _lock(id: StringName, player_id: StringName) -> GameCommand:
	return GameCommand.new(id, player_id, CommandKinds.LOCK_HAND)


func _ready(id: StringName, player_id: StringName) -> GameCommand:
	return GameCommand.new(id, player_id, CommandKinds.SET_READY, {"ready": true})


func _event_for_player(events: Array, kind: StringName, player_id: StringName):
	for event in events:
		if event.kind == kind and event.payload.get("player_id") == str(player_id):
			return event
	return null


func _first_event(events: Array, kind: StringName):
	for event in events:
		if event.kind == kind:
			return event
	return null


func _recipient_event(events: Array, kind: StringName, recipient_id: StringName):
	for event in events:
		if event.kind == kind and event.recipient_id == recipient_id:
			return event
	return null


func _projected_player(players: Array, player_id: StringName) -> Dictionary:
	for player: Dictionary in players:
		if player.player_id == str(player_id):
			return player
	return {}
