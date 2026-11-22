extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")


func test_shift_is_consumed_immediately_without_active_field() -> void:
	var state := _main_one_state(801)
	_set_ability(state, &"one", 0, _field_definition(&"shift_to_flourish"))
	var controller := MatchController.new(state)
	controller.tick(0)
	var used_before := state.ability_deck.used_count()
	var ability = state.players[&"one"].ability_hand[0]

	var result := controller.submit(_play(&"shift", &"one", ability.copy_id), 10)

	assert_true(result.accepted)
	assert_eq(state.active_context, GameTypes.Context.FLOURISH)
	assert_eq(state.ability_deck.active_fields().size(), 0)
	assert_eq(state.ability_deck.used_count(), used_before + 1)


func test_resonance_keeps_clock_at_rise_and_allows_flourish_submission() -> void:
	var state := _main_one_state(802)
	_set_ability(state, &"one", 0, _field_definition(&"flourish_resonance"))
	var controller := MatchController.new(state)
	controller.tick(0)
	var ability = state.players[&"one"].ability_hand[0]
	assert_true(controller.submit(_play(&"resonance", &"one", ability.copy_id), 10).accepted)
	assert_eq(state.active_context, GameTypes.Context.RISE)
	assert_eq(state.ability_deck.active_fields().size(), 1)

	state.phase = GameTypes.Phase.HAND_PLAY
	var card = _ordinary_card(state.players[&"one"].hand)
	card.first.apply_overrides(GameTypes.Context.FLOURISH, 4, card.first.effective_suit())
	card.second.apply_overrides(GameTypes.Context.FLOURISH, 7, card.second.effective_suit())
	var staged := controller.submit(GameCommand.new(
		&"stage", &"one", CommandKinds.STAGE_HAND,
		{"cards": [{"card_id": card.card_id, "half_index": 0, "joker_choices": []}]}
	), 11)

	assert_true(staged.accepted)
	assert_true(state.players[&"one"].has_staged_submission)


func test_reverse_cycle_is_persistent_and_newest_conflict_replaces_once() -> void:
	var state := _main_one_state(803)
	var reverse := _field_definition(&"reverse_cycle")
	_set_ability(state, &"one", 0, reverse)
	_set_ability(state, &"one", 1, reverse)
	var controller := MatchController.new(state)
	controller.tick(0)
	var first = state.players[&"one"].ability_hand[0]
	assert_true(controller.submit(_play(&"reverse-one", &"one", first.copy_id), 10).accepted)
	assert_eq(state.context_direction, GameTypes.ContextDirection.REVERSE)
	assert_eq(state.ability_deck.active_fields().size(), 1)
	for _tick in range(5):
		assert_eq(state.ability_deck.tick_fields_end().size(), 0)
	var second = state.players[&"one"].ability_hand[0]
	var result := controller.submit(_play(&"reverse-two", &"one", second.copy_id), 20)
	assert_true(result.accepted)
	assert_eq(state.context_direction, GameTypes.ContextDirection.FORWARD)
	assert_eq(state.ability_deck.active_fields().size(), 1)
	assert_eq(state.ability_deck.active_fields()[0].ability.copy_id, second.copy_id)


func test_malformed_field_rule_rejects_before_card_leaves_hand() -> void:
	var state := _main_one_state(804)
	var malformed := AbilityDefinition.new(
		&"malformed_field", AbilityDefinition.Timing.FIELD, [&"field"],
		&"field_rule", 3, &"", {
			"field_rule": &"per_selected_rank_set", "ranks": [2, 2],
			"numerator": 1, "denominator": 10,
		}
	)
	_set_ability(state, &"one", 0, malformed)
	var controller := MatchController.new(state)
	controller.tick(0)
	var ability = state.players[&"one"].ability_hand[0]

	var result := controller.submit(_play(&"malformed", &"one", ability.copy_id), 10)

	assert_false(result.accepted)
	assert_eq(result.error_code, &"invalid_field_ranks")
	assert_true(ability in state.players[&"one"].ability_hand)
	assert_eq(state.ability_deck.active_fields().size(), 0)


func _main_one_state(seed_value: int) -> MatchState:
	var definitions: Array[AbilityDefinition] = []
	definitions.assign(AbilityCatalog.build_deck(AbilityCatalog.provisional_deck_recipe()))
	var config := MatchConfig.new(
		[&"one", &"two"], [], GameTypes.VictoryMode.SCORE_RACE, 20,
		GameTypes.InformationVisibility.PUBLIC,
		{GameTypes.Phase.START: 5000, GameTypes.Phase.MAIN_1: 5000,
		GameTypes.Phase.HAND_PLAY: 5000, GameTypes.Phase.MAIN_2: 5000,
		GameTypes.Phase.END: 2000},
		1000, 5000, 30000, definitions,
		[NormalHandDefinition.new(&"high_card", 10, 1, &"high_card", Rational.new(1, 1))], []
	)
	var state := MatchState.create(config, seed_value)
	state.phase = GameTypes.Phase.MAIN_1
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	return state


func _field_definition(id: StringName) -> AbilityDefinition:
	for definition in AbilityCatalog.field_designs():
		if definition.id == id:
			return definition
	assert(false, "unknown field definition")
	return null


func _set_ability(state: MatchState, player_id: StringName, index: int, definition: AbilityDefinition) -> void:
	state.players[player_id].ability_hand[index].definition = definition


func _play(id: StringName, player_id: StringName, copy_id: StringName) -> GameCommand:
	return GameCommand.new(id, player_id, CommandKinds.PLAY_PUBLIC_ABILITY, {
		"copy_id": copy_id, "target_player_id": &"", "choices": {},
	})


func _ordinary_card(hand: Array):
	for card in hand:
		if not card.first.is_joker() and not card.second.is_joker():
			return card
	assert(false, "fixture needs a non-Joker card")
	return null
