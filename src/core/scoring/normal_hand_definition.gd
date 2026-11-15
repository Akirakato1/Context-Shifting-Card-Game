class_name NormalHandDefinition
extends RefCounted

const Rational = preload("res://src/core/common/rational.gd")

var id: StringName
var priority: int
var subset_size: int
var rule_id: StringName
var multiplier: Rational


func _init(
	definition_id: StringName,
	definition_priority: int,
	required_subset_size: int,
	definition_rule_id: StringName,
	definition_multiplier: Rational
) -> void:
	assert(required_subset_size > 0, "normal hand subset size must be positive")
	id = definition_id
	priority = definition_priority
	subset_size = required_subset_size
	rule_id = definition_rule_id
	multiplier = definition_multiplier
