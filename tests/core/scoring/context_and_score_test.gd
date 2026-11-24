extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")
const ContextHandDefinition = preload("res://src/core/scoring/context_hand_definition.gd")
const ContextHandEvaluator = preload("res://src/core/scoring/context_hand_evaluator.gd")
const ScoreCalculator = preload("res://src/core/scoring/score_calculator.gd")


func test_rational_arithmetic_comparison_zero_floor_and_ceiling_are_exact() -> void:
	var one_half := Rational.new(1, 2)
	var one_third := Rational.new(1, 3)
	var negative := Rational.new(-5, 4)

	assert_true(one_half.added(one_third).equals(Rational.new(5, 6)))
	assert_true(one_half.multiplied(Rational.new(6, 5)).equals(Rational.new(3, 5)))
	assert_eq(one_half.compare_to(one_third), 1)
	assert_eq(one_third.compare_to(one_half), -1)
	assert_eq(one_half.compare_to(Rational.new(2, 4)), 0)
	assert_true(negative.clamped_to_zero().equals(Rational.new(0, 1)))
	assert_eq(Rational.new(8, 3).ceiling(), 3)
	assert_eq(Rational.new(-8, 3).ceiling(), -2)


func test_inclusive_context_thresholds_lock_only_the_highest_priority_match() -> void:
	var cards: Array[FullCardState] = [
		_card(&"one", GameTypes.Context.RISE, GameTypes.Context.FLOURISH),
		_card(&"two", GameTypes.Context.RISE, GameTypes.Context.FLOURISH),
		_card(&"three", GameTypes.Context.RISE, GameTypes.Context.FALL),
		_card(&"four", GameTypes.Context.RISE, GameTypes.Context.FLOURISH),
	]
	var definitions: Array[ContextHandDefinition] = [
		ContextHandDefinition.new(
			&"all_contexts_1", 10,
			{GameTypes.Context.RISE: 1, GameTypes.Context.FLOURISH: 1, GameTypes.Context.FALL: 1},
			Rational.new(3, 2)
		),
		ContextHandDefinition.new(
			&"ab_3", 20,
			{GameTypes.Context.RISE: 3, GameTypes.Context.FLOURISH: 3},
			Rational.new(2, 1)
		),
	]

	var result := ContextHandEvaluator.evaluate(cards, definitions)

	assert_eq(result.category_id, &"ab_3")
	assert_eq(result.priority, 20)
	assert_true(result.multiplier.equals(Rational.new(2, 1)))
	assert_eq(result.counts[GameTypes.Context.RISE], 4)
	assert_eq(result.counts[GameTypes.Context.FLOURISH], 3)
	assert_eq(result.counts[GameTypes.Context.FALL], 1)


func test_context_evaluator_returns_neutral_fallback_when_no_threshold_matches() -> void:
	var definitions: Array[ContextHandDefinition] = [
		ContextHandDefinition.new(
			&"ab_3", 20,
			{GameTypes.Context.RISE: 3, GameTypes.Context.FLOURISH: 3},
			Rational.new(2, 1)
		),
	]
	var cards: Array[FullCardState] = [
		_card(&"single", GameTypes.Context.RISE, GameTypes.Context.FLOURISH),
	]

	var result := ContextHandEvaluator.evaluate(cards, definitions)

	assert_eq(result.category_id, &"no_context")
	assert_eq(result.priority, -1)
	assert_true(result.multiplier.equals(Rational.new(1, 1)))


func test_context_evaluator_accepts_resolved_contexts_without_card_mutation() -> void:
	var definitions: Array[ContextHandDefinition] = [
		ContextHandDefinition.new(
			&"all_contexts_1", 10,
			{GameTypes.Context.RISE: 1, GameTypes.Context.FLOURISH: 1, GameTypes.Context.FALL: 1},
			Rational.new(2, 1)
		),
	]
	var result := ContextHandEvaluator.evaluate_contexts(
		PackedInt32Array([
			GameTypes.Context.RISE,
			GameTypes.Context.FLOURISH,
			GameTypes.Context.FALL,
			GameTypes.Context.FALL,
		]),
		definitions
	)

	assert_eq(result.category_id, &"all_contexts_1")
	assert_eq(result.counts[GameTypes.Context.RISE], 1)
	assert_eq(result.counts[GameTypes.Context.FLOURISH], 1)
	assert_eq(result.counts[GameTypes.Context.FALL], 2)


