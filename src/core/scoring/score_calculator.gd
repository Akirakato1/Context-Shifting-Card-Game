class_name ScoreCalculator
extends RefCounted

const Rational = preload("res://src/core/common/rational.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")

static func calculate(
	faces: Array[ScoringTypes.SelectedCardFace],
	normal: ScoringTypes.NormalHandResult,
	context: ScoringTypes.ContextHandResult,
	modifiers: Array[ScoringTypes.FactorModifier],
	field_components: Array[ScoringTypes.MultiplierComponent] = []
) -> ScoringTypes.ScoreBreakdown:
	var base_value := 0
	for face in faces:
		if not face.is_joker:
			base_value += face.rank

	var card_components: Array[ScoringTypes.MultiplierComponent] = []
	if normal != null: card_components.assign(normal.components)
	var context_components: Array[ScoringTypes.MultiplierComponent] = []
	if context != null and context.component != null: context_components.append(context.component)
	var card_unclamped := _sum_components(card_components, false)
	var context_unclamped := _sum_components(context_components, false)
	var field_unclamped := _sum_components(field_components, true)
	var applied: Array[ScoringTypes.FactorModifier] = []
	for modifier in modifiers:
		var components := _components_for_factor(
			modifier.factor_id, card_components, context_components, field_components
		)
		if not _contains_category(components, modifier.category_id):
			continue
		match modifier.factor_id:
			&"card_hand": card_unclamped = card_unclamped.added(modifier.delta)
			&"context_hand": context_unclamped = context_unclamped.added(modifier.delta)
			&"field": field_unclamped = field_unclamped.added(modifier.delta)
			_: continue
		applied.append(modifier)
	var card_factor := _floor_to_one(card_unclamped)
	var context_factor := _floor_to_one(context_unclamped)
	var field_factor := _floor_to_one(field_unclamped)
	var raw := Rational.new(base_value, 1).multiplied(card_factor)
	raw = raw.multiplied(context_factor).multiplied(field_factor)
	return ScoringTypes.ScoreBreakdown.new(
		base_value, card_components, context_components, field_components, applied,
		card_unclamped, card_factor, context_unclamped, context_factor,
		field_unclamped, field_factor, raw, raw.ceiling()
	)


static func _sum_components(components: Array[ScoringTypes.MultiplierComponent], neutral_one: bool) -> Rational:
	var result := Rational.new(1 if neutral_one else 0, 1)
	for component in components: result = result.added(component.value)
	return result


static func _floor_to_one(value: Rational) -> Rational:
	var one := Rational.new(1, 1)
	return one if value.compare_to(one) < 0 else value


static func _contains_category(components: Array, category_id: StringName) -> bool:
	for component in components:
		if component.category_id == category_id: return true
	return false


static func _components_for_factor(
	factor_id: StringName,
	card_components: Array[ScoringTypes.MultiplierComponent],
	context_components: Array[ScoringTypes.MultiplierComponent],
	field_components: Array[ScoringTypes.MultiplierComponent]
) -> Array:
	match factor_id:
		&"card_hand": return card_components
		&"context_hand": return context_components
		&"field": return field_components
	return []
