extends "res://tests/test_case.gd"

const ScoringReference = preload("res://src/view/app/scoring_reference.gd")


func test_default_reference_uses_complete_normal_hand_catalog() -> void:
	var definitions := ScoringReference.normal_definitions()
	var by_id := {}
	for definition in definitions:
		by_id[definition.id] = definition

	assert_eq(definitions.size(), 18)
	assert_eq(by_id.pair.multiplier.numerator, 5)
	assert_eq(by_id.pair.multiplier.denominator, 4)
	assert_eq(by_id.four_house.rule_parameters.group_sizes, [4, 2])
	assert_eq(by_id.six_kind.multiplier.numerator, 19)
	assert_eq(by_id.six_kind.multiplier.denominator, 4)

	var catalog := ScoringReference.default_catalog()
	assert_eq(catalog.normal.size(), 18)
	var normal_names := {}
	for entry: Dictionary in catalog.normal:
		normal_names[entry.id] = entry.display_name
	assert_eq(normal_names.full_house, "Full House")
	assert_eq(normal_names.two_pair, "Two Pair")
	assert_eq(normal_names.six_kind, "Six of a Kind")
	assert_eq(normal_names.flush_5, "5-card Flush")
	var context_names := {}
	for entry: Dictionary in catalog.context:
		context_names[entry.id] = entry.display_name
		assert_false(str(entry.get("requirements_text", "")).is_empty())
	assert_eq(context_names.size(), 40)
	assert_eq(context_names.rise_5, "Five Ascent")
	assert_eq(context_names.fall_7, "Seven Descent")
	assert_eq(context_names.flourish_12, "Twelve Golden Age")
	assert_eq(context_names.rise_flourish_4, "Four Renaissance")
	assert_eq(context_names.rise_fall_4, "Four Upheaval")
	assert_eq(context_names.flourish_fall_4, "Four Afterglow")
	assert_eq(context_names.all_contexts_4, "Four Full Cycle")
