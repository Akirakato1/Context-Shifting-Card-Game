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
	var components: Array[MultiplierComponent]

	func _init(
		valid: bool,
		category: StringName,
		category_priority: int,
		category_multiplier: Rational,
		matched: Array[SelectedCardFace],
		submitted: Array[SelectedCardFace],
		category_tie_break: PackedInt32Array,
		multiplier_components: Array[MultiplierComponent] = []
	) -> void:
		is_valid = valid
		category_id = category
		priority = category_priority
		multiplier = category_multiplier
		matched_faces = matched.duplicate()
		submitted_faces = submitted.duplicate()
		tie_break = category_tie_break.duplicate()
		components = multiplier_components.duplicate()


class ContextHandResult extends RefCounted:
	var category_id: StringName
	var priority: int
	var multiplier: Rational
	var counts: Dictionary
	var broad_category_id: StringName
	var component: MultiplierComponent

	func _init(
		category: StringName,
		category_priority: int,
		category_multiplier: Rational,
		context_counts: Dictionary,
		context_broad_category_id: StringName = &"",
		context_component: MultiplierComponent = null
	) -> void:
		category_id = category
		priority = category_priority
		multiplier = category_multiplier
		counts = context_counts.duplicate()
		broad_category_id = context_broad_category_id
		component = context_component


class ScoreBreakdown extends RefCounted:
	var base_value: int
	var card_hand_components: Array[MultiplierComponent]
	var context_hand_components: Array[MultiplierComponent]
	var field_components: Array[MultiplierComponent]
	var applied_modifiers: Array[FactorModifier]
	var card_hand_unclamped: Rational
	var card_hand_factor: Rational
	var context_hand_unclamped: Rational
	var context_hand_factor: Rational
	var field_unclamped: Rational
	var field_factor: Rational
	var raw_score: Rational
	var final_score: int

	func _init(
		base: int,
		card_components: Array[MultiplierComponent],
		context_components: Array[MultiplierComponent],
		active_field_components: Array[MultiplierComponent],
		active_modifiers: Array[FactorModifier],
		card_unclamped: Rational,
		card_clamped: Rational,
		context_unclamped: Rational,
		context_clamped: Rational,
		field_unclamped_value: Rational,
		field_clamped: Rational,
		raw: Rational,
		final_value: int
	) -> void:
		base_value = base
		card_hand_components = card_components.duplicate()
		context_hand_components = context_components.duplicate()
		field_components = active_field_components.duplicate()
		applied_modifiers = active_modifiers.duplicate()
		card_hand_unclamped = card_unclamped
		card_hand_factor = card_clamped
		context_hand_unclamped = context_unclamped
		context_hand_factor = context_clamped
		field_unclamped = field_unclamped_value
		field_factor = field_clamped
		raw_score = raw
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