func test_context_result_uses_selected_definition_broad_category() -> void:
	var definitions: Array[ContextHandDefinition] = [ContextHandDefinition.new(
		&"all_three", 20, {0: 1, 1: 1, 2: 1}, Rational.new(3, 1), &"three_context"
	)]
	var result := ContextHandEvaluator.evaluate_contexts(PackedInt32Array([0, 1, 2]), definitions)
	assert_eq(result.broad_category_id, &"three_context")
	assert_eq(result.component.category_id, &"three_context")


func test_lower_priority_context_shapes_do_not_emit_extra_components() -> void:
	var definitions: Array[ContextHandDefinition] = [
		ContextHandDefinition.new(&"single", 10, {0: 1}, Rational.new(2, 1), &"single_context"),
		ContextHandDefinition.new(&"triple", 20, {0: 1, 1: 1, 2: 1}, Rational.new(3, 1), &"three_context"),
	]
	var result := ContextHandEvaluator.evaluate_contexts(PackedInt32Array([0, 1, 2]), definitions)
	assert_eq(result.component.source_definition_id, &"triple")


func test_no_context_fallback_is_neutral_and_has_no_buffable_category() -> void:
	var result := ContextHandEvaluator.evaluate_contexts(PackedInt32Array([0]), [])
	assert_eq(result.broad_category_id, &"")
	assert_eq(result.component, null)


func test_base_score_adds_all_ordinary_ranks_and_skips_ranked_jokers() -> void:
	var faces := _score_faces([4, 9, 6])
	faces.append(ScoringTypes.SelectedCardFace.new(&"joker", 0, 10, 0, true))
	var sum := ScoreCalculator.calculate(faces, null, null, [])
	assert_eq(sum.base_value, 19)
	assert_eq(sum.final_score, 19)
	var pass_score := ScoreCalculator.calculate([], null, null, [])
	assert_eq(pass_score.final_score, 0)


func test_score_adds_components_and_matching_modifiers_inside_each_factor() -> void:
	var faces := _score_faces([4, 6])
	var result := ScoreCalculator.calculate(
		faces,
		_normal(faces, [_component(&"card_hand", &"straight", &"straight", 6), _component(&"card_hand", &"flush", &"flush", 4)]),
		_context([_component(&"context_hand", &"three_context", &"abc", 5)]),
		[
			_modifier(&"card_hand", &"straight", 3, &"buff"),
			_modifier(&"card_hand", &"flush", -2, &"nerf"),
			_modifier(&"context_hand", &"three_context", -3, &"context-nerf"),
		]
	)
	assert_true(result.card_hand_factor.equals(Rational.new(11, 1)))
	assert_true(result.context_hand_factor.equals(Rational.new(2, 1)))
	assert_eq(result.final_score, 220)


func test_straight_flush_uses_sum_of_both_normal_components() -> void:
	var faces := _score_faces([2, 3, 4])
	var result := ScoreCalculator.calculate(faces, _normal(faces, [
		_component(&"card_hand", &"straight", &"straight", 4),
		_component(&"card_hand", &"flush", &"flush", 2),
	]), _context([]), [])
	assert_true(result.card_hand_factor.equals(Rational.new(6, 1)))


func test_one_modifier_hits_matching_group_once_even_with_several_rank_groups() -> void:
	var faces := _score_faces([2, 2, 8, 8])
	var duplicate_groups := [
		_component(&"card_hand", &"group", &"two_pairs", 5),
		_component(&"card_hand", &"group", &"malformed_duplicate", 7),
	]
	var result := ScoreCalculator.calculate(
		faces, _normal(faces, duplicate_groups), _context([]),
		[_modifier(&"card_hand", &"group", 3, &"once")]
	)
	assert_true(result.card_hand_factor.equals(Rational.new(15, 1)))
	assert_eq(result.applied_modifiers.size(), 1)


func test_multiple_same_category_modifiers_stack_once_each() -> void:
	var faces := _score_faces([5])
	var modifiers: Array[ScoringTypes.FactorModifier] = [
		_modifier(&"card_hand", &"high_card", 3, &"first"),
		_modifier(&"card_hand", &"high_card", 3, &"second"),
	]
	var result := ScoreCalculator.calculate(faces, _normal(faces, [
		_component(&"card_hand", &"high_card", &"high", 1)
	]), _context([]), modifiers)
	assert_true(result.card_hand_factor.equals(Rational.new(7, 1)))
	assert_eq(result.applied_modifiers.size(), 2)


