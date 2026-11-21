extends "res://tests/test_case.gd"

const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const ManipulationResolver = preload("res://src/core/abilities/manipulation_resolver.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const GameTypes = preload("res://src/core/common/game_types.gd")
const RandomSource = preload("res://src/core/common/random_source.gd")


func test_context_exchange_swaps_pre_effect_contexts_and_preserves_rank_suit() -> void:
	var card := _card(&"target")
	card.first.apply_overrides(GameTypes.Context.FALL, 9, GameTypes.Suit.THREE)
	card.second.apply_overrides(GameTypes.Context.RISE, 4, GameTypes.Suit.ONE)
	var definition := _definition(&"context_exchange")
	var choices := {"cards": [str(card.card_id)]}

	assert_eq(ManipulationResolver.validate(definition, [card], choices), &"")
	ManipulationResolver.apply(definition, [card], choices, RandomSource.new(1), 1)

	assert_eq(card.first.effective_context(), GameTypes.Context.RISE)
	assert_eq(card.first.effective_rank(), 9)
	assert_eq(card.first.effective_suit(), GameTypes.Suit.THREE)
	assert_eq(card.second.effective_context(), GameTypes.Context.FALL)
	assert_eq(card.second.effective_rank(), 4)
	assert_eq(card.second.effective_suit(), GameTypes.Suit.ONE)


func test_context_convergence_changes_only_the_selected_half() -> void:
	var card := _card(&"target")
	card.first.apply_overrides(GameTypes.Context.FALL, 7, GameTypes.Suit.THREE)
	card.second.apply_overrides(GameTypes.Context.FLOURISH, 4, GameTypes.Suit.ONE)
	var definition := _definition(&"context_convergence")
	var choices := {"cards": [str(card.card_id)], "half_index": [0]}

	assert_eq(ManipulationResolver.validate(definition, [card], choices), &"")
	ManipulationResolver.apply(definition, [card], choices, RandomSource.new(2), 1)

	assert_eq(card.first.effective_context(), GameTypes.Context.FLOURISH)
	assert_eq(card.first.effective_rank(), 7)
	assert_eq(card.first.effective_suit(), GameTypes.Suit.THREE)
	assert_eq(card.second.effective_context(), GameTypes.Context.FLOURISH)
	assert_eq(card.second.effective_rank(), 4)


func test_suit_imprint_changes_both_ordinary_halves() -> void:
	var card := _card(&"target")
	var definition := _definition(&"suit_imprint")
	var choices := {"cards": [str(card.card_id)], "suit": [GameTypes.Suit.THREE]}

	assert_eq(ManipulationResolver.validate(definition, [card], choices), &"")
	ManipulationResolver.apply(definition, [card], choices, RandomSource.new(3), 1)

	assert_eq(card.first.effective_suit(), GameTypes.Suit.THREE)
	assert_eq(card.second.effective_suit(), GameTypes.Suit.THREE)
	assert_eq(card.first.effective_context(), GameTypes.Context.RISE)
	assert_eq(card.second.effective_context(), GameTypes.Context.FLOURISH)


func test_fixed_context_infusions_change_both_ordinary_halves() -> void:
	var expected := {
		&"rise_infusion": GameTypes.Context.RISE,
		&"flourish_infusion": GameTypes.Context.FLOURISH,
		&"fall_infusion": GameTypes.Context.FALL,
	}
	for id in expected:
		var card := _card(StringName("target-%s" % id))
		var definition := _definition(id)
		var choices := {"cards": [str(card.card_id)]}
		assert_eq(ManipulationResolver.validate(definition, [card], choices), &"")
		ManipulationResolver.apply(definition, [card], choices, RandomSource.new(4), 1)
		assert_eq(card.first.effective_context(), expected[id])
		assert_eq(card.second.effective_context(), expected[id])


func test_deterministic_operations_skip_jokers_and_valid_noop_still_resolves() -> void:
	var joker := HalfCardState.new(
		&"joker", GameTypes.Context.RISE, 0, HalfCardState.NO_SUIT,
		GameTypes.HalfKind.JOKER
	)
	var normal := HalfCardState.new(
		&"normal", GameTypes.Context.FLOURISH, 8, GameTypes.Suit.TWO
	)
	var mixed := FullCardState.new(&"mixed", joker, normal)
	var exchange := _definition(&"context_exchange")
	var choices := {"cards": [str(mixed.card_id)]}

	assert_eq(ManipulationResolver.validate(exchange, [mixed], choices), &"")
	ManipulationResolver.apply(exchange, [mixed], choices, RandomSource.new(5), 1)
	assert_true(joker.is_joker())
	assert_eq(normal.effective_context(), GameTypes.Context.FLOURISH)

	var infusion := _definition(&"fall_infusion")
	ManipulationResolver.apply(infusion, [mixed], choices, RandomSource.new(6), 1)
	assert_eq(joker.effective_rank(), 0)
	assert_eq(normal.effective_context(), GameTypes.Context.FALL)


func test_context_roulette_rolls_each_selected_ordinary_half_independently() -> void:
	var selected := _card(&"selected")
	var untouched := _card(&"untouched")
	var choices := {"halves": [
		{"card_id": str(selected.card_id), "half_index": 0},
		{"card_id": str(selected.card_id), "half_index": 1},
	]}
	var expected_rng := RandomSource.new(301)
	var expected_first := expected_rng.pick_index(3)
	var expected_second := expected_rng.pick_index(3)
	var untouched_context := untouched.first.effective_context()

	ManipulationResolver.apply(
		_definition(&"context_roulette"), [selected, untouched], choices,
		RandomSource.new(301), GameTypes.ContextDirection.FORWARD
	)

	assert_eq(selected.first.effective_context(), expected_first)
	assert_eq(selected.second.effective_context(), expected_second)
	assert_eq(untouched.first.effective_context(), untouched_context)
	assert_eq(selected.first.effective_rank(), 2)
	assert_eq(selected.second.effective_suit(), GameTypes.Suit.TWO)


func test_rank_rolls_use_exact_low_high_even_and_odd_sets() -> void:
	var allowed_by_id := {
		&"low_roll": [1, 2, 3, 4, 5],
		&"high_roll": [6, 7, 8, 9, 10],
		&"even_roll": [2, 4, 6, 8, 10],
		&"odd_roll": [1, 3, 5, 7, 9],
	}
	var seed_value := 310
	for id in allowed_by_id:
		var card := _card(StringName("rank-%s" % id))
		ManipulationResolver.apply(
			_definition(id), [card], {"cards": [str(card.card_id)]},
			RandomSource.new(seed_value), GameTypes.ContextDirection.FORWARD
		)
		assert_true(card.first.effective_rank() in allowed_by_id[id])
		assert_true(card.second.effective_rank() in allowed_by_id[id])
		assert_eq(card.first.effective_context(), GameTypes.Context.RISE)
		assert_eq(card.second.effective_suit(), GameTypes.Suit.TWO)
		seed_value += 1


func test_random_roll_may_equal_the_current_value() -> void:
	var card := _card(&"same-value")
	var allowed: Array = _definition(&"low_roll").effect_parameters.ranks
	var probe := RandomSource.new(321)
	var rolled_rank: int = allowed[probe.pick_index(allowed.size())]
	card.first.apply_overrides(
		card.first.effective_context(), rolled_rank, card.first.effective_suit()
	)

	ManipulationResolver.apply(
		_definition(&"low_roll"), [card], {"cards": [str(card.card_id)]},
		RandomSource.new(321), GameTypes.ContextDirection.FORWARD
	)

	assert_eq(card.first.effective_rank(), rolled_rank)


func test_ride_and_against_cycle_follow_normal_and_reversed_direction() -> void:
	for direction in [GameTypes.ContextDirection.FORWARD, GameTypes.ContextDirection.REVERSE]:
		for fixture in [
			{"id": &"ride_the_cycle", "delta": 1},
			{"id": &"against_the_cycle", "delta": -1},
		]:
			var card := _card(StringName("cycle-%s-%d" % [fixture.id, direction]))
			var first_before := card.first.effective_context()
			var second_before := card.second.effective_context()
			ManipulationResolver.apply(
				_definition(fixture.id), [card], {"cards": [str(card.card_id)]},
				RandomSource.new(330), direction
			)
			assert_eq(
				card.first.effective_context(),
				posmod(first_before + direction * fixture.delta, 3)
			)
			assert_eq(
				card.second.effective_context(),
				posmod(second_before + direction * fixture.delta, 3)
			)


func test_mirror_rank_maps_all_five_pairs_on_both_halves() -> void:
	for low_rank in range(1, 6):
		var high_rank := 11 - low_rank
		var card := _card(StringName("mirror-%d" % low_rank))
		card.first.apply_overrides(
			card.first.effective_context(), low_rank, card.first.effective_suit()
		)
		card.second.apply_overrides(
			card.second.effective_context(), high_rank, card.second.effective_suit()
		)
		ManipulationResolver.apply(
			_definition(&"mirror_rank"), [card], {"cards": [str(card.card_id)]},
			RandomSource.new(340), GameTypes.ContextDirection.FORWARD
		)
		assert_eq(card.first.effective_rank(), high_rank)
		assert_eq(card.second.effective_rank(), low_rank)


func _definition(id: StringName) -> AbilityDefinition:
	for definition in AbilityCatalog.manipulation_definitions(1):
		if definition.id == id:
			return definition
	return null


func _card(id: StringName) -> FullCardState:
	return FullCardState.new(
		id,
		HalfCardState.new(
			StringName("%s-first" % id), GameTypes.Context.RISE, 2, GameTypes.Suit.ONE
		),
		HalfCardState.new(
			StringName("%s-second" % id), GameTypes.Context.FLOURISH, 6, GameTypes.Suit.TWO
		)
	)
