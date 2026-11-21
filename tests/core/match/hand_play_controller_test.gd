extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")
const ContextHandDefinition = preload("res://src/core/scoring/context_hand_definition.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const EventKinds = preload("res://src/core/events/event_kinds.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")


func test_incomplete_manipulation_cancels_but_completed_choice_is_irreversible() -> void:
	var state := _hand_play_state(41)
	_set_manipulation(state, &"one", 0, &"rise_infusion")
	var ability = state.players[&"one"].ability_hand[0]
	var card = _ordinary_card(state.players[&"one"].hand)
	card.first.apply_overrides(GameTypes.Context.FALL, card.first.effective_rank(), card.first.effective_suit())
	card.second.apply_overrides(GameTypes.Context.FALL, card.second.effective_rank(), card.second.effective_suit())
	var controller := MatchController.new(state)

	assert_true(controller.submit(_begin(&"begin", &"one", ability.copy_id), 10).accepted)
	assert_true(controller.submit(GameCommand.new(
		&"cancel", &"one", CommandKinds.CANCEL_MANIPULATION
	), 11).accepted)
	assert_true(state.players[&"one"].ability_hand.has(ability))
	assert_eq(card.first.effective_rank(), card.first.base_rank)

	controller.submit(_begin(&"begin-again", &"one", ability.copy_id), 12)
	var committed := controller.submit(GameCommand.new(
		&"commit", &"one", CommandKinds.COMMIT_MANIPULATION, {
			"choices": {"cards": [str(card.card_id)]},
		}
	), 13)
	assert_true(committed.accepted)
	assert_eq(card.first.effective_context(), GameTypes.Context.RISE)
	assert_eq(card.second.effective_context(), GameTypes.Context.RISE)
	assert_false(state.players[&"one"].ability_hand.has(ability))
	assert_eq(controller.submit(GameCommand.new(
		&"too-late", &"one", CommandKinds.CANCEL_MANIPULATION
	), 14).error_code, &"no_pending_manipulation")
	assert_eq(card.first.effective_context(), GameTypes.Context.RISE)


func test_spent_manipulation_remains_spent_on_pass_and_unplayed_card_keeps_override() -> void:
	var state := _hand_play_state(42)
	_set_manipulation(state, &"one", 0, &"rise_infusion")
	var ability = state.players[&"one"].ability_hand[0]
	var modified_card = _ordinary_card(state.players[&"one"].hand)
	modified_card.first.apply_overrides(GameTypes.Context.FALL, modified_card.first.effective_rank(), modified_card.first.effective_suit())
	modified_card.second.apply_overrides(GameTypes.Context.FALL, modified_card.second.effective_rank(), modified_card.second.effective_suit())
	var controller := MatchController.new(state)
	controller.submit(_begin(&"begin", &"one", ability.copy_id), 1)
	controller.submit(GameCommand.new(
		&"commit", &"one", CommandKinds.COMMIT_MANIPULATION, {
			"choices": {"cards": [str(modified_card.card_id)]},
		}
	), 2)

	controller.submit(_stage(&"pass-one", &"one", []), 3)
	controller.submit(_stage(&"pass-two", &"two", []), 3)
	controller.submit(_lock(&"lock-one", &"one"), 4)
	controller.submit(_lock(&"lock-two", &"two"), 4)

	assert_false(state.players[&"one"].ability_hand.has(ability))
	assert_eq(state.players[&"one"].submitted_cards.size(), 0)
	assert_eq(modified_card.first.effective_context(), GameTypes.Context.RISE)
	assert_eq(modified_card.second.effective_context(), GameTypes.Context.RISE)


func test_submission_requires_eligible_cards_and_explicit_double_active_choice() -> void:
	var state := _hand_play_state(43)
	var controller := MatchController.new(state)
	var ineligible = _card_without_context(state.players[&"one"].hand, state.active_context)
	var rejected := controller.submit(_stage(
		&"bad", &"one", [{"card_id": ineligible.card_id, "half_index": 0}]
	), 1)
	assert_eq(rejected.error_code, &"card_not_eligible")

	var eligible = _card_with_context(state.players[&"one"].hand, state.active_context)
	eligible.first.apply_overrides(state.active_context, eligible.first.effective_rank(), eligible.first.effective_suit())
	eligible.second.apply_overrides(state.active_context, eligible.second.effective_rank(), eligible.second.effective_suit())
	var missing_choice := controller.submit(GameCommand.new(
		&"missing-choice", &"one", CommandKinds.STAGE_HAND,
		{"cards": [{"card_id": eligible.card_id}]}
	), 2)
	assert_eq(missing_choice.error_code, &"half_choice_required")
	assert_true(controller.submit(_stage(
		&"chosen", &"one", [{"card_id": eligible.card_id, "half_index": 1}]
	), 3).accepted)


func test_zero_to_six_cards_are_legal_when_every_card_is_eligible() -> void:
	var state := _hand_play_state(44)
	var selected_indexes := {}
	for card in state.players[&"one"].hand:
		var half_index := 0 if not card.first.is_joker() else 1
		var half = card.half_at(half_index)
		assert_false(half.is_joker(), "fixture needs one normal half on every selected card")
		half.apply_overrides(
			state.active_context, half.effective_rank(), half.effective_suit()
		)
		selected_indexes[card.card_id] = half_index
	var controller := MatchController.new(state)
	assert_true(controller.submit(_stage(&"pass", &"two", []), 1).accepted)
	var all_cards: Array = []
	for card in state.players[&"one"].hand:
		var joker_choices: Array = []
		for half_index in range(2):
			if card.half_at(half_index).is_joker():
				joker_choices.append({
					"half_index": half_index,
					"context": GameTypes.Context.RISE,
					"suit": GameTypes.Suit.ONE,
				})
		all_cards.append({
			"card_id": card.card_id,
			"half_index": selected_indexes[card.card_id],
			"joker_choices": joker_choices,
		})
	assert_eq(all_cards.size(), 6)
	assert_true(controller.submit(_stage(&"six", &"one", all_cards), 2).accepted)
	all_cards.append(all_cards[0])
	assert_eq(controller.submit(_stage(
		&"seven", &"one", all_cards
	), 3).error_code, &"submission_size_out_of_range")


func test_timeout_locks_valid_staging_cancels_incomplete_targeting_and_defaults_to_pass() -> void:
	var state := _hand_play_state(45)
	_set_manipulation(state, &"two", 0, &"mirror_rank")
	var staged_card = _card_with_context(state.players[&"one"].hand, state.active_context)
	var controller := MatchController.new(state)
	controller.tick(0)
	controller.submit(_stage(
		&"stage-one", &"one", [{"card_id": staged_card.card_id, "half_index": _active_half(staged_card, state.active_context)}]
	), 10)
	controller.submit(_begin(
		&"begin-two", &"two", state.players[&"two"].ability_hand[0].copy_id
	), 11)

	controller.tick(5001)

	assert_eq(state.phase, GameTypes.Phase.MAIN_2)
	assert_eq(state.players[&"one"].submitted_cards.size(), 1)
	assert_eq(state.players[&"two"].submitted_cards.size(), 0)
	assert_true(state.players[&"two"].pending_manipulation.is_empty())
	assert_eq(state.players[&"two"].ability_hand.size(), 2)


func test_reveal_scores_all_submitted_cards_and_sanitizes_manipulation_history() -> void:
	var state := _hand_play_state(46)
	var selected := _three_active_cards(state.players[&"one"].hand, state.active_context)
	var ranks := [3, 8, 9]
	for index in range(selected.size()):
		var half_index := _active_half(selected[index], state.active_context)
		var half = selected[index].first if half_index == 0 else selected[index].second
		half.apply_overrides(state.active_context, ranks[index], half.effective_suit())
	_set_manipulation(state, &"one", 0, &"suit_imprint")
	var ability = state.players[&"one"].ability_hand[0]
	var controller := MatchController.new(state)
	controller.submit(_begin(&"begin", &"one", ability.copy_id), 1)
	controller.submit(GameCommand.new(
		&"commit", &"one", CommandKinds.COMMIT_MANIPULATION, {
			"choices": {
				"cards": [str(selected[0].card_id)],
				"suit": [GameTypes.Suit.THREE],
			},
		}
	), 2)
	var staged: Array = []
	for card in selected:
		staged.append({"card_id": card.card_id, "half_index": _active_half(card, state.active_context)})
	controller.submit(_stage(&"stage-one", &"one", staged), 3)
	controller.submit(_stage(&"pass-two", &"two", []), 3)
	controller.submit(_lock(&"lock-one", &"one"), 4)
	var resolved := controller.submit(_lock(&"lock-two", &"two"), 4)

	assert_eq(state.players[&"one"].submitted_faces.size(), 3)
	assert_eq(state.players[&"one"].provisional_score.base_value, 20)
	assert_eq(state.players[&"one"].locked_normal.category_id, &"high_card")
	assert_true(state.players[&"one"].locked_context.category_id != &"no_context")
	var public_reveal = _player_event(resolved.events, EventKinds.HAND_REVEALED, &"one", &"public")
	assert_true(public_reveal.payload.manipulation_ability_ids.has("suit_imprint"))
	assert_false(public_reveal.payload.has("manipulation_targets"))
	assert_false(public_reveal.payload.has("change_history"))
	assert_eq(public_reveal.payload.base_value, 20)


func _hand_play_state(seed_value: int) -> MatchState:
	var abilities: Array[AbilityDefinition] = []
	for index in range(12): abilities.append(AbilityDefinition.new(
		StringName("base-%d" % index), AbilityDefinition.Timing.HAND_SHAPE, [], &"noop"
	))
	var normal_definitions: Array[NormalHandDefinition] = [
		NormalHandDefinition.new(&"high_card", 10, 1, &"high_card", Rational.new(1, 1)),
		NormalHandDefinition.new(&"pair", 20, 2, &"pair", Rational.new(2, 1)),
	]
	var context_definitions: Array[ContextHandDefinition] = [
		ContextHandDefinition.new(
			&"any_pair", 10, {GameTypes.Context.RISE: 1, GameTypes.Context.FLOURISH: 1}, Rational.new(2, 1)
		),
		ContextHandDefinition.new(
			&"abc", 20, {GameTypes.Context.RISE: 1, GameTypes.Context.FLOURISH: 1, GameTypes.Context.FALL: 1}, Rational.new(2, 1)
		),
	]
	var config := MatchConfig.new(
		[&"one", &"two"], [], GameTypes.VictoryMode.SCORE_RACE, 100,
		GameTypes.InformationVisibility.PUBLIC,
		{GameTypes.Phase.START: 5000, GameTypes.Phase.MAIN_1: 5000,
		GameTypes.Phase.HAND_PLAY: 5000, GameTypes.Phase.MAIN_2: 5000,
		GameTypes.Phase.END: 2000}, 1000, 5000, 30000, abilities,
		normal_definitions, context_definitions
	)
	var state := MatchState.create(config, seed_value)
	state.phase = GameTypes.Phase.HAND_PLAY
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	return state


func _set_manipulation(state: MatchState, player_id: StringName, index: int, id: StringName) -> void:
	for definition in AbilityCatalog.manipulation_definitions(1):
		if definition.id == id:
			state.players[player_id].ability_hand[index].definition = definition
			return
	assert(false, "unknown manipulation fixture: %s" % id)


func _begin(id: StringName, player_id: StringName, copy_id: StringName) -> GameCommand:
	return GameCommand.new(id, player_id, CommandKinds.STAGE_MANIPULATION, {"copy_id": copy_id})


func _stage(id: StringName, player_id: StringName, cards: Array) -> GameCommand:
	return GameCommand.new(id, player_id, CommandKinds.STAGE_HAND, {"cards": cards})


func _lock(id: StringName, player_id: StringName) -> GameCommand:
	return GameCommand.new(id, player_id, CommandKinds.LOCK_HAND)


func _card_without_context(hand: Array, context: int):
	for card in hand:
		if card.eligible_half_indexes(context).is_empty(): return card
	return null


func _card_with_context(hand: Array, context: int):
	for card in hand:
		if not card.eligible_half_indexes(context).is_empty(): return card
	return null


func _ordinary_card(hand: Array):
	for card in hand:
		if not card.first.is_joker() and not card.second.is_joker():
			return card
	return null


func _three_active_cards(hand: Array, context: int) -> Array:
	var result: Array = []
	for card in hand:
		if not card.eligible_half_indexes(context).is_empty(): result.append(card)
		if result.size() == 3: break
	return result


func _active_half(card, context: int) -> int:
	return card.eligible_half_indexes(context)[0]


func _player_event(events: Array, kind: StringName, player_id: StringName, audience: StringName):
	for event in events:
		if event.kind == kind and event.audience == audience and event.payload.player_id == str(player_id):
			return event
	return null
