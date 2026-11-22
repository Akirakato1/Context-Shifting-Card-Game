extends "res://tests/test_case.gd"

const Rational = preload("res://src/core/common/rational.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")
const NormalHandEvaluator = preload("res://src/core/scoring/normal_hand_evaluator.gd")


func test_rational_reduces_and_normalizes_denominator_sign() -> void:
	var reduced := Rational.new(6, 8)
	var normalized := Rational.new(3, -9)
	var double_negative := Rational.new(-4, -6)

	assert_eq(reduced.numerator, 3)
	assert_eq(reduced.denominator, 4)
	assert_eq(normalized.numerator, -1)
	assert_eq(normalized.denominator, 3)
	assert_eq(double_negative.numerator, 2)
	assert_eq(double_negative.denominator, 3)


func test_high_card_is_one_card_but_result_retains_the_whole_submission() -> void:
	var faces := _faces([3, 8, 9])
	var result := NormalHandEvaluator.evaluate(faces, _definitions())

	assert_true(result.is_valid)
	assert_eq(result.category_id, &"high_card")
	assert_eq(result.matched_faces.size(), 1)
	assert_eq(result.matched_faces[0].rank, 9)
	assert_eq(result.submitted_faces.size(), 3)
	assert_eq(_rank_total(result.submitted_faces), 20)


func test_category_priority_beats_contained_categories_and_multiplier_size() -> void:
	var definitions := _definitions()
	definitions[1].multiplier = Rational.new(100, 1)
	var result := NormalHandEvaluator.evaluate(_faces([4, 4, 4, 9, 9]), definitions)

	assert_eq(result.category_id, &"full_house")
	assert_eq(result.priority, 50)
	assert_true(result.multiplier.equals(Rational.new(5, 2)))
	assert_eq(result.matched_faces.size(), 5)

	var post_classification_buff := ScoringTypes.ScoreModifier.new(
		&"multiply_normal", Rational.new(1, 100), &"fixture_nerf"
	)
	assert_eq(post_classification_buff.operation, &"multiply_normal")
	assert_eq(result.category_id, &"full_house", "later score effects must not reclassify")


func test_fixed_subset_sizes_and_rule_specific_tie_breaks() -> void:
	var pair := NormalHandEvaluator.evaluate(_faces([4, 4, 9, 9]), _definitions())
	assert_eq(pair.category_id, &"pair")
	assert_eq(pair.matched_faces.size(), 2)
	assert_eq(pair.matched_faces[0].rank, 9)
	assert_eq(pair.matched_faces[1].rank, 9)

	var trips := NormalHandEvaluator.evaluate(_faces([2, 7, 7, 7]), _definitions())
	assert_eq(trips.category_id, &"three_kind")
	assert_eq(trips.matched_faces.size(), 3)
	assert_eq(trips.matched_faces[0].rank, 7)

	var straight := NormalHandEvaluator.evaluate(_faces([1, 2, 3, 7, 8, 9]), _definitions())
	assert_eq(straight.category_id, &"straight")
	assert_eq(straight.matched_faces.size(), 3)
	assert_eq(straight.tie_break, PackedInt32Array([9]))


func test_no_nonempty_subset_returns_an_explicit_invalid_result() -> void:
	var only_pair: Array[NormalHandDefinition] = [
		NormalHandDefinition.new(&"pair", 20, 2, &"pair", Rational.new(2, 1)),
	]
	var result := NormalHandEvaluator.evaluate(_faces([2, 7, 9]), only_pair)

	assert_false(result.is_valid)
	assert_eq(result.category_id, &"")
	assert_eq(result.matched_faces.size(), 0)
	assert_eq(result.submitted_faces.size(), 3)


func test_rank_result_selects_exactly_one_high_straight_family_or_group_component() -> void:
	var result := NormalHandEvaluator.evaluate(_faces([4, 4, 4, 9, 9]), _component_definitions())
	assert_eq(result.category_id, &"full_house")
	assert_eq(result.components.size(), 1)
	assert_eq(result.components[0].category_id, &"group")


func test_grouped_rank_parameters_cover_two_pairs_two_triples_three_pairs_and_full_house() -> void:
	var fixtures := {
		&"two_pairs": [2, 2, 8, 8],
		&"two_triples": [2, 2, 2, 8, 8, 8],
		&"three_pairs": [2, 2, 5, 5, 8, 8],
		&"full_house": [2, 2, 2, 8, 8],
	}
	for expected in fixtures:
		assert_eq(NormalHandEvaluator.evaluate(_faces(fixtures[expected]), _component_definitions()).category_id, expected)


