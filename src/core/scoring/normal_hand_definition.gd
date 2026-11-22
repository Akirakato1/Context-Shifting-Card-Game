class_name NormalHandDefinition
extends RefCounted

const Rational = preload("res://src/core/common/rational.gd")
const ScoringCategories = preload("res://src/core/scoring/scoring_categories.gd")

var id: StringName
var priority: int
var subset_size: int
var rule_id: StringName
var multiplier: Rational
var broad_category_id: StringName
var component_group: StringName
var rule_parameters: Dictionary


func _init(
	definition_id: StringName,
	definition_priority: int,
	required_subset_size: int,
	definition_rule_id: StringName,
	definition_multiplier: Rational,
	definition_broad_category_id: StringName = &"",
	definition_component_group: StringName = &"",
	definition_rule_parameters: Dictionary = {}
) -> void:
	assert(required_subset_size > 0, "normal hand subset size must be positive")
	var normalized_rule := definition_rule_id
	var normalized_parameters := definition_rule_parameters.duplicate(true)
	if definition_rule_id == &"pair":
		normalized_rule = &"grouped_ranks"
		normalized_parameters = {"group_sizes": [2]}
	elif definition_rule_id == &"three_kind":
		normalized_rule = &"grouped_ranks"
		normalized_parameters = {"group_sizes": [3]}
	elif definition_rule_id == &"full_house":
		normalized_rule = &"grouped_ranks"
		normalized_parameters = {"group_sizes": [3, 2]}
	var inferred_category := definition_broad_category_id
	if inferred_category == &"":
		inferred_category = _infer_category(normalized_rule, normalized_parameters)
	var inferred_group := definition_component_group
	if inferred_group == &"":
		inferred_group = ScoringCategories.SUIT_GROUP if normalized_rule == &"flush" else ScoringCategories.RANK_GROUP
	assert(ScoringCategories.category_allowed(ScoringCategories.CARD_HAND, inferred_category))
	assert(ScoringCategories.component_group_allowed(inferred_group))
	id = definition_id
	priority = definition_priority
	subset_size = required_subset_size
	rule_id = normalized_rule
	multiplier = definition_multiplier
	broad_category_id = inferred_category
	component_group = inferred_group
	rule_parameters = normalized_parameters


static func _infer_category(rule: StringName, parameters: Dictionary) -> StringName:
	match rule:
		&"high_card": return ScoringCategories.HIGH_CARD
		&"straight": return ScoringCategories.STRAIGHT
		&"flush": return ScoringCategories.FLUSH
		&"grouped_ranks":
			var sizes: Array = parameters.get("group_sizes", [])
			return ScoringCategories.FAMILY if sizes.size() == 1 else ScoringCategories.GROUP
	return ScoringCategories.HIGH_CARD
