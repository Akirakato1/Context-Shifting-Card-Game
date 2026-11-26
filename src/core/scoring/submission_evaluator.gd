class_name SubmissionEvaluator
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")
const ContextHandDefinition = preload("res://src/core/scoring/context_hand_definition.gd")
const NormalHandEvaluator = preload("res://src/core/scoring/normal_hand_evaluator.gd")
const ContextHandEvaluator = preload("res://src/core/scoring/context_hand_evaluator.gd")
const ScoreCalculator = preload("res://src/core/scoring/score_calculator.gd")
const FieldEffectResolver = preload("res://src/core/abilities/field_effect_resolver.gd")

const MAX_SUBMITTED_CARDS := 6


static func evaluate(
	hand: Array[FullCardState],
	selections: Array,
	active_context: int,
	normal_definitions: Array[NormalHandDefinition],
	context_definitions: Array[ContextHandDefinition],
	modifiers: Array[ScoringTypes.FactorModifier],
	active_fields: Array = []
) -> ScoringTypes.SubmissionResult:
	if selections.size() > MAX_SUBMITTED_CARDS:
		return _invalid(&"submission_size_out_of_range")
	if (
		active_context < GameTypes.Context.RISE
		or active_context > GameTypes.Context.FALL
	):
		return _invalid(&"invalid_active_context")
	var active_contexts := FieldEffectResolver.active_contexts(active_context, active_fields)

	var cards_by_id := {}
	for card in hand:
		cards_by_id[card.card_id] = card

	var seen_card_ids := {}
	var submitted_cards: Array[FullCardState] = []
	var selected_faces: Array[ScoringTypes.SelectedCardFace] = []
	var resolved_cards: Array[Dictionary] = []
	var resolved_contexts := PackedInt32Array()

	for untyped_selection in selections:
		if not untyped_selection is Dictionary:
			return _invalid(&"malformed_submission")
		var selection: Dictionary = untyped_selection
		if not selection.has("card_id") or not selection.has("half_index"):
			return _invalid(&"malformed_submission")
		if not selection.has("joker_choices") or not selection["joker_choices"] is Array:
			return _invalid(&"malformed_submission")
		var card_id_value: Variant = selection["card_id"]
		if not (card_id_value is String or card_id_value is StringName):
			return _invalid(&"malformed_submission")
		var card_id := StringName(str(card_id_value))
		if seen_card_ids.has(card_id):
			return _invalid(&"duplicate_submitted_card")
		if not cards_by_id.has(card_id):
			return _invalid(&"card_not_in_hand")
		var half_index_value: Variant = selection["half_index"]
		if not half_index_value is int or half_index_value < 0 or half_index_value > 1:
			return _invalid(&"invalid_half_index")
		var half_index: int = half_index_value
		var card: FullCardState = cards_by_id[card_id]
		var choices_result := _validate_joker_choices(card, selection["joker_choices"], active_contexts)
		if not choices_result["ok"]:
			return _invalid(choices_result["error_code"])
		var choices_by_half: Dictionary = choices_result["choices_by_half"]
		var selected_half: HalfCardState = card.half_at(half_index)
		if card.eligible_half_indexes_for_contexts(active_contexts).is_empty():
			return _invalid(&"card_not_eligible")
		if (
			not selected_half.is_joker()
			and selected_half.effective_context() not in active_contexts
		):
			return _invalid(&"selected_half_not_active")

		var resolved_halves: Array[Dictionary] = []
		for resolved_half_index in range(2):
			var half: HalfCardState = card.half_at(resolved_half_index)
			var resolved_context: int
			var resolved_rank: int
			var resolved_suit: int
			if half.is_joker():
				var choice: Dictionary = choices_by_half[resolved_half_index]
				resolved_context = choice["context"]
				resolved_rank = choice["rank"]
				resolved_suit = choice["suit"]
			else:
				resolved_context = half.effective_context()
				resolved_rank = half.effective_rank()
				resolved_suit = half.effective_suit()
			resolved_contexts.append(resolved_context)
			resolved_halves.append({
				"context": resolved_context,
				"rank": resolved_rank,
				"suit": resolved_suit,
				"joker": half.is_joker(),
			})

		var selected_resolved: Dictionary = resolved_halves[half_index]
		selected_faces.append(ScoringTypes.SelectedCardFace.new(
			card.card_id,
			half_index,
			selected_resolved["rank"],
			selected_resolved["suit"],
			selected_resolved["joker"]
		))
		submitted_cards.append(card)
		resolved_cards.append({
			"card_id": str(card.card_id),
			"selected_half_index": half_index,
			"halves": resolved_halves,
		})
		seen_card_ids[card_id] = true

	var normal_result := NormalHandEvaluator.evaluate(selected_faces, normal_definitions)
	if not selections.is_empty() and not normal_result.is_valid:
		return _invalid(&"invalid_normal_hand")
	var context_result := ContextHandEvaluator.evaluate_contexts(
		resolved_contexts, context_definitions
	)
	var field_components := FieldEffectResolver.score_components(
		selected_faces, context_result.counts, active_fields
	)
	var score_breakdown := ScoreCalculator.calculate(
		selected_faces, normal_result, context_result, modifiers, field_components
	)
	return ScoringTypes.SubmissionResult.new(
		true,
		&"",
		submitted_cards,
		selected_faces,
		resolved_cards,
		normal_result,
		context_result,
		score_breakdown
	)


static func _validate_joker_choices(
	card: FullCardState, choices: Array, active_contexts: PackedInt32Array
) -> Dictionary:
	var choices_by_half := {}
	for untyped_choice in choices:
		if not untyped_choice is Dictionary:
			return _choice_error(&"malformed_joker_choice")
		var choice: Dictionary = untyped_choice
		if (
			not choice.has("half_index")
			or not choice.has("context")
			or not choice.has("suit")
		):
			return _choice_error(&"malformed_joker_choice")
		var half_index_value: Variant = choice["half_index"]
		if not half_index_value is int or half_index_value < 0 or half_index_value > 1:
			return _choice_error(&"invalid_joker_half_index")
		var half_index: int = half_index_value
		if choices_by_half.has(half_index):
			return _choice_error(&"duplicate_joker_choice")
		if not card.half_at(half_index).is_joker():
			return _choice_error(&"joker_choice_for_normal_half")
		var context_value: Variant = choice["context"]
		var suit_value: Variant = choice["suit"]
		var rank_value: Variant = choice.get("rank", card.half_at(half_index).joker_rank)
		var error := HalfCardState.joker_choice_error(context_value, suit_value, rank_value)
		if not error.is_empty():
			return _choice_error(error)
		if context_value not in active_contexts:
			return _choice_error(&"joker_context_not_active")
		choices_by_half[half_index] = {
			"context": context_value,
			"suit": suit_value,
			"rank": rank_value,
		}

	for half_index in range(2):
		if card.half_at(half_index).is_joker() and not choices_by_half.has(half_index):
			return _choice_error(&"joker_choice_required")
	return {"ok": true, "error_code": &"", "choices_by_half": choices_by_half}


static func _choice_error(error_code: StringName) -> Dictionary:
	return {"ok": false, "error_code": error_code, "choices_by_half": {}}


static func _invalid(error_code: StringName) -> ScoringTypes.SubmissionResult:
	var no_cards: Array[FullCardState] = []
	var no_faces: Array[ScoringTypes.SelectedCardFace] = []
	var no_resolved: Array[Dictionary] = []
	return ScoringTypes.SubmissionResult.new(
		false, error_code, no_cards, no_faces, no_resolved, null, null, null
	)