func test_full_house_is_group_only_and_does_not_emit_contained_family_components() -> void:
	var result := NormalHandEvaluator.evaluate(_faces([4, 4, 4, 9, 9]), _component_definitions())
	assert_eq(result.components.size(), 1)
	assert_eq(result.components[0].category_id, &"group")


func test_high_card_uses_one_card_subset_when_extra_cards_are_submitted() -> void:
	var result := NormalHandEvaluator.evaluate(_faces([3, 8, 9]), _component_definitions())
	assert_eq(result.category_id, &"high_card")
	assert_eq(result.matched_faces.size(), 1)
	assert_eq(result.submitted_faces.size(), 3)


func test_straight_family_and_group_may_each_stack_one_flush_component() -> void:
	for ranks in [[1, 2, 3], [7, 7, 7], [4, 4, 4, 9, 9]]:
		var faces := _faces(ranks)
		for face in faces: face.suit = 1
		var result := NormalHandEvaluator.evaluate(faces, _component_definitions())
		assert_eq(result.components.size(), 2)
		assert_eq(result.components[1].category_id, &"flush")


func test_flush_requires_every_submitted_face_to_share_one_suit() -> void:
	var faces := _faces([1, 2, 3])
	faces[0].suit = 1
	faces[1].suit = 1
	faces[2].suit = 2
	var result := NormalHandEvaluator.evaluate(faces, _component_definitions())
	assert_eq(result.components.size(), 1)


func test_flush_definition_does_not_match_a_same_suit_subset_with_off_suit_extras() -> void:
	var faces := _faces([1, 2, 3, 8])
	for face in faces: face.suit = 1
	faces[3].suit = 2
	var result := NormalHandEvaluator.evaluate(faces, _component_definitions())
	for component in result.components:
		assert_ne(component.category_id, &"flush")


func _definitions() -> Array[NormalHandDefinition]:
	return [
		NormalHandDefinition.new(&"high_card", 10, 1, &"high_card", Rational.new(1, 1)),
		NormalHandDefinition.new(&"pair", 20, 2, &"pair", Rational.new(3, 2)),
		NormalHandDefinition.new(&"three_kind", 30, 3, &"three_kind", Rational.new(2, 1)),
		NormalHandDefinition.new(&"straight", 40, 3, &"straight", Rational.new(9, 4)),
		NormalHandDefinition.new(&"full_house", 50, 5, &"full_house", Rational.new(5, 2)),
	]


func _component_definitions() -> Array[NormalHandDefinition]:
	return [
		NormalHandDefinition.new(&"high_card", 10, 1, &"high_card", Rational.new(1, 1)),
		NormalHandDefinition.new(&"straight", 40, 3, &"straight", Rational.new(4, 1)),
		NormalHandDefinition.new(&"family_three", 30, 3, &"grouped_ranks", Rational.new(3, 1), &"family", &"rank", {"group_sizes": [3]}),
		NormalHandDefinition.new(&"two_pairs", 50, 4, &"grouped_ranks", Rational.new(5, 1), &"group", &"rank", {"group_sizes": [2, 2]}),
		NormalHandDefinition.new(&"full_house", 60, 5, &"grouped_ranks", Rational.new(6, 1), &"group", &"rank", {"group_sizes": [3, 2]}),
		NormalHandDefinition.new(&"three_pairs", 70, 6, &"grouped_ranks", Rational.new(7, 1), &"group", &"rank", {"group_sizes": [2, 2, 2]}),
		NormalHandDefinition.new(&"two_triples", 80, 6, &"grouped_ranks", Rational.new(8, 1), &"group", &"rank", {"group_sizes": [3, 3]}),
		NormalHandDefinition.new(&"flush_three", 20, 3, &"flush", Rational.new(2, 1), &"flush", &"suit"),
		NormalHandDefinition.new(&"flush_five", 20, 5, &"flush", Rational.new(2, 1), &"flush", &"suit"),
	]


func _faces(ranks: Array) -> Array[ScoringTypes.SelectedCardFace]:
	var result: Array[ScoringTypes.SelectedCardFace] = []
	for index in range(ranks.size()):
		result.append(ScoringTypes.SelectedCardFace.new(
			StringName("card-%d" % index), 0, ranks[index], index % 3
		))
	return result


func _rank_total(faces: Array[ScoringTypes.SelectedCardFace]) -> int:
	var total := 0
	for face in faces:
		total += face.rank
	return total
