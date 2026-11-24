class_name NormalHandCatalog
extends RefCounted

const Rational = preload("res://src/core/common/rational.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")
const ScoringCategories = preload("res://src/core/scoring/scoring_categories.gd")


static func definitions() -> Array[NormalHandDefinition]:
	return [
		_rank(&"high_card", 10, 1, &"high_card", 1, 1, ScoringCategories.HIGH_CARD),
		_group(&"pair", 20, [2], 5, 4, ScoringCategories.FAMILY),
		_group(&"two_pair", 40, [2, 2], 7, 4, ScoringCategories.GROUP),
		_flush(&"flush_3", 50, 3, 7, 4),
		_group(&"three_kind", 60, [3], 7, 4, ScoringCategories.FAMILY),
		_rank(&"straight_4", 70, 4, &"straight", 2, 1, ScoringCategories.STRAIGHT),
		_flush(&"flush_4", 80, 4, 2, 1),
		_group(&"full_house", 90, [3, 2], 5, 2, ScoringCategories.GROUP),
		_rank(&"straight_5", 100, 5, &"straight", 9, 4, ScoringCategories.STRAIGHT),
		_flush(&"flush_5", 110, 5, 5, 2),
		_group(&"four_kind", 120, [4], 3, 1, ScoringCategories.FAMILY),
		_group(&"three_pair", 130, [2, 2, 2], 11, 4, ScoringCategories.GROUP),
		_flush(&"flush_6", 140, 6, 3, 1),
		_rank(&"straight_6", 150, 6, &"straight", 3, 1, ScoringCategories.STRAIGHT),
		_group(&"four_house", 160, [4, 2], 13, 4, ScoringCategories.GROUP),
		_group(&"double_triple", 170, [3, 3], 7, 2, ScoringCategories.GROUP),
		_group(&"five_kind", 180, [5], 17, 4, ScoringCategories.FAMILY),
		_group(&"six_kind", 190, [6], 6, 1, ScoringCategories.FAMILY),
	]


static func _rank(
	id: StringName,
	priority: int,
	size: int,
	rule: StringName,
	numerator: int,
	denominator: int,
	category: StringName
) -> NormalHandDefinition:
	return NormalHandDefinition.new(
		id, priority, size, rule, Rational.new(numerator, denominator),
		category, ScoringCategories.RANK_GROUP
	)


static func _group(
	id: StringName,
	priority: int,
	sizes: Array,
	numerator: int,
	denominator: int,
	category: StringName
) -> NormalHandDefinition:
	var subset_size := 0
	for size in sizes:
		subset_size += int(size)
	return NormalHandDefinition.new(
		id, priority, subset_size, &"grouped_ranks", Rational.new(numerator, denominator),
		category, ScoringCategories.RANK_GROUP, {"group_sizes": sizes.duplicate()}
	)


static func _flush(
	id: StringName,
	priority: int,
	size: int,
	numerator: int,
	denominator: int
) -> NormalHandDefinition:
	return NormalHandDefinition.new(
		id, priority, size, &"flush", Rational.new(numerator, denominator),
		ScoringCategories.FLUSH, ScoringCategories.SUIT_GROUP
	)
