extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const ContextHandCatalog = preload("res://src/core/scoring/context_hand_catalog.gd")
const ContextHandEvaluator = preload("res://src/core/scoring/context_hand_evaluator.gd")
const ScoringCategories = preload("res://src/core/scoring/scoring_categories.gd")


func test_catalog_has_40_unique_semantic_definitions_in_all_three_families() -> void:
	var definitions := ContextHandCatalog.definitions()
	var by_id := _by_id(definitions)
	var category_counts := {}
	for definition in definitions:
		category_counts[definition.broad_category_id] = int(
			category_counts.get(definition.broad_category_id, 0)
		) + 1
	assert_eq(definitions.size(), 40)
	assert_eq(by_id.size(), 40)
	assert_eq(category_counts[ScoringCategories.THREE_CONTEXT], 4)
	assert_eq(category_counts[ScoringCategories.SINGLE_CONTEXT], 24)
	assert_eq(category_counts[ScoringCategories.TWO_CONTEXT], 12)
	for id in [&"all_contexts_4", &"rise_12", &"flourish_12", &"fall_12",
		&"rise_flourish_6", &"rise_fall_6", &"flourish_fall_6"]:
		assert_true(by_id.has(id))


func test_every_family_threshold_has_the_configured_priority_and_exact_multiplier() -> void:
	var by_id := _by_id(ContextHandCatalog.definitions())
	var all_tiers := {
		1: [10, 5, 4], 2: [20, 3, 2], 3: [40, 11, 4], 4: [90, 4, 1],
	}
	for threshold in all_tiers:
		_assert_tier(by_id[StringName("all_contexts_%d" % threshold)], all_tiers[threshold])
	var single_tiers := {
		5: [1, 5, 4], 6: [5, 11, 8], 7: [9, 3, 2], 8: [19, 13, 8],
		9: [39, 15, 8], 10: [59, 17, 8], 11: [89, 5, 2], 12: [101, 11, 4],
	}
	for context_name in ["rise", "flourish", "fall"]:
		for threshold in single_tiers:
			_assert_tier(
				by_id[StringName("%s_%d" % [context_name, threshold])],
				single_tiers[threshold]
			)
	var pair_tiers := {
		3: [30, 11, 8], 4: [60, 15, 8], 5: [100, 19, 8], 6: [130, 13, 4],
	}
	for pair_name in ["rise_flourish", "rise_fall", "flourish_fall"]:
		for threshold in pair_tiers:
			_assert_tier(
				by_id[StringName("%s_%d" % [pair_name, threshold])],
				pair_tiers[threshold]
			)


func test_priority_resolves_overlaps_in_favor_of_stronger_mixed_shapes() -> void:
	var definitions := ContextHandCatalog.definitions()
	assert_eq(
		ContextHandEvaluator.evaluate_contexts(_contexts(6, 3, 3), definitions).category_id,
		&"all_contexts_3"
	)
	assert_eq(
		ContextHandEvaluator.evaluate_contexts(_contexts(5, 0, 3), definitions).category_id,
		&"rise_fall_3"
	)
	assert_eq(
		ContextHandEvaluator.evaluate_contexts(_contexts(4, 4, 4), definitions).category_id,
		&"all_contexts_4"
	)
	assert_eq(
		ContextHandEvaluator.evaluate_contexts(_contexts(5, 5, 2), definitions).category_id,
		&"rise_flourish_5"
	)


func test_multiplier_strictly_increases_within_each_context_pattern() -> void:
	var patterns := {}
	for definition in ContextHandCatalog.definitions():
		var contexts := definition.minimums.keys()
		contexts.sort()
		var key := str(contexts)
		if not patterns.has(key):
			patterns[key] = []
		patterns[key].append(definition)
	for pattern: Array in patterns.values():
		pattern.sort_custom(func(a: ContextHandDefinition, b: ContextHandDefinition) -> bool:
			var context: int = a.minimums.keys()[0]
			return a.minimums[context] < b.minimums[context]
		)
		for index in range(1, pattern.size()):
			var previous: ContextHandDefinition = pattern[index - 1]
			var current: ContextHandDefinition = pattern[index]
			assert_true(current.multiplier.compare_to(previous.multiplier) > 0,
				"%s should pay more than %s" % [current.id, previous.id])


func test_each_catalog_call_returns_fresh_array_definitions_and_minimums() -> void:
	var first := ContextHandCatalog.definitions()
	var first_all_one = _by_id(first)[&"all_contexts_1"]
	first.pop_back()
	first_all_one.minimums[GameTypes.Context.RISE] = 99
	var second := ContextHandCatalog.definitions()
	assert_eq(second.size(), 40)
	assert_eq(
		_by_id(second)[&"all_contexts_1"].minimums[GameTypes.Context.RISE],
		1
	)


func _by_id(definitions: Array) -> Dictionary:
	var result := {}
	for definition in definitions:
		result[definition.id] = definition
	return result


func _assert_tier(definition, expected: Array) -> void:
	assert_eq(definition.priority, expected[0])
	assert_eq(definition.multiplier.numerator, expected[1])
	assert_eq(definition.multiplier.denominator, expected[2])


func _contexts(rise: int, flourish: int, fall: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for _index in range(rise): result.append(GameTypes.Context.RISE)
	for _index in range(flourish): result.append(GameTypes.Context.FLOURISH)
	for _index in range(fall): result.append(GameTypes.Context.FALL)
	return result
