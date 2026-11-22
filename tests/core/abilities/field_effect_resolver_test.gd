extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const AbilityState = preload("res://src/core/abilities/ability_state.gd")
const FieldState = preload("res://src/core/abilities/field_state.gd")
const FieldEffectResolver = preload("res://src/core/abilities/field_effect_resolver.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")


func test_active_contexts_union_base_and_duplicate_resonance() -> void:
	var fields := [
		_field(&"flourish-one", {
			"field_rule": &"additional_context",
			"context": GameTypes.Context.FLOURISH,
		}),
		_field(&"flourish-two", {
			"field_rule": &"additional_context",
			"context": GameTypes.Context.FLOURISH,
		}),
	]

	assert_eq(
		FieldEffectResolver.active_contexts(GameTypes.Context.RISE, fields),
		PackedInt32Array([GameTypes.Context.RISE, GameTypes.Context.FLOURISH])
	)


func test_suit_favor_counts_selected_joker_suit_and_duplicates_stack_separately() -> void:
	var faces: Array[ScoringTypes.SelectedCardFace] = [
		_face(&"joker", 0, GameTypes.Suit.MOUNTAIN),
		_face(&"two", 2, GameTypes.Suit.MOUNTAIN),
		_face(&"three", 3, GameTypes.Suit.MOUNTAIN),
		_face(&"four", 4, GameTypes.Suit.CLOUD),
	]
	var parameters := {
		"field_rule": &"per_selected_suit", "suit": GameTypes.Suit.MOUNTAIN,
		"numerator": 1, "denominator": 10,
	}
	var components := FieldEffectResolver.score_components(
		faces, _counts(2, 3, 3), [
			_field(&"suit-one-a", parameters),
			_field(&"suit-one-b", parameters),
		]
	)

	assert_eq(components.size(), 2)
	for component in components:
		assert_eq(component.factor_id, &"field")
		assert_eq(component.category_id, &"field")
		assert_eq(component.value.numerator, 3)
		assert_eq(component.value.denominator, 10)


func test_rank_favors_partition_normal_ranks_and_ignore_joker_zero() -> void:
	var faces: Array[ScoringTypes.SelectedCardFace] = [_face(&"joker", 0, GameTypes.Suit.MOUNTAIN)]
	for rank in range(1, 11):
		faces.append(_face(StringName("rank-%d" % rank), rank, GameTypes.Suit.MOUNTAIN))
	var fields := [
		_field(&"even", _rank_parameters([2, 4, 6, 8, 10])),
		_field(&"odd", _rank_parameters([1, 3, 5, 7, 9])),
	]
	var components := FieldEffectResolver.score_components(faces, _counts(4, 4, 4), fields)

	assert_eq(components.size(), 2)
	assert_eq(components[0].source_definition_id, &"even")
	assert_eq(components[0].value.numerator, 1)
	assert_eq(components[0].value.denominator, 2)
	assert_eq(components[1].source_definition_id, &"odd")
	assert_eq(components[1].value.numerator, 1)
	assert_eq(components[1].value.denominator, 2)


func test_ascendancy_requires_a_strict_untied_context_maximum() -> void:
	var rise := _field(&"rise-ascendancy", {
		"field_rule": &"strict_context_majority",
		"context": GameTypes.Context.RISE,
		"numerator": 1,
		"denominator": 4,
	})

	var winning := FieldEffectResolver.score_components([], _counts(4, 2, 2), [rise])
	var tied := FieldEffectResolver.score_components([], _counts(4, 4, 0), [rise])

	assert_eq(winning.size(), 1)
	assert_eq(winning[0].value.numerator, 1)
	assert_eq(winning[0].value.denominator, 4)
	assert_eq(tied, [])


func test_zero_match_fields_emit_no_score_components() -> void:
	var suit_three := _field(&"suit-three", {
		"field_rule": &"per_selected_suit", "suit": GameTypes.Suit.SEA,
		"numerator": 1, "denominator": 10,
	})
	assert_eq(
		FieldEffectResolver.score_components(
			[_face(&"one", 1, GameTypes.Suit.MOUNTAIN)], _counts(1, 1, 0), [suit_three]
		),
		[]
	)


func test_field_rule_validation_reports_stable_errors() -> void:
	assert_eq(FieldEffectResolver.validate_rule({}), &"invalid_field_rule")
	assert_eq(
		FieldEffectResolver.validate_rule({"field_rule": &"unknown"}),
		&"unknown_field_rule"
	)
	assert_eq(
		FieldEffectResolver.validate_rule({"field_rule": &"additional_context"}),
		&"invalid_field_context"
	)
	assert_eq(
		FieldEffectResolver.validate_rule({
			"field_rule": &"per_selected_suit", "suit": 99,
			"numerator": 1, "denominator": 10,
		}),
		&"invalid_field_suit"
	)
	assert_eq(
		FieldEffectResolver.validate_rule({
			"field_rule": &"per_selected_rank_set", "ranks": [2, 2],
			"numerator": 1, "denominator": 10,
		}),
		&"invalid_field_ranks"
	)
	assert_eq(
		FieldEffectResolver.validate_rule({
			"field_rule": &"per_selected_rank_set", "ranks": [0, 2],
			"numerator": 1, "denominator": 10,
		}),
		&"invalid_field_ranks"
	)
	assert_eq(
		FieldEffectResolver.validate_rule({
			"field_rule": &"strict_context_majority",
			"context": GameTypes.Context.RISE,
			"numerator": 1, "denominator": 0,
		}),
		&"zero_denominator"
	)


func _field(id: StringName, parameters: Dictionary) -> FieldState:
	var definition := AbilityDefinition.new(
		id, AbilityDefinition.Timing.FIELD, [&"field"], &"field_rule", 3, &"",
		parameters
	)
	return FieldState.new(AbilityState.new(StringName("%s-copy" % id), definition), &"one")


func _face(id: StringName, rank: int, suit: int) -> ScoringTypes.SelectedCardFace:
	return ScoringTypes.SelectedCardFace.new(id, 0, rank, suit)


func _rank_parameters(ranks: Array) -> Dictionary:
	return {
		"field_rule": &"per_selected_rank_set", "ranks": ranks,
		"numerator": 1, "denominator": 10,
	}


func _counts(rise: int, flourish: int, fall: int) -> Dictionary:
	return {
		GameTypes.Context.RISE: rise,
		GameTypes.Context.FLOURISH: flourish,
		GameTypes.Context.FALL: fall,
	}
