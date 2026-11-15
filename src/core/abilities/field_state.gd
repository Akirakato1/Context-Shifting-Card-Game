class_name FieldState
extends RefCounted

const AbilityState = preload("res://src/core/abilities/ability_state.gd")

var ability: AbilityState
var source_player_id: StringName
var conflict_group: StringName
var remaining_rounds: int


func _init(field_ability: AbilityState, source_id: StringName) -> void:
	ability = field_ability
	source_player_id = source_id
	conflict_group = field_ability.definition.conflict_group
	remaining_rounds = field_ability.definition.field_duration


func tick_end() -> bool:
	remaining_rounds = max(remaining_rounds - 1, 0)
	return remaining_rounds == 0
