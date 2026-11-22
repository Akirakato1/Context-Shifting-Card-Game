extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const RandomSource = preload("res://src/core/common/random_source.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const ContextPile = preload("res://src/core/cards/context_pile.gd")


func test_context_fixture_contains_ninety_unique_base_cards() -> void:
	var cards := _build_context_cards(GameTypes.Context.RISE)
	var identifiers := {}

	for card in cards:
		identifiers[card.copy_id] = true
		assert_eq(card.base_context, GameTypes.Context.RISE)
		assert_true(card.base_rank >= 1 and card.base_rank <= 10)
		assert_true(card.base_suit >= GameTypes.Suit.MOUNTAIN and card.base_suit <= GameTypes.Suit.SEA)

	assert_eq(cards.size(), 90)
	assert_eq(identifiers.size(), 90)


func test_effective_overrides_do_not_change_base_identity_and_can_reset() -> void:
	var card := HalfCardState.new(&"a-1-0-0", GameTypes.Context.RISE, 1, GameTypes.Suit.MOUNTAIN)

	card.apply_overrides(GameTypes.Context.FALL, 10, GameTypes.Suit.SEA)

	assert_eq(card.base_context, GameTypes.Context.RISE)
	assert_eq(card.base_rank, 1)
	assert_eq(card.base_suit, GameTypes.Suit.MOUNTAIN)
	assert_eq(card.effective_context(), GameTypes.Context.FALL)
	assert_eq(card.effective_rank(), 10)
	assert_eq(card.effective_suit(), GameTypes.Suit.SEA)

	card.reset_effective()

	assert_eq(card.effective_context(), GameTypes.Context.RISE)
	assert_eq(card.effective_rank(), 1)
	assert_eq(card.effective_suit(), GameTypes.Suit.MOUNTAIN)


func test_base_value_validation_rejects_out_of_range_values() -> void:
	assert_false(HalfCardState.is_valid_base(GameTypes.Context.RISE, 0, GameTypes.Suit.MOUNTAIN))
	assert_false(HalfCardState.is_valid_base(GameTypes.Context.RISE, 11, GameTypes.Suit.MOUNTAIN))
	assert_false(HalfCardState.is_valid_base(99, 1, GameTypes.Suit.MOUNTAIN))
	assert_false(HalfCardState.is_valid_base(GameTypes.Context.RISE, 1, 99))
	assert_true(HalfCardState.is_valid_base(GameTypes.Context.FLOURISH, 10, GameTypes.Suit.SEA))


func test_draws_without_replacement_and_recycles_only_after_exhaustion() -> void:
	var first := HalfCardState.new(&"first", GameTypes.Context.RISE, 1, GameTypes.Suit.MOUNTAIN)
	var second := HalfCardState.new(&"second", GameTypes.Context.RISE, 2, GameTypes.Suit.MOUNTAIN)
	var recycled := HalfCardState.new(&"recycled", GameTypes.Context.RISE, 3, GameTypes.Suit.MOUNTAIN)
	var pile := ContextPile.new(GameTypes.Context.RISE, [first, second])
	var rng := RandomSource.new(7)
	pile.discard(recycled)

	var initial_draw := pile.draw(2, rng)

	assert_eq(initial_draw.size(), 2)
	assert_ne(initial_draw[0].copy_id, initial_draw[1].copy_id)
	assert_eq(pile.draw_count(), 0)
	assert_eq(pile.used_count(), 1)

	var recycled_draw := pile.draw(1, rng)

	assert_eq(recycled_draw.size(), 1)
	assert_eq(recycled_draw[0].copy_id, &"recycled")
	assert_eq(pile.draw_count(), 0)
	assert_eq(pile.used_count(), 0)


func test_short_draw_does_not_duplicate_or_fabricate_cards() -> void:
	var only := HalfCardState.new(&"only", GameTypes.Context.FLOURISH, 4, GameTypes.Suit.CLOUD)
	var pile := ContextPile.new(GameTypes.Context.FLOURISH, [only])

	var drawn := pile.draw(3, RandomSource.new(3))
	var drawn_again := pile.draw(1, RandomSource.new(3))

	assert_eq(drawn.size(), 1)
	assert_eq(drawn[0].copy_id, &"only")
	assert_eq(drawn_again, [])
	assert_eq(pile.draw_count(), 0)
	assert_eq(pile.used_count(), 0)


func _build_context_cards(context: int) -> Array:
	var cards: Array = []
	for rank in range(1, 11):
		for suit in range(GameTypes.Suit.MOUNTAIN, GameTypes.Suit.SEA + 1):
			for copy_index in range(3):
				var copy_id := StringName("%d-%d-%d-%d" % [context, rank, suit, copy_index])
				cards.append(HalfCardState.new(copy_id, context, rank, suit))
	return cards
