extends "res://tests/test_case.gd"

const NormalHandCatalog = preload("res://src/core/scoring/normal_hand_catalog.gd")


func test_catalog_contains_all_approved_definitions_with_exact_balance_data() -> void:
	var expected := {
		&"high_card": [10, 1, &"high_card", 1, 1, &"high_card", &"rank", []],
		&"pair": [20, 2, &"grouped_ranks", 5, 4, &"family", &"rank", [2]],
		&"two_pair": [40, 4, &"grouped_ranks", 7, 4, &"group", &"rank", [2, 2]],
		&"flush_3": [50, 3, &"flush", 2, 1, &"flush", &"suit", []],
		&"three_kind": [60, 3, &"grouped_ranks", 7, 4, &"family", &"rank", [3]],
		&"straight_4": [70, 4, &"straight", 2, 1, &"straight", &"rank", []],
		&"flush_4": [80, 4, &"flush", 9, 4, &"flush", &"suit", []],
		&"full_house": [90, 5, &"grouped_ranks", 9, 4, &"group", &"rank", [3, 2]],
		&"straight_5": [100, 5, &"straight", 9, 4, &"straight", &"rank", []],
		&"flush_5": [110, 5, &"flush", 11, 4, &"flush", &"suit", []],
		&"four_kind": [120, 4, &"grouped_ranks", 5, 2, &"family", &"rank", [4]],
		&"three_pair": [130, 6, &"grouped_ranks", 11, 4, &"group", &"rank", [2, 2, 2]],
		&"flush_6": [140, 6, &"flush", 13, 4, &"flush", &"suit", []],
		&"straight_6": [150, 6, &"straight", 3, 1, &"straight", &"rank", []],
		&"four_house": [160, 6, &"grouped_ranks", 13, 4, &"group", &"rank", [4, 2]],
		&"double_triple": [170, 6, &"grouped_ranks", 7, 2, &"group", &"rank", [3, 3]],
		&"five_kind": [180, 5, &"grouped_ranks", 7, 2, &"family", &"rank", [5]],
		&"six_kind": [190, 6, &"grouped_ranks", 19, 4, &"family", &"rank", [6]],
	}
	var definitions: Array = NormalHandCatalog.definitions()
	var by_id := {}
	for definition in definitions:
		assert_false(by_id.has(definition.id), "normal hand IDs must be unique")
		by_id[definition.id] = definition

	assert_eq(definitions.size(), 18)
	assert_eq(by_id.size(), expected.size())
	for id in expected:
		assert_true(by_id.has(id), "missing normal hand %s" % id)
		var definition = by_id[id]
		var row: Array = expected[id]
		assert_eq(definition.priority, row[0], "%s priority" % id)
		assert_eq(definition.subset_size, row[1], "%s subset size" % id)
		assert_eq(definition.rule_id, row[2], "%s rule" % id)
		assert_eq(definition.multiplier.numerator, row[3], "%s numerator" % id)
		assert_eq(definition.multiplier.denominator, row[4], "%s denominator" % id)
		assert_eq(definition.broad_category_id, row[5], "%s category" % id)
		assert_eq(definition.component_group, row[6], "%s component group" % id)
		assert_eq(definition.rule_parameters.get("group_sizes", []), row[7], "%s groups" % id)
