class_name AbilityState
extends RefCounted

const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")

enum Zone {
	DRAW,
	HAND,
	ACTIVE_FIELD,
	USED,
}

var copy_id: StringName
var definition: AbilityDefinition
var zone := Zone.DRAW
var owner_id: StringName = &""


func _init(id: StringName, ability_definition: AbilityDefinition) -> void:
	copy_id = id
	definition = ability_definition


func move_to(new_zone: int, new_owner_id: StringName = &"") -> void:
	zone = new_zone
	owner_id = new_owner_id
