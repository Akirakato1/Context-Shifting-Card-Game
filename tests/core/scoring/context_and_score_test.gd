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
		_card(&"one", GameTypes.Context.A, GameTypes.Context.B),
		_card(&"two", GameTypes.Context.A, GameTypes.Context.B),
		_card(&"three", GameTypes.Context.A, GameTypes.Context.C),
		_card(&"four", GameTypes.Context.A, GameTypes.Context.B),
	]
	var definitions: Array[ContextHandDefinition] = [
		ContextHandDefinition.new(
			&"abc_1", 10,
			{GameTypes.Context.A: 1, GameTypes.Context.B: 1, GameTypes.Context.C: 1},
			Rational.new(3, 2)
		),
		ContextHandDefinition.new(
			&"ab_3", 20,
			{GameTypes.Context.A: 3, GameTypes.Context.B: 3},
			Rational.new(2, 1)
		),
	]

	var result := ContextHandEvaluator.evaluate(cards, definitions)

	assert_eq(result.category_id, &"ab_3")
	assert_eq(result.priority, 20)
	assert_true(result.multiplier.equals(Rational.new(2, 1)))
	assert_eq(result.counts[GameTypes.Context.A], 4)
	assert_eq(result.counts[GameTypes.Context.B], 3)
	assert_eq(result.counts[GameTypes.Context.C], 1)


func test_context_evaluator_returns_neutral_fallback_when_no_threshold_matches() -> void:
	var definitions: Array[ContextHandDefinition] = [
		ContextHandDefinition.new(
			&"ab_3", 20,
			{GameTypes.Context.A: 3, GameTypes.Context.B: 3},
			Rational.new(2, 1)
		),
	]
	var cards: Array[FullCardState] = [
		_card(&"single", GameTypes.Context.A, GameTypes.Context.B),
	]

	var result := ContextHandEvaluator.evaluate(cards, definitions)

	assert_eq(result.category_id, &"no_context")
	assert_eq(result.priority, -1)
	assert_true(result.multiplier.equals(Rational.new(1, 1)))


func test_score_uses_all_faces_ordered_modifiers_and_one_final_ceiling() -> void:
	var faces: Array[ScoringTypes.SelectedCardFace] = [
		ScoringTypes.SelectedCardFace.new(&"three", 0, 3, GameTypes.Suit.ONE),
		ScoringTypes.SelectedCardFace.new(&"eight", 0, 8, GameTypes.Suit.TWO),
		ScoringTypes.SelectedCardFace.new(&"nine", 0, 9, GameTypes.Suit.THREE),
	]
	var normal := ScoringTypes.NormalHandResult.new(
		true, &"high_card", 10, Rational.new(3, 2), [faces[2]], faces, PackedInt32Array([9])
	)
	var context := ScoringTypes.ContextHandResult.new(
		&"abc_1", 10, Rational.new(4, 3), {},
	)
	var modifiers: Array[ScoringTypes.ScoreModifier] = [
		ScoringTypes.ScoreModifier.new(&"add", Rational.new(1, 2), &"bonus"),
		ScoringTypes.ScoreModifier.new(&"multiply", Rational.new(2, 3), &"scale"),
	]

	var result := ScoreCalculator.calculate(faces, normal, context, modifiers)

	assert_eq(result.base_value, 20)
	assert_true(result.before_modifiers.equals(Rational.new(40, 1)))
	assert_true(result.after_each_modifier[0].equals(Rational.new(81, 2)))
	assert_true(result.after_each_modifier[1].equals(Rational.new(27, 1)))
	assert_true(result.raw_score.equals(Rational.new(27, 1)))
	assert_eq(result.final_score, 27)


func test_score_floors_negative_raw_values_at_zero() -> void:
	var faces: Array[ScoringTypes.SelectedCardFace] = [
		ScoringTypes.SelectedCardFace.new(&"one", 0, 1, GameTypes.Suit.ONE),
	]
	var normal := ScoringTypes.NormalHandResult.new(
		true, &"high_card", 10, Rational.new(1, 1), faces, faces, PackedInt32Array([1])
	)
	var context := ScoringTypes.ContextHandResult.new(
		&"no_context", -1, Rational.new(1, 1), {},
	)
	var modifiers: Array[ScoringTypes.ScoreModifier] = [
		ScoringTypes.ScoreModifier.new(&"add", Rational.new(-2, 1), &"penalty"),
	]

	var result := ScoreCalculator.calculate(faces, normal, context, modifiers)

	assert_true(result.unclamped_raw_score.equals(Rational.new(-1, 1)))
	assert_true(result.raw_score.equals(Rational.new(0, 1)))
	assert_eq(result.final_score, 0)


func _card(id: StringName, first_context: int, second_context: int) -> FullCardState:
	var first := HalfCardState.new(
		StringName("%s-first" % id), first_context, 1, GameTypes.Suit.ONE
	)
	var second := HalfCardState.new(
		StringName("%s-second" % id), second_context, 1, GameTypes.Suit.TWO
	)
	return FullCardState.new(id, first, second)
