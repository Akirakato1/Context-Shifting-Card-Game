extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")
const ContextHandDefinition = preload("res://src/core/scoring/context_hand_definition.gd")
const SubmissionEvaluator = preload("res://src/core/scoring/submission_evaluator.gd")
const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const AbilityState = preload("res://src/core/abilities/ability_state.gd")
const FieldState = preload("res://src/core/abilities/field_state.gd")


func test_selected_joker_is_valid_in_every_active_context_and_uses_submission_choice() -> void:
	for active_context in range(GameTypes.Context.RISE, GameTypes.Context.FALL + 1):
		var card := _joker_card(StringName("joker-%d" % active_context), GameTypes.Context.FLOURISH)
		var choices := [{
			"half_index": 0,
			"context": (active_context + 1) % 3,
			"suit": GameTypes.Suit.THREE,
		}]
		var result := SubmissionEvaluator.evaluate(
			[card], [_selection(card.card_id, 0, choices)], active_context,
			_normal_definitions(), _context_definitions(), []
		)

		assert_true(result.is_valid)
		assert_eq(result.error_code, &"")
		assert_true(result.normal_result.is_valid)
		assert_eq(result.normal_result.category_id, &"high_card")
		assert_eq(result.selected_faces[0].rank, 0)
		assert_eq(result.selected_faces[0].suit, GameTypes.Suit.THREE)
		assert_eq(result.resolved_cards[0]["halves"][0]["context"], choices[0]["context"])
		assert_eq(result.resolved_cards[0]["halves"][0]["suit"], GameTypes.Suit.THREE)
		assert_eq(result.score_breakdown.base_value, 0)


func test_double_joker_choices_resolve_independently_and_both_count_for_context() -> void:
	var card := FullCardState.new(
		&"double-joker",
		_joker_half(&"first-joker", GameTypes.Context.RISE),
		_joker_half(&"second-joker", GameTypes.Context.FLOURISH),
	)
	var choices := [
		{"half_index": 0, "context": GameTypes.Context.RISE, "suit": GameTypes.Suit.ONE},
		{"half_index": 1, "context": GameTypes.Context.FALL, "suit": GameTypes.Suit.TWO},
	]

	var result := SubmissionEvaluator.evaluate(
		[card], [_selection(card.card_id, 1, choices)], GameTypes.Context.FLOURISH,
		_normal_definitions(), _context_definitions(), []
	)

	assert_true(result.is_valid)
	assert_eq(result.selected_faces[0].rank, 0)
	assert_eq(result.selected_faces[0].suit, GameTypes.Suit.TWO)
	assert_eq(result.context_result.counts[GameTypes.Context.RISE], 1)
	assert_eq(result.context_result.counts[GameTypes.Context.FLOURISH], 0)
	assert_eq(result.context_result.counts[GameTypes.Context.FALL], 1)
	assert_eq(result.resolved_cards[0]["halves"][0]["joker"], true)
	assert_eq(result.resolved_cards[0]["halves"][1]["joker"], true)


func test_mixed_overridden_and_joker_submission_scores_without_mutating_inputs() -> void:
	var ordinary := _normal_card(
		&"ordinary", GameTypes.Context.FALL, 3, GameTypes.Suit.ONE,
		GameTypes.Context.FLOURISH, 4, GameTypes.Suit.TWO
	)
	ordinary.first.apply_overrides(GameTypes.Context.RISE, 8, GameTypes.Suit.THREE)
	var joker := _joker_card(&"joker", GameTypes.Context.RISE)
	var hand: Array[FullCardState] = [ordinary, joker]
	var selections := [
		_selection(ordinary.card_id, 0, []),
		_selection(joker.card_id, 0, [{
			"half_index": 0, "context": GameTypes.Context.FALL, "suit": GameTypes.Suit.TWO,
		}]),
	]
	var selections_before: Array = selections.duplicate(true)

	var result := SubmissionEvaluator.evaluate(
		hand, selections, GameTypes.Context.RISE,
		_normal_definitions(), _context_definitions(), []
	)

	assert_true(result.is_valid)
	assert_eq(result.submitted_cards.size(), 2)
	assert_eq(result.normal_result.category_id, &"high_card")
	assert_eq(result.normal_result.matched_faces[0].rank, 8)
	assert_eq(result.context_result.category_id, &"all_contexts_1")
	assert_eq(result.context_result.counts[GameTypes.Context.RISE], 2)
	assert_eq(result.context_result.counts[GameTypes.Context.FLOURISH], 1)
	assert_eq(result.context_result.counts[GameTypes.Context.FALL], 1)
	assert_eq(result.score_breakdown.base_value, 8)
	assert_eq(ordinary.first.base_context, GameTypes.Context.FALL)
	assert_eq(ordinary.first.effective_context(), GameTypes.Context.RISE)
	assert_eq(joker.first.base_context, GameTypes.Context.FALL)
	assert_eq(joker.first.base_rank, 0)
	assert_eq(joker.first.base_suit, HalfCardState.NO_SUIT)
	assert_eq(selections, selections_before)


