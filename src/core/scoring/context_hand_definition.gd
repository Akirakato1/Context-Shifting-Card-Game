class_name ContextHandDefinition
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const ScoringCategories = preload("res://src/core/scoring/scoring_categories.gd")

var id: StringName
var priority: int
var minimums: Dictionary
var multiplier: Rational
var broad_category_id: StringName


func _init(
	definition_id: StringName,
	definition_priority: int,
	context_minimums: Dictionary,
	definition_multiplier: Rational,
	definition_broad_category_id: StringName = &""
) -> void:
	for context in context_minimums:
		assert(
			context is int
			and context >= GameTypes.Context.RISE
			and context <= GameTypes.Context.FALL,
			"unknown context minimum"
		)
		assert(context_minimums[context] is int and context_minimums[context] >= 0)
	id = definition_id
	priority = definition_priority
	minimums = context_minimums.duplicate()
	multiplier = definition_multiplier
	broad_category_id = definition_broad_category_id
	if broad_category_id == &"":
		match minimums.size():
			1: broad_category_id = ScoringCategories.SINGLE_CONTEXT
			2: broad_category_id = ScoringCategories.TWO_CONTEXT
			_: broad_category_id = ScoringCategories.THREE_CONTEXT
	assert(ScoringCategories.category_allowed(ScoringCategories.CONTEXT_HAND, broad_category_id))
