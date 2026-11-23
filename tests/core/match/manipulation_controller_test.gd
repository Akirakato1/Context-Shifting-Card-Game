extends "res://tests/test_case.gd"

const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const ManipulationResolver = preload("res://src/core/abilities/manipulation_resolver.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const GameTypes = preload("res://src/core/common/game_types.gd")
const RandomSource = preload("res://src/core/common/random_source.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")


func test_commit_requires_exact_schema_unique_owned_targets_and_valid_options() -> void:
	var state := _state(210)
	var hand: Array = state.players[&"one"].hand
	var card_id := str(hand[0].card_id)
	var suit_imprint := _definition(&"suit_imprint")
	assert_eq(
		ManipulationResolver.validate(suit_imprint, hand, {}),
		&"manipulation_choice_keys_mismatch"
	)
	assert_eq(ManipulationResolver.validate(suit_imprint, hand, {
		"cards": [card_id], "suit": [GameTypes.Suit.MOUNTAIN], "extra": [],
	}), &"manipulation_choice_keys_mismatch")
	assert_eq(ManipulationResolver.validate(suit_imprint, hand, {
		"cards": card_id, "suit": [GameTypes.Suit.MOUNTAIN],
	}), &"malformed_manipulation_choice")
	assert_eq(ManipulationResolver.validate(suit_imprint, hand, {
		"cards": [card_id], "suit": [99],
	}), &"invalid_manipulation_choice")

	var low_roll := _definition(&"low_roll")
	assert_eq(ManipulationResolver.validate(low_roll, hand, {"cards": []}), &"manipulation_choice_count")
	assert_eq(ManipulationResolver.validate(low_roll, hand, {
		"cards": [card_id, card_id],
	}), &"duplicate_manipulation_target")
	assert_eq(ManipulationResolver.validate(low_roll, hand, {
		"cards": ["missing-card"],
	}), &"card_not_in_hand")
	assert_eq(ManipulationResolver.validate(low_roll, hand, {
		"cards": ["one", "two", "three", "four", "five", "six", "seven"],
	}), &"manipulation_choice_count")

	var roulette := _definition(&"context_roulette")
	assert_eq(ManipulationResolver.validate(roulette, hand, {"halves": [{
		"card_id": card_id, "half_index": 2,
	}]}), &"invalid_half_index")
	assert_eq(ManipulationResolver.validate(roulette, hand, {"halves": [
		{"card_id": card_id, "half_index": 0},
		{"card_id": card_id, "half_index": 0},
	]}), &"duplicate_manipulation_target")
	assert_eq(ManipulationResolver.validate(roulette, hand, {"halves": [{
		"card_id": "missing-card", "half_index": 0,
	}]}), &"card_not_in_hand")


func test_rejected_manipulation_preserves_cards_ability_pending_state_and_rng() -> void:
	var state := _state(211)
	var controller := MatchController.new(state)
	var ability = _set_ability(state, &"one", &"suit_imprint")
	var card = state.players[&"one"].hand[0]
	assert_true(controller.submit(_begin(&"begin", ability.copy_id), 10).accepted)
	var before := state.to_dict()
	var rng_before := state.rng.state_token()

	var rejected := controller.submit(_commit(&"reject", {
		"cards": [str(card.card_id)], "suit": [99],
	}), 11)

	assert_false(rejected.accepted)
	assert_eq(rejected.error_code, &"invalid_manipulation_choice")
	assert_eq(state.to_dict(), before)
	assert_eq(state.rng.state_token(), rng_before)
	assert_true(state.players[&"one"].ability_hand.has(ability))
	assert_eq(ability.zone, 1)


func test_success_consumes_ability_clears_pending_and_persists_override() -> void:
	var state := _state(212)
	var controller := MatchController.new(state)
	var ability = _set_ability(state, &"one", &"rise_infusion")
	var card = _ordinary_card(state.players[&"one"].hand)
	card.first.apply_overrides(GameTypes.Context.FALL, card.first.effective_rank(), card.first.effective_suit())
	card.second.apply_overrides(GameTypes.Context.FALL, card.second.effective_rank(), card.second.effective_suit())
	assert_true(controller.submit(_begin(&"begin", ability.copy_id), 10).accepted)

	var committed := controller.submit(_commit(&"commit", {
		"cards": [str(card.card_id)],
	}), 11)

	assert_true(committed.accepted)
	assert_eq(card.first.effective_context(), GameTypes.Context.RISE)
	assert_eq(card.second.effective_context(), GameTypes.Context.RISE)
	assert_false(state.players[&"one"].ability_hand.has(ability))
	assert_eq(state.ability_deck.used_count(), 1)
	assert_true(state.players[&"one"].pending_manipulation.is_empty())
	assert_true(state.players[&"one"].completed_manipulation_ids.has(&"rise_infusion"))
	assert_eq(committed.events.size(), 1)
	if committed.events.size() == 1:
		var event = committed.events[0]
		assert_eq(event.kind, &"manipulation_resolved")
		assert_eq(event.audience, &"player")
		assert_eq(event.recipient_id, &"one")
		assert_eq(event.payload.card_changes.size(), 1)
		assert_eq(event.payload.card_changes[0].before.first.effective_context, GameTypes.Context.FALL)
		assert_eq(event.payload.card_changes[0].after.first.effective_context, GameTypes.Context.RISE)


func test_cancel_and_timeout_keep_uncommitted_ability() -> void:
	var cancelled_state := _state(213)
	var cancelled_controller := MatchController.new(cancelled_state)
	var cancelled_ability = _set_ability(cancelled_state, &"one", &"mirror_rank")
	assert_true(cancelled_controller.submit(_begin(&"begin", cancelled_ability.copy_id), 1).accepted)
	assert_true(cancelled_controller.submit(GameCommand.new(
		&"cancel", &"one", CommandKinds.CANCEL_MANIPULATION
	), 2).accepted)
	assert_true(cancelled_state.players[&"one"].ability_hand.has(cancelled_ability))

	var timed_state := _state(214)
	var timed_controller := MatchController.new(timed_state)
	var timed_ability = _set_ability(timed_state, &"one", &"mirror_rank")
	assert_true(timed_controller.submit(_begin(&"begin", timed_ability.copy_id), 1).accepted)
	timed_controller.tick(5001)
	assert_true(timed_state.players[&"one"].ability_hand.has(timed_ability))
	assert_true(timed_state.players[&"one"].pending_manipulation.is_empty())


func test_commit_after_hand_play_deadline_rejects_without_mutation() -> void:
	var state := _state(221)
	var controller := MatchController.new(state)
	var ability = _set_ability(state, &"one", &"mirror_rank")
	var card: FullCardState = _ordinary_card(state.players[&"one"].hand)
	assert_true(controller.submit(_begin(&"begin-deadline", ability.copy_id), 10).accepted)
	var before := state.to_dict()
	var rng_before := state.rng.state_token()

	var rejected := controller.submit(_commit(&"commit-after-deadline", {
		"cards": [str(card.card_id)],
	}), state.phase_deadline_msec + 1)

	assert_false(rejected.accepted)
	assert_eq(rejected.error_code, &"phase_deadline_passed")
	assert_eq(state.to_dict(), before)
	assert_eq(state.rng.state_token(), rng_before)
	assert_true(state.players[&"one"].ability_hand.has(ability))


func test_locked_or_out_of_phase_manipulation_rejects() -> void:
	var locked_state := _state(215)
	var locked_controller := MatchController.new(locked_state)
	var locked_ability = _set_ability(locked_state, &"one", &"mirror_rank")
	locked_state.players[&"one"].hand_locked = true
	assert_eq(
		locked_controller.submit(_begin(&"locked", locked_ability.copy_id), 1).error_code,
		&"hand_already_locked"
	)

	var phase_state := _state(216)
	var phase_controller := MatchController.new(phase_state)
	var phase_ability = _set_ability(phase_state, &"one", &"mirror_rank")
	phase_state.phase = GameTypes.Phase.MAIN_1
	assert_eq(
		phase_controller.submit(_begin(&"phase", phase_ability.copy_id), 1).error_code,
		&"command_not_allowed_in_phase"
	)


func test_random_effect_skips_joker_but_changes_ordinary_partner_and_consumes() -> void:
	var state := _state(217)
	var card := _mixed_joker_card(&"mixed-random")
	state.players[&"one"].hand[0] = card
	var ability = _set_ability(state, &"one", &"low_roll")
	var probe := RandomSource.new(0)
	probe.restore_state_token(state.rng.state_token())
	var allowed: Array = ability.definition.effect_parameters.ranks
	var expected_rank: int = allowed[probe.pick_index(allowed.size())]
	var expected_rng_token := probe.state_token()
	var controller := MatchController.new(state)
	assert_true(controller.submit(_begin(&"begin-random", ability.copy_id), 10).accepted)

	var committed := controller.submit(_commit(&"commit-random", {
		"cards": [str(card.card_id)],
	}), 11)

	assert_true(committed.accepted)
	assert_true(card.first.is_joker())
	assert_eq(card.first.effective_rank(), 0)
	assert_eq(card.second.effective_rank(), expected_rank)
	assert_ne(card.second.effective_rank(), card.second.base_rank)
	assert_eq(state.rng.state_token(), expected_rng_token)
	assert_false(state.players[&"one"].ability_hand.has(ability))


func test_cycle_direction_is_read_once_and_changes_persist_without_retroactivity() -> void:
	var state := _state(218)
	state.context_direction = GameTypes.ContextDirection.REVERSE
	var card: FullCardState = _ordinary_card(state.players[&"one"].hand)
	var first_before: int = card.first.effective_context()
	var second_before: int = card.second.effective_context()
	var ability = _set_ability(state, &"one", &"ride_the_cycle")
	var controller := MatchController.new(state)
	controller.submit(_begin(&"begin-cycle", ability.copy_id), 10)
	assert_true(controller.submit(_commit(&"commit-cycle", {
		"cards": [str(card.card_id)],
	}), 11).accepted)
	var first_after: int = card.first.effective_context()
	var second_after: int = card.second.effective_context()

	assert_eq(first_after, posmod(first_before - 1, 3))
	assert_eq(second_after, posmod(second_before - 1, 3))
	state.context_direction = GameTypes.ContextDirection.FORWARD
	assert_eq(card.first.effective_context(), first_after)
	assert_eq(card.second.effective_context(), second_after)


func test_cycle_and_mirror_allow_complete_joker_noop_and_consume() -> void:
	for fixture in [
		{"seed": 219, "id": &"ride_the_cycle"},
		{"seed": 220, "id": &"mirror_rank"},
	]:
		var state := _state(fixture.seed)
		var card := _double_joker_card(StringName("double-%s" % fixture.id))
		state.players[&"one"].hand[0] = card
		var ability = _set_ability(state, &"one", fixture.id)
		var controller := MatchController.new(state)
		controller.submit(_begin(StringName("begin-%s" % fixture.id), ability.copy_id), 10)
		var committed := controller.submit(_commit(
			StringName("commit-%s" % fixture.id), {"cards": [str(card.card_id)]}
		), 11)

		assert_true(committed.accepted)
		assert_true(card.first.is_joker())
		assert_true(card.second.is_joker())
		assert_eq(card.first.effective_rank(), 0)
		assert_eq(card.second.effective_rank(), 0)
		assert_false(state.players[&"one"].ability_hand.has(ability))


func _state(seed_value: int) -> MatchState:
	var config := MatchConfig.new(
		[&"one", &"two"], [], GameTypes.VictoryMode.SCORE_RACE, 100,
		GameTypes.InformationVisibility.PUBLIC, {
			GameTypes.Phase.START: 5000,
			GameTypes.Phase.MAIN_1: 5000,
			GameTypes.Phase.HAND_PLAY: 5000,
			GameTypes.Phase.MAIN_2: 5000,
			GameTypes.Phase.END: 2000,
		}, 1000, 5000, 30000, AbilityCatalog.manipulation_definitions()
	)
	var state := MatchState.create(config, seed_value)
	state.phase = GameTypes.Phase.HAND_PLAY
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	return state


func _set_ability(state: MatchState, player_id: StringName, id: StringName):
	var ability = state.players[player_id].ability_hand[0]
	ability.definition = _definition(id)
	return ability


func _definition(id: StringName) -> AbilityDefinition:
	for definition in AbilityCatalog.manipulation_definitions(1):
		if definition.id == id:
			return definition
	return null


func _ordinary_card(hand: Array):
	for card in hand:
		if not card.first.is_joker() and not card.second.is_joker():
			return card
	return null


func _mixed_joker_card(id: StringName) -> FullCardState:
	return FullCardState.new(
		id,
		HalfCardState.new(
			StringName("%s-joker" % id), GameTypes.Context.RISE, 0,
			HalfCardState.NO_SUIT, GameTypes.HalfKind.JOKER
		),
		HalfCardState.new(
			StringName("%s-normal" % id), GameTypes.Context.FLOURISH, 8,
			GameTypes.Suit.CLOUD
		)
	)


func _double_joker_card(id: StringName) -> FullCardState:
	return FullCardState.new(
		id,
		HalfCardState.new(
			StringName("%s-first" % id), GameTypes.Context.RISE, 0,
			HalfCardState.NO_SUIT, GameTypes.HalfKind.JOKER
		),
		HalfCardState.new(
			StringName("%s-second" % id), GameTypes.Context.FLOURISH, 0,
			HalfCardState.NO_SUIT, GameTypes.HalfKind.JOKER
		)
	)


func _begin(id: StringName, copy_id: StringName) -> GameCommand:
	return GameCommand.new(id, &"one", CommandKinds.STAGE_MANIPULATION, {"copy_id": copy_id})


func _commit(id: StringName, choices: Dictionary) -> GameCommand:
	return GameCommand.new(
		id, &"one", CommandKinds.COMMIT_MANIPULATION, {"choices": choices}
	)