func test_empty_submission_is_a_valid_zero_score_pass() -> void:
	var result := SubmissionEvaluator.evaluate(
		[], [], GameTypes.Context.RISE, _normal_definitions(), _context_definitions(), []
	)

	assert_true(result.is_valid)
	assert_false(result.normal_result.is_valid)
	assert_eq(result.context_result.category_id, &"no_context")
	assert_eq(result.score_breakdown.final_score, 0)


func test_resonance_extends_eligibility_without_moving_base_context() -> void:
	var card := _normal_card(
		&"flourish-only", GameTypes.Context.FLOURISH, 4, GameTypes.Suit.ONE,
		GameTypes.Context.FLOURISH, 7, GameTypes.Suit.TWO
	)
	var fields := [_field_state(&"flourish_resonance")]
	var result := SubmissionEvaluator.evaluate(
		[card], [_selection(card.card_id, 0, [])], GameTypes.Context.RISE,
		_normal_definitions(), _context_definitions(), [], fields
	)

	assert_true(result.is_valid)
	assert_eq(result.selected_faces[0].rank, 4)
	assert_eq(result.score_breakdown.field_components.size(), 0)


func test_score_fields_add_exact_components_and_pass_stays_neutral() -> void:
	var card := _normal_card(
		&"rise-even-suit", GameTypes.Context.RISE, 2, GameTypes.Suit.ONE,
		GameTypes.Context.RISE, 9, GameTypes.Suit.TWO
	)
	var fields := [
		_field_state(&"suit_1_favor"),
		_field_state(&"even_rank_favor"),
		_field_state(&"rise_ascendancy"),
	]
	var result := SubmissionEvaluator.evaluate(
		[card], [_selection(card.card_id, 0, [])], GameTypes.Context.RISE,
		_normal_definitions(), _context_definitions(), [], fields
	)

	assert_true(result.is_valid)
	assert_eq(result.score_breakdown.field_components.size(), 3)
	assert_eq(result.score_breakdown.field_unclamped.numerator, 29)
	assert_eq(result.score_breakdown.field_unclamped.denominator, 20)
	var pass_result := SubmissionEvaluator.evaluate(
		[card], [], GameTypes.Context.RISE,
		_normal_definitions(), _context_definitions(), [], fields
	)
	assert_true(pass_result.is_valid)
	assert_eq(pass_result.score_breakdown.field_components.size(), 0)
	assert_eq(pass_result.score_breakdown.field_factor.numerator, 1)
	assert_eq(pass_result.score_breakdown.field_factor.denominator, 1)


func test_joker_choice_validation_returns_stable_errors_without_mutation() -> void:
	var card := _joker_card(&"joker", GameTypes.Context.FLOURISH)
	var hand: Array[FullCardState] = [card]
	var valid_choice := {
		"half_index": 0, "context": GameTypes.Context.RISE, "suit": GameTypes.Suit.ONE,
	}
	var cases := [
		{"expected": &"joker_choice_required", "choices": []},
		{"expected": &"duplicate_joker_choice", "choices": [valid_choice, valid_choice.duplicate()]},
		{"expected": &"joker_choice_for_normal_half", "choices": [valid_choice, {
			"half_index": 1, "context": GameTypes.Context.FLOURISH, "suit": GameTypes.Suit.TWO,
		}]},
		{"expected": &"invalid_joker_half_index", "choices": [{
			"half_index": 2, "context": GameTypes.Context.RISE, "suit": GameTypes.Suit.ONE,
		}]},
		{"expected": &"invalid_joker_context", "choices": [{
			"half_index": 0, "context": "a", "suit": GameTypes.Suit.ONE,
		}]},
		{"expected": &"invalid_joker_context", "choices": [{
			"half_index": 0, "context": 3, "suit": GameTypes.Suit.ONE,
		}]},
		{"expected": &"invalid_joker_suit", "choices": [{
			"half_index": 0, "context": GameTypes.Context.RISE, "suit": "one",
		}]},
		{"expected": &"invalid_joker_suit", "choices": [{
			"half_index": 0, "context": GameTypes.Context.RISE, "suit": 3,
		}]},
	]

	for case in cases:
		var selections := [_selection(card.card_id, 0, case["choices"])]
		var selections_before: Array = selections.duplicate(true)
		var result := SubmissionEvaluator.evaluate(
			hand, selections, GameTypes.Context.RISE,
			_normal_definitions(), _context_definitions(), []
		)
		assert_false(result.is_valid)
		assert_eq(result.error_code, case["expected"])
		assert_eq(selections, selections_before)
		assert_eq(card.first.base_rank, 0)
		assert_eq(card.first.base_suit, HalfCardState.NO_SUIT)


