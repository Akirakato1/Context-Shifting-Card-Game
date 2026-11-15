class_name ScoringTypes
extends RefCounted

const Rational = preload("res://src/core/common/rational.gd")


class SelectedCardFace extends RefCounted:
	var card_id: StringName
	var half_index: int
	var rank: int
	var suit: int

	func _init(id: StringName, selected_half_index: int, face_rank: int, face_suit: int) -> void:
		card_id = id
		half_index = selected_half_index
		rank = face_rank
		suit = face_suit


class ScoreModifier extends RefCounted:
	var operation: StringName
	var value: Rational
	var source_id: StringName

	func _init(modifier_operation: StringName, modifier_value: Rational, source: StringName) -> void:
		operation = modifier_operation
		value = modifier_value
		source_id = source


class NormalHandResult extends RefCounted:
	var is_valid: bool
	var category_id: StringName
	var priority: int
	var multiplier: Rational
	var matched_faces: Array[SelectedCardFace]
	var submitted_faces: Array[SelectedCardFace]
	var tie_break: PackedInt32Array

	func _init(
		valid: bool,
		category: StringName,
		category_priority: int,
		category_multiplier: Rational,
		matched: Array[SelectedCardFace],
		submitted: Array[SelectedCardFace],
		category_tie_break: PackedInt32Array
	) -> void:
		is_valid = valid
		category_id = category
		priority = category_priority
		multiplier = category_multiplier
		matched_faces = matched.duplicate()
		submitted_faces = submitted.duplicate()
		tie_break = category_tie_break.duplicate()
