class_name FieldEffectResolver
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")

const ADDITIONAL_CONTEXT := &"additional_context"
const PER_SELECTED_SUIT := &"per_selected_suit"
const PER_SELECTED_RANK_SET := &"per_selected_rank_set"
const STRICT_CONTEXT_MAJORITY := &"strict_context_majority"


static func validate_rule(parameters: Dictionary) -> StringName:
	var raw_rule: Variant = parameters.get("field_rule")
	if not (raw_rule is String or raw_rule is StringName):
		return &"invalid_field_rule"
	var rule := StringName(str(raw_rule))
	match rule:
		ADDITIONAL_CONTEXT:
			return &"" if _valid_context(parameters.get("context")) else &"invalid_field_context"
		PER_SELECTED_SUIT:
			if not _valid_suit(parameters.get("suit")):
				return &"invalid_field_suit"
			return _validate_delta(parameters)
		PER_SELECTED_RANK_SET:
			if not _valid_rank_set(parameters.get("ranks")):
				return &"invalid_field_ranks"
			return _validate_delta(parameters)
		STRICT_CONTEXT_MAJORITY:
			if not _valid_context(parameters.get("context")):
				return &"invalid_field_context"
			return _validate_delta(parameters)
		_:
			return &"unknown_field_rule"


static func active_contexts(base_context: int, fields: Array) -> PackedInt32Array:
	var included := {base_context: true}
	for field in fields:
		if field == null or field.ability == null:
			continue
		var parameters: Dictionary = field.ability.definition.effect_parameters
		if StringName(str(parameters.get("field_rule", ""))) != ADDITIONAL_CONTEXT:
			continue
		var context: Variant = parameters.get("context")
		if _valid_context(context):
			included[int(context)] = true
	var result := PackedInt32Array()
	for context in included:
		result.append(int(context))
	result.sort()
	return result


static func score_components(
	faces: Array[ScoringTypes.SelectedCardFace],
	context_counts: Dictionary,
	fields: Array
) -> Array[ScoringTypes.MultiplierComponent]:
	var result: Array[ScoringTypes.MultiplierComponent] = []
	for field in fields:
		if field == null or field.ability == null:
			continue
		var definition = field.ability.definition
		var parameters: Dictionary = definition.effect_parameters
		if not validate_rule(parameters).is_empty():
			continue
		var matches := 0
		match StringName(str(parameters.field_rule)):
			PER_SELECTED_SUIT:
				for face in faces:
					if face.suit == int(parameters.suit):
						matches += 1
			PER_SELECTED_RANK_SET:
				for face in faces:
					if face.rank > 0 and face.rank in parameters.ranks:
						matches += 1
			STRICT_CONTEXT_MAJORITY:
				if _is_strict_context_majority(int(parameters.context), context_counts):
					matches = 1
			_:
				continue
		if matches == 0:
			continue
		result.append(ScoringTypes.MultiplierComponent.new(
			&"field", &"field", definition.id,
			Rational.new(int(parameters.numerator) * matches, int(parameters.denominator))
		))
	return result


static func _validate_delta(parameters: Dictionary) -> StringName:
	if not parameters.get("numerator") is int or not parameters.get("denominator") is int:
		return &"invalid_field_delta"
	if int(parameters.denominator) == 0:
		return &"zero_denominator"
	if int(parameters.numerator) == 0:
		return &"zero_field_delta"
	return &""


static func _valid_context(value: Variant) -> bool:
	return (
		value is int
		and value >= GameTypes.Context.RISE
		and value <= GameTypes.Context.FALL
	)


static func _valid_suit(value: Variant) -> bool:
	return (
		value is int
		and value >= GameTypes.Suit.MOUNTAIN
		and value <= GameTypes.Suit.SEA
	)


static func _valid_rank_set(value: Variant) -> bool:
	if not value is Array or value.is_empty():
		return false
	var seen := {}
	for rank in value:
		if not rank is int or rank < 1 or rank > 10 or seen.has(rank):
			return false
		seen[rank] = true
	return true


static func _is_strict_context_majority(context: int, counts: Dictionary) -> bool:
	var target := _context_count(counts, context)
	for other_context in range(GameTypes.Context.RISE, GameTypes.Context.FALL + 1):
		if other_context != context and target <= _context_count(counts, other_context):
			return false
	return true


static func _context_count(counts: Dictionary, context: int) -> int:
	return int(counts.get(context, counts.get(str(context), 0)))