func test_submission_validation_rejects_invalid_cards_and_selected_halves() -> void:
	var eligible := _normal_card(
		&"eligible", GameTypes.Context.RISE, 2, GameTypes.Suit.ONE,
		GameTypes.Context.FLOURISH, 3, GameTypes.Suit.TWO
	)
	var absent := _normal_card(
		&"absent", GameTypes.Context.RISE, 4, GameTypes.Suit.ONE,
		GameTypes.Context.FALL, 5, GameTypes.Suit.THREE
	)
	var ineligible := _normal_card(
		&"ineligible", GameTypes.Context.FLOURISH, 6, GameTypes.Suit.ONE,
		GameTypes.Context.FALL, 7, GameTypes.Suit.THREE
	)
	var hand: Array[FullCardState] = [eligible, ineligible]
	var cases := [
		{"expected": &"invalid_half_index", "selections": [_selection(eligible.card_id, 2, [])]},
		{"expected": &"duplicate_submitted_card", "selections": [
			_selection(eligible.card_id, 0, []), _selection(eligible.card_id, 0, []),
		]},
		{"expected": &"card_not_in_hand", "selections": [_selection(absent.card_id, 0, [])]},
		{"expected": &"card_not_eligible", "selections": [_selection(ineligible.card_id, 0, [])]},
		{"expected": &"selected_half_not_active", "selections": [_selection(eligible.card_id, 1, [])]},
	]

	for case in cases:
		var result := SubmissionEvaluator.evaluate(
			hand, case["selections"], GameTypes.Context.RISE,
			_normal_definitions(), _context_definitions(), []
		)
		assert_false(result.is_valid)
		assert_eq(result.error_code, case["expected"])

	var seven_cards: Array[FullCardState] = []
	var seven_selections: Array = []
	for index in range(7):
		var card := _normal_card(
			StringName("card-%d" % index), GameTypes.Context.RISE, index + 1, GameTypes.Suit.ONE,
			GameTypes.Context.FLOURISH, index + 1, GameTypes.Suit.TWO
		)
		seven_cards.append(card)
		seven_selections.append(_selection(card.card_id, 0, []))
	var oversized := SubmissionEvaluator.evaluate(
		seven_cards, seven_selections, GameTypes.Context.RISE,
		_normal_definitions(), _context_definitions(), []
	)
	assert_false(oversized.is_valid)
	assert_eq(oversized.error_code, &"submission_size_out_of_range")


func _selection(card_id: StringName, half_index: int, joker_choices: Array) -> Dictionary:
	return {"card_id": card_id, "half_index": half_index, "joker_choices": joker_choices}


func _joker_card(id: StringName, normal_context: int) -> FullCardState:
	return FullCardState.new(
		id,
		_joker_half(StringName("%s-joker" % id), GameTypes.Context.FALL),
		HalfCardState.new(
			StringName("%s-normal" % id), normal_context, 5, GameTypes.Suit.ONE
		),
	)


func _joker_half(id: StringName, origin_context: int) -> HalfCardState:
	return HalfCardState.new(
		id, origin_context, 0, HalfCardState.NO_SUIT, GameTypes.HalfKind.JOKER
	)


func _normal_card(
	id: StringName,
	first_context: int,
	first_rank: int,
	first_suit: int,
	second_context: int,
	second_rank: int,
	second_suit: int
) -> FullCardState:
	return FullCardState.new(
		id,
		HalfCardState.new(
			StringName("%s-first" % id), first_context, first_rank, first_suit
		),
		HalfCardState.new(
			StringName("%s-second" % id), second_context, second_rank, second_suit
		),
	)


func _normal_definitions() -> Array[NormalHandDefinition]:
	return [
		NormalHandDefinition.new(&"high_card", 10, 1, &"high_card", Rational.new(1, 1)),
		NormalHandDefinition.new(&"pair", 20, 2, &"pair", Rational.new(3, 2)),
	]


func _context_definitions() -> Array[ContextHandDefinition]:
	return [
		ContextHandDefinition.new(
			&"all_contexts_1", 10,
			{GameTypes.Context.RISE: 1, GameTypes.Context.FLOURISH: 1, GameTypes.Context.FALL: 1},
			Rational.new(2, 1)
		),
	]


func _field_state(definition_id: StringName) -> FieldState:
	for definition in AbilityCatalog.field_designs():
		if definition.id == definition_id:
			return FieldState.new(
				AbilityState.new(StringName("copy-%s" % definition_id), definition), &"one"
			)
	assert(false, "unknown field fixture")
	return null
