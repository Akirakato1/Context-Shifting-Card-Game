class_name ContextHandDefinition
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")

var id: StringName
var priority: int
var minimums: Dictionary
var multiplier: Rational


func _init(
	definition_id: StringName,
	definition_priority: int,
	context_minimums: Dictionary,
	definition_multiplier: Rational
) -> void:
	for context in context_minimums:
		assert(
			context is int
			and context >= GameTypes.Context.A
			and context <= GameTypes.Context.C,
			"unknown context minimum"
		)
		assert(context_minimums[context] is int and context_minimums[context] >= 0)
	id = definition_id
	priority = definition_priority
	minimums = context_minimums.duplicate()
	multiplier = definition_multiplier
