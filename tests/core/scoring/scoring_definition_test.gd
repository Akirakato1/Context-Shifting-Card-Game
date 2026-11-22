extends "res://tests/test_case.gd"

const Rational = preload("res://src/core/common/rational.gd")
const ScoringCategories = preload("res://src/core/scoring/scoring_categories.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")
const ContextHandDefinition = preload("res://src/core/scoring/context_hand_definition.gd")


func test_scoring_category_vocabulary_accepts_only_known_factor_category_pairs() -> void:
	for category in [&"high_card", &"straight", &"family", &"group", &"flush"]:
		assert_true(ScoringCategories.category_allowed(&"card_hand", category))
	for category in [&"single_context", &"two_context", &"three_context"]:
		assert_true(ScoringCategories.category_allowed(&"context_hand", category))
	assert_true(ScoringCategories.category_allowed(&"field", &"field"))
	assert_false(ScoringCategories.category_allowed(&"card_hand", &"single_context"))
	assert_false(ScoringCategories.category_allowed(&"unknown", &"flush"))
	assert_true(ScoringCategories.component_group_allowed(&"rank"))
	assert_true(ScoringCategories.component_group_allowed(&"suit"))
	assert_false(ScoringCategories.component_group_allowed(&"unknown"))

	var component := ScoringTypes.MultiplierComponent.new(
		&"card_hand", &"flush", &"flush_five", Rational.new(3, 2)
	)
	var modifier := ScoringTypes.FactorModifier.new(
		&"card_hand", &"flush", Rational.new(-3, 1), &"copy-1", &"flush_nerf"
	)
	assert_eq(component.source_definition_id, &"flush_five")
	assert_eq(modifier.source_copy_id, &"copy-1")


func test_normal_definition_retains_component_group_category_and_rule_parameters() -> void:
	var definition := NormalHandDefinition.new(
		&"three_pairs", 60, 6, &"grouped_ranks", Rational.new(6, 1),
		&"group", &"rank", {"group_sizes": [2, 2, 2]}
	)
	assert_eq(definition.broad_category_id, &"group")
	assert_eq(definition.component_group, &"rank")
	assert_eq(definition.rule_parameters, {"group_sizes": [2, 2, 2]})

	var legacy := NormalHandDefinition.new(&"pair", 20, 2, &"pair", Rational.new(2, 1))
	assert_eq(legacy.rule_id, &"grouped_ranks")
	assert_eq(legacy.rule_parameters, {"group_sizes": [2]})
	assert_eq(legacy.broad_category_id, &"family")
	assert_eq(legacy.component_group, &"rank")


func test_context_definition_retains_broad_category() -> void:
	var explicit := ContextHandDefinition.new(
		&"rise_and_flourish", 20, {0: 2, 1: 2}, Rational.new(3, 1), &"two_context"
	)
	assert_eq(explicit.broad_category_id, &"two_context")
	var inferred := ContextHandDefinition.new(
		&"all_three", 30, {0: 1, 1: 1, 2: 1}, Rational.new(4, 1)
	)
	assert_eq(inferred.broad_category_id, &"three_context")
