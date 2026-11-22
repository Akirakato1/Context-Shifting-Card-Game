extends "res://tests/test_case.gd"

const ScoringReference = preload("res://src/view/app/scoring_reference.gd")


func test_default_reference_uses_complete_normal_hand_catalog() -> void:
	var definitions := ScoringReference.normal_definitions()
	var by_id := {}
	for definition in definitions:
		by_id[definition.id] = definition

	assert_eq(definitions.size(), 19)
	assert_eq(by_id.pair.multiplier.numerator, 5)
	assert_eq(by_id.pair.multiplier.denominator, 4)
	assert_eq(by_id.four_house.rule_parameters.group_sizes, [4, 2])
	assert_eq(by_id.six_kind.multiplier.numerator, 19)
	assert_eq(by_id.six_kind.multiplier.denominator, 4)

	var catalog := ScoringReference.default_catalog()
	assert_eq(catalog.normal.size(), 19)
