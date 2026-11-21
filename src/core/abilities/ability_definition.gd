class_name AbilityDefinition
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")

enum Timing {
	HAND_MANIPULATION,
	FIELD,
	HAND_SHAPE,
	SABOTAGE,
}

var id: StringName
var timing: int
var tags: Array[StringName]
var effect_id: StringName
var field_duration: int
var conflict_group: StringName
var _effect_parameters: Dictionary
var _choice_schema: Dictionary
var _display_name: String
var _rules_text: String

var effect_parameters: Dictionary:
	get: return _effect_parameters.duplicate(true)
var choice_schema: Dictionary:
	get: return _choice_schema.duplicate(true)
var display_name: String:
	get: return _display_name
var rules_text: String:
	get: return _rules_text


func _init(
	definition_id: StringName,
	timing_category: int,
	definition_tags: Array,
	definition_effect_id: StringName,
	duration: int = 0,
	field_conflict_group: StringName = &"",
	definition_effect_parameters: Dictionary = {},
	definition_choice_schema: Dictionary = {},
	definition_display_name: String = "",
	definition_rules_text: String = ""
) -> void:
	assert(timing_category >= Timing.HAND_MANIPULATION and timing_category <= Timing.SABOTAGE)
	assert(duration >= 0)
	assert(timing_category != Timing.FIELD or duration > 0, "field abilities need a duration")
	id = definition_id
	timing = timing_category
	tags.assign(definition_tags)
	effect_id = definition_effect_id
	field_duration = duration
	conflict_group = field_conflict_group
	_effect_parameters = definition_effect_parameters.duplicate(true)
	_choice_schema = definition_choice_schema.duplicate(true)
	_display_name = definition_display_name
	_rules_text = definition_rules_text


func allows_phase(phase: int) -> bool:
	match timing:
		Timing.HAND_MANIPULATION:
			return phase == GameTypes.Phase.HAND_PLAY
		Timing.FIELD:
			return phase == GameTypes.Phase.MAIN_1
		Timing.HAND_SHAPE:
			return phase == GameTypes.Phase.MAIN_1 or phase == GameTypes.Phase.MAIN_2
		Timing.SABOTAGE:
			return phase == GameTypes.Phase.MAIN_1
	return false
