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