func test_opposing_modifiers_are_order_independent() -> void:
	var faces := _score_faces([5])
	var normal := _normal(faces, [_component(&"card_hand", &"high_card", &"high", 2)])
	var buff := _modifier(&"card_hand", &"high_card", 3, &"buff")
	var nerf := _modifier(&"card_hand", &"high_card", -4, &"nerf")
	var first := ScoreCalculator.calculate(faces, normal, _context([]), [buff, nerf])
	var second := ScoreCalculator.calculate(faces, normal, _context([]), [nerf, buff])
	assert_true(first.card_hand_factor.equals(second.card_hand_factor))
	assert_eq(first.final_score, second.final_score)


func test_each_multiplier_factor_floors_to_one_independently() -> void:
	var faces := _score_faces([10])
	var result := ScoreCalculator.calculate(
		faces,
		_normal(faces, [_component(&"card_hand", &"high_card", &"high", 2)]),
		_context([_component(&"context_hand", &"single_context", &"single", 5)]),
		[
			_modifier(&"card_hand", &"high_card", -9, &"card-nerf"),
			_modifier(&"context_hand", &"single_context", -2, &"context-nerf"),
		]
	)
	assert_true(result.card_hand_unclamped.equals(Rational.new(-7, 1)))
	assert_true(result.card_hand_factor.equals(Rational.new(1, 1)))
	assert_true(result.context_hand_factor.equals(Rational.new(3, 1)))
	assert_eq(result.final_score, 30)


func test_pass_stays_zero_with_neutral_factor_floors() -> void:
	var no_faces: Array[ScoringTypes.SelectedCardFace] = []
	var result := ScoreCalculator.calculate(no_faces, _normal(no_faces, []), _context([]), [])
	assert_eq(result.base_value, 0)
	assert_eq(result.final_score, 0)


func test_exact_rationals_receive_one_final_ceiling_only() -> void:
	var faces := _score_faces([1])
	var result := ScoreCalculator.calculate(faces, _normal(faces, [
		ScoringTypes.MultiplierComponent.new(&"card_hand", &"high_card", &"fraction", Rational.new(4, 3))
	]), _context([ScoringTypes.MultiplierComponent.new(
		&"context_hand", &"single_context", &"fraction-context", Rational.new(5, 4)
	)]), [])
	assert_true(result.raw_score.equals(Rational.new(5, 3)))
	assert_eq(result.final_score, 2)


func _score_faces(ranks: Array) -> Array[ScoringTypes.SelectedCardFace]:
	var result: Array[ScoringTypes.SelectedCardFace] = []
	for index in range(ranks.size()):
		result.append(ScoringTypes.SelectedCardFace.new(StringName("score-%d" % index), 0, ranks[index], 0))
	return result


func _component(factor: StringName, category: StringName, source: StringName, value: int) -> ScoringTypes.MultiplierComponent:
	return ScoringTypes.MultiplierComponent.new(factor, category, source, Rational.new(value, 1))


func _modifier(factor: StringName, category: StringName, value: int, copy_id: StringName) -> ScoringTypes.FactorModifier:
	return ScoringTypes.FactorModifier.new(factor, category, Rational.new(value, 1), copy_id, copy_id)


func _normal(faces: Array[ScoringTypes.SelectedCardFace], components: Array) -> ScoringTypes.NormalHandResult:
	var typed: Array[ScoringTypes.MultiplierComponent] = []
	typed.assign(components)
	return ScoringTypes.NormalHandResult.new(not faces.is_empty(), &"fixture", 1, Rational.new(1, 1), faces, faces, PackedInt32Array(), typed)


func _context(components: Array) -> ScoringTypes.ContextHandResult:
	var component: ScoringTypes.MultiplierComponent = components[0] if not components.is_empty() else null
	return ScoringTypes.ContextHandResult.new(&"fixture", 1, Rational.new(1, 1), {}, component.category_id if component else &"", component)


func _card(id: StringName, first_context: int, second_context: int) -> FullCardState:
	var first := HalfCardState.new(
		StringName("%s-first" % id), first_context, 1, GameTypes.Suit.MOUNTAIN
	)
	var second := HalfCardState.new(
		StringName("%s-second" % id), second_context, 1, GameTypes.Suit.CLOUD
	)
	return FullCardState.new(id, first, second)
