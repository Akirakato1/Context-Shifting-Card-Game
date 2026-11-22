class_name ScoringTypes
extends RefCounted

const Rational = preload("res://src/core/common/rational.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")


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


class MultiplierComponent extends RefCounted:
	var factor_id: StringName
	var category_id: StringName
	var source_definition_id: StringName
	var value: Rational

	func _init(
		component_factor_id: StringName,
		component_category_id: StringName,
		component_source_definition_id: StringName,
		component_value: Rational
	) -> void:
		factor_id = component_factor_id
		category_id = component_category_id
		source_definition_id = component_source_definition_id
		value = component_value


class FactorModifier extends RefCounted:
	var factor_id: StringName
	var category_id: StringName
	var delta: Rational
	var source_copy_id: StringName
	var source_definition_id: StringName

	func _init(
		modifier_factor_id: StringName,
		modifier_category_id: StringName,
		modifier_delta: Rational,
		modifier_source_copy_id: StringName,
		modifier_source_definition_id: StringName
	) -> void:
		factor_id = modifier_factor_id
		category_id = modifier_category_id
		delta = modifier_delta
		source_copy_id = modifier_source_copy_id
		source_definition_id = modifier_source_definition_id


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


class ContextHandResult extends RefCounted:
	var category_id: StringName
	var priority: int
	var multiplier: Rational
	var counts: Dictionary

	func _init(
		category: StringName,
		category_priority: int,
		category_multiplier: Rational,
		context_counts: Dictionary
	) -> void:
		category_id = category
		priority = category_priority
		multiplier = category_multiplier
		counts = context_counts.duplicate()


class ScoreBreakdown extends RefCounted:
	var base_value: int
	var normal_multiplier: Rational
	var context_multiplier: Rational
	var before_modifiers: Rational
	var after_each_modifier: Array[Rational]
	var unclamped_raw_score: Rational
	var raw_score: Rational
	var final_score: int

	func _init(
		base: int,
		normal_value: Rational,
		context_value: Rational,
		before: Rational,
		modifier_results: Array[Rational],
		unclamped: Rational,
		clamped: Rational,
		final_value: int
	) -> void:
		base_value = base
		normal_multiplier = normal_value
		context_multiplier = context_value
		before_modifiers = before
		after_each_modifier = modifier_results.duplicate()
		unclamped_raw_score = unclamped
		raw_score = clamped
		final_score = final_value


class SubmissionResult extends RefCounted:
	var is_valid: bool
	var error_code: StringName
	var submitted_cards: Array[FullCardState]
	var selected_faces: Array[SelectedCardFace]
	var resolved_cards: Array[Dictionary]
	var normal_result: NormalHandResult
	var context_result: ContextHandResult
	var score_breakdown: ScoreBreakdown

	func _init(
		valid: bool,
		error: StringName,
		cards: Array[FullCardState],
		faces: Array[SelectedCardFace],
		resolved: Array[Dictionary],
		normal: NormalHandResult,
		context: ContextHandResult,
		breakdown: ScoreBreakdown
	) -> void:
		is_valid = valid
		error_code = error
		submitted_cards = cards.duplicate()
		selected_faces = faces.duplicate()
		resolved_cards = resolved.duplicate(true)
		normal_result = normal
		context_result = context
		score_breakdown = breakdown
