class_name FullCardState
extends RefCounted

const HalfCardState = preload("res://src/core/cards/half_card_state.gd")

var card_id: StringName
var first: HalfCardState
var second: HalfCardState


func _init(id: StringName, first_half: HalfCardState, second_half: HalfCardState) -> void:
	assert(first_half != null and second_half != null, "full cards require two half cards")
	assert(first_half.copy_id != second_half.copy_id, "a full card cannot reuse one half card")
	card_id = id
	first = first_half
	second = second_half


func eligible_half_indexes(active_context: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	if first.effective_context() == active_context:
		result.append(0)
	if second.effective_context() == active_context:
		result.append(1)
	return result


func reset_effective() -> void:
	first.reset_effective()
	second.reset_effective()
