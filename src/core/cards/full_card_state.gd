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


func half_at(index: int) -> HalfCardState:
	assert(index == 0 or index == 1, "half index must be zero or one")
	return first if index == 0 else second


func face_snapshot() -> Dictionary:
	return {"first": _face(first), "second": _face(second)}


func _face(half: HalfCardState) -> Dictionary:
	return {
		"kind": half.kind,
		"effective_context": half.effective_context(),
		"effective_rank": half.effective_rank(),
		"effective_suit": half.effective_suit(),
	}


func eligible_half_indexes(active_context: int) -> PackedInt32Array:
	return eligible_half_indexes_for_contexts(PackedInt32Array([active_context]))


func eligible_half_indexes_for_contexts(active_contexts: PackedInt32Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	if first.is_joker() or first.effective_context() in active_contexts:
		result.append(0)
	if second.is_joker() or second.effective_context() in active_contexts:
		result.append(1)
	return result


func reset_effective() -> void:
	first.reset_effective()
	second.reset_effective()


func leave_hand() -> void:
	reset_effective()
