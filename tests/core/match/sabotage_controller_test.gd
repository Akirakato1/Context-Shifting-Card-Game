extends "res://tests/test_case.gd"

const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const EventKinds = preload("res://src/core/events/event_kinds.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const GameTypes = preload("res://src/core/common/game_types.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const SnapshotProjector = preload("res://src/core/match/snapshot_projector.gd")
const DomainEvent = preload("res://src/core/events/domain_event.gd")


func test_momentary_lock_is_private_blocks_submission_and_round_end_clears_it() -> void:
	var state := _state(401)
	_set_sabotage(state, &"one", &"momentary_lock")
	var controller := MatchController.new(state)
	var result := controller.submit(_play(&"lock", state, &"one", &"two"), 1)
	assert_true(result.accepted)
	assert_eq(state.players[&"two"].submission_locked_card_ids.size(), 1)
	var locked_id: StringName = state.players[&"two"].submission_locked_card_ids[0]
	var public_text := JSON.stringify(_event_for_audience(result.events, &"public").payload)
	var attacker_text := JSON.stringify(_event_for_recipient(result.events, &"one").payload)
	var target_text := JSON.stringify(_event_for_recipient(result.events, &"two").payload)
	assert_false(public_text.contains(str(locked_id)))
	assert_false(attacker_text.contains(str(locked_id)))
	assert_true(target_text.contains(str(locked_id)))

	state.phase = GameTypes.Phase.HAND_PLAY
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	var stage := controller.submit(GameCommand.new(
		&"stage-locked", &"two", CommandKinds.STAGE_HAND,
		{"cards": [{"card_id": locked_id, "half_index": 0, "joker_choices": []}]}
	), 2)
	assert_false(stage.accepted)
	assert_eq(stage.error_code, &"card_submission_locked")

	for player_id in state.seat_order:
		state.players[player_id].locked_normal = null
		state.players[player_id].locked_context = null
	controller.call("_begin_end", 3)
	assert_true(state.players[&"two"].submission_locked_card_ids.is_empty())


func test_sabotage_rejects_self_spectator_pending_inactive_and_disconnected_targets() -> void:
	for target_state in [&"self", &"spectator", &"pending", &"inactive", &"disconnected"]:
		var state := _state(410)
		_set_sabotage(state, &"one", &"rank_scramble")
		var target := &"two"
		if target_state == &"self": target = &"one"
		elif target_state == &"spectator": target = &"watcher"
		elif target_state == &"pending": state.players[&"two"].pending = true
		elif target_state == &"inactive": state.players[&"two"].active = false
		elif target_state == &"disconnected": state.players[&"two"].connected = false
		var result := MatchController.new(state).submit(_play(&"bad", state, &"one", target), 1)
		assert_false(result.accepted, "expected %s target rejection" % target_state)
		assert_eq(state.players[&"one"].ability_hand.size(), 2)


func test_forced_mulligan_resets_departing_card_reconciles_lock_and_reveals_only_draw_counts() -> void:
	var state := _state(415)
	_set_sabotage(state, &"one", &"forced_mulligan")
	var target = state.players[&"two"]
	var prior_cards := {}
	for card in target.hand:
		prior_cards[str(card.card_id)] = card
		if not card.first.is_joker():
			card.first.apply_overrides(
				GameTypes.Context.FALL, 10, GameTypes.Suit.SEA
			)
		target.submission_locked_card_ids.append(card.card_id)
	var result := MatchController.new(state).submit(
		_play(&"mulligan", state, &"one", &"two"), 1
	)
	assert_true(result.accepted)
	var target_event = _event_for_recipient(result.events, &"two")
	var public_event = _event_for_audience(result.events, &"public")
	var removed_id := str(target_event.payload.removed_card_id)
	var removed = prior_cards[removed_id]
	assert_true(target_event.payload.has("card_changes"))
	if target_event.payload.has("card_changes"):
		var change: Dictionary = target_event.payload.card_changes[0]
		assert_true(change.before.has("first"))
		assert_true(change.after.has("first"))
		assert_eq(change.before.first.effective_rank, 10 if not removed.first.is_joker() else 0)
	assert_false(public_event.payload.has("card_changes"))
	assert_false(_event_for_recipient(result.events, &"one").payload.has("card_changes"))
	assert_eq(target.hand.size(), 6)
	assert_false(target.submission_locked_card_ids.has(StringName(removed_id)))
	assert_eq(removed.first.effective_context(), removed.first.base_context)
	assert_eq(removed.first.effective_rank(), removed.first.base_rank)
	assert_eq(removed.first.effective_suit(), removed.first.base_suit)
	var draw_total := 0
	for count in public_event.payload.draw_context_counts.values(): draw_total += count
	assert_eq(draw_total, 2)
	assert_false(JSON.stringify(public_event.payload).contains(removed_id))


func test_lock_and_sabotage_overrides_survive_state_and_private_snapshot_round_trip() -> void:
	var state := _state(420)
	_set_sabotage(state, &"one", &"momentary_lock")
	var controller := MatchController.new(state)
	assert_true(controller.submit(_play(&"lock", state, &"one", &"two"), 1).accepted)
	_set_sabotage(state, &"one", &"rank_scramble")
	assert_true(controller.submit(_play(&"rank", state, &"one", &"two"), 2).accepted)
	var restored := MatchState.from_dict(state.to_dict())
	assert_eq(
		restored.players[&"two"].submission_locked_card_ids,
		state.players[&"two"].submission_locked_card_ids
	)
	var owner := SnapshotProjector.for_recipient(
		restored, &"two", GameTypes.RecipientRole.ACTIVE_PLAYER
	)
	var spectator := SnapshotProjector.for_recipient(
		restored, &"watcher", GameTypes.RecipientRole.SPECTATOR
	)
	assert_eq(owner.private_hand.filter(func(card): return card.submission_locked).size(), 1)
	assert_false(JSON.stringify(spectator).contains("submission_locked"))


func test_public_history_is_sanitized_bounded_serialized_and_identical_for_spectators() -> void:
	var state := _state(430)
	for index in range(35):
		state.record_public_events([DomainEvent.new(
			EventKinds.SABOTAGE_RESOLVED,
			{"ability_id": "public-%d" % index, "source_player_id": "one",
			"target_player_id": "two"}, &"public"
		)])
	state.record_public_events([DomainEvent.new(
		EventKinds.SABOTAGE_RESOLVED, {"removed_card_id": "secret"}, &"player", &"two"
	)])
	assert_eq(state.public_history.size(), 32)
	assert_eq(state.public_history[0].payload.ability_id, "public-3")
	assert_false(JSON.stringify(state.public_history).contains("secret"))
	var restored := MatchState.from_dict(state.to_dict())
	var active := SnapshotProjector.for_recipient(
		restored, &"one", GameTypes.RecipientRole.ACTIVE_PLAYER
	)
	var spectator := SnapshotProjector.for_recipient(
		restored, &"watcher", GameTypes.RecipientRole.SPECTATOR
	)
	assert_eq(active.public_history, spectator.public_history)
	assert_eq(active.public_history.size(), 32)


func _state(seed_value: int) -> MatchState:
	var definitions: Array[AbilityDefinition] = AbilityCatalog.build_deck(
		AbilityCatalog.provisional_deck_recipe()
	)
	var config := MatchConfig.new(
		[&"one", &"two"], [&"watcher"], GameTypes.VictoryMode.SCORE_RACE, 20,
		GameTypes.InformationVisibility.PUBLIC,
		{GameTypes.Phase.START: 5000, GameTypes.Phase.MAIN_1: 5000,
		GameTypes.Phase.HAND_PLAY: 5000, GameTypes.Phase.MAIN_2: 5000,
		GameTypes.Phase.END: 2000}, 1000, 5000, 30000, definitions
	)
	var state := MatchState.create(config, seed_value)
	state.phase = GameTypes.Phase.MAIN_1
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	return state


func _set_sabotage(state: MatchState, player_id: StringName, id: StringName) -> void:
	for definition in AbilityCatalog.sabotage_designs():
		if definition.id == id:
			state.players[player_id].ability_hand[0].definition = definition
			return
	assert(false, "unknown sabotage fixture")


func _play(id: StringName, state: MatchState, source: StringName, target: StringName) -> GameCommand:
	return GameCommand.new(id, source, CommandKinds.PLAY_PUBLIC_ABILITY, {
		"copy_id": state.players[source].ability_hand[0].copy_id,
		"target_player_id": target,
		"choices": {"target_player_id": [target]},
	})


func _ready(id: StringName, player_id: StringName) -> GameCommand:
	return GameCommand.new(id, player_id, CommandKinds.SET_READY, {"ready": true})


func _event_for_audience(events: Array, audience: StringName):
	for event in events:
		if event.kind == EventKinds.SABOTAGE_RESOLVED and event.audience == audience: return event
	return null


func _event_for_recipient(events: Array, recipient: StringName):
	for event in events:
		if event.kind == EventKinds.SABOTAGE_RESOLVED and event.recipient_id == recipient: return event
	return null
