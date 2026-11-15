extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const RandomSource = preload("res://src/core/common/random_source.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const ContextPile = preload("res://src/core/cards/context_pile.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const CardFactory = preload("res://src/core/cards/card_factory.gd")


func test_opening_hand_draws_four_of_each_context_in_fixed_pair_shape() -> void:
	var piles := _build_piles(12)
	var hand: Array[FullCardState] = CardFactory.build_opening_hand(piles, RandomSource.new(41))

	assert_eq(hand.size(), 6)
	assert_eq(_half_context_counts(hand), {
		GameTypes.Context.A: 4,
		GameTypes.Context.B: 4,
		GameTypes.Context.C: 4,
	})
	assert_eq(_pair_shape_counts(hand), {&"ab": 2, &"ac": 2, &"bc": 2})
	assert_eq(_unique_card_ids(hand), 6)


func test_full_card_exposes_eligible_effective_halves_and_resets_them() -> void:
	var first := HalfCardState.new(&"a", GameTypes.Context.A, 1, GameTypes.Suit.ONE)
	var second := HalfCardState.new(&"b", GameTypes.Context.B, 2, GameTypes.Suit.TWO)
	var card := FullCardState.new(&"full:a+b", first, second)

	assert_eq(card.half_at(0), first)
	assert_eq(card.half_at(1), second)
	assert_eq(card.eligible_half_indexes(GameTypes.Context.A), PackedInt32Array([0]))
	assert_eq(card.eligible_half_indexes(GameTypes.Context.C), PackedInt32Array())

	second.apply_overrides(GameTypes.Context.A, 10, GameTypes.Suit.THREE)
	assert_eq(card.eligible_half_indexes(GameTypes.Context.A), PackedInt32Array([0, 1]))

	card.reset_effective()
	assert_eq(second.effective_context(), GameTypes.Context.B)
	assert_eq(second.effective_rank(), 2)
	assert_eq(second.effective_suit(), GameTypes.Suit.TWO)


func test_replenishment_pairs_one_shuffled_pool_and_can_make_same_context_cards() -> void:
	var found_same_context_pair := false
	for seed_value in range(1, 30):
		var request := {
			GameTypes.Context.A: 2,
			GameTypes.Context.B: 2,
			GameTypes.Context.C: 2,
		}
		var hand: Array[FullCardState] = CardFactory.draw_replenishment(
			_build_piles(6), request, RandomSource.new(seed_value)
		)
		assert_eq(hand.size(), 3)
		assert_eq(_half_context_counts(hand), request)
		assert_eq(_unique_card_ids(hand), 3)
		for card in hand:
			if card.first.effective_context() == card.second.effective_context():
				found_same_context_pair = true
	assert_true(found_same_context_pair, "later replenishment must permit AA/BB/CC pairings")


func test_card_ids_are_stable_for_the_same_seed_and_unique_within_a_draw() -> void:
	var request := {
		GameTypes.Context.A: 3,
		GameTypes.Context.B: 2,
		GameTypes.Context.C: 1,
	}
	var first: Array[FullCardState] = CardFactory.draw_replenishment(
		_build_piles(6), request, RandomSource.new(998)
	)
	var second: Array[FullCardState] = CardFactory.draw_replenishment(
		_build_piles(6), request, RandomSource.new(998)
	)

	assert_eq(_card_ids(first), _card_ids(second))
	assert_eq(_unique_card_ids(first), first.size())


func test_complete_request_preserves_choices_and_fills_only_missing_slots() -> void:
	var result := CardFactory.complete_request(
		{GameTypes.Context.A: 3, GameTypes.Context.C: 1},
		8,
		RandomSource.new(72)
	)

	assert_true(result.ok)
	assert_eq(result.error, &"")
	assert_eq(result.request[GameTypes.Context.A], 3)
	assert_eq(result.request[GameTypes.Context.C], 1)
	assert_eq(_request_total(result.request), 8)
	for count in result.request.values():
		assert_true(count >= 0 and count <= 5)


func test_complete_request_reports_stable_validation_errors() -> void:
	_assert_request_error({GameTypes.Context.A: 1}, 3, &"odd_needed_half_count")
	_assert_request_error({GameTypes.Context.A: 3}, 2, &"request_exceeds_needed_halves")
	_assert_request_error({GameTypes.Context.A: -1}, 2, &"negative_context_count")
	_assert_request_error({GameTypes.Context.A: 6}, 6, &"context_count_exceeds_cap")
	_assert_request_error({99: 2}, 2, &"unknown_context")


func test_replenishment_rejects_invalid_or_incomplete_requests_before_drawing() -> void:
	var piles := _build_piles(6)
	var invalid := {GameTypes.Context.A: 2, GameTypes.Context.B: 1}

	var cards: Array[FullCardState] = CardFactory.draw_replenishment(
		piles, invalid, RandomSource.new(12)
	)

	assert_eq(cards.size(), 0)
	assert_eq(piles[GameTypes.Context.A].draw_count(), 6)
	assert_eq(piles[GameTypes.Context.B].draw_count(), 6)
	assert_eq(piles[GameTypes.Context.C].draw_count(), 6)


func _assert_request_error(partial: Dictionary, needed_halves: int, expected: StringName) -> void:
	var result := CardFactory.complete_request(partial, needed_halves, RandomSource.new(1))
	assert_false(result.ok)
	assert_eq(result.error, expected)
	assert_eq(result.request, {})


func _build_piles(cards_per_context: int) -> Dictionary:
	var piles := {}
	for context in range(GameTypes.Context.A, GameTypes.Context.C + 1):
		var cards: Array[HalfCardState] = []
		for index in range(cards_per_context):
			var rank := (index % 10) + 1
			var suit := index % 3
			var copy_id := StringName("%d-%02d" % [context, index])
			cards.append(HalfCardState.new(copy_id, context, rank, suit))
		piles[context] = ContextPile.new(context, cards)
	return piles


func _half_context_counts(hand: Array[FullCardState]) -> Dictionary:
	var counts := {
		GameTypes.Context.A: 0,
		GameTypes.Context.B: 0,
		GameTypes.Context.C: 0,
	}
	for card in hand:
		counts[card.first.effective_context()] += 1
		counts[card.second.effective_context()] += 1
	return counts


func _pair_shape_counts(hand: Array[FullCardState]) -> Dictionary:
	var counts := {&"ab": 0, &"ac": 0, &"bc": 0}
	for card in hand:
		var contexts := [card.first.base_context, card.second.base_context]
		contexts.sort()
		var key := StringName("%s%s" % [char(97 + contexts[0]), char(97 + contexts[1])])
		counts[key] += 1
	return counts


func _card_ids(hand: Array[FullCardState]) -> Array[StringName]:
	var result: Array[StringName] = []
	for card in hand:
		result.append(card.card_id)
	return result


func _unique_card_ids(hand: Array[FullCardState]) -> int:
	var identifiers := {}
	for card in hand:
		identifiers[card.card_id] = true
	return identifiers.size()


func _request_total(request: Dictionary) -> int:
	var total := 0
	for count in request.values():
		total += count
	return total
