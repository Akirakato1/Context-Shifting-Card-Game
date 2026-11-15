class_name ScoreCalculator
extends RefCounted

const Rational = preload("res://src/core/common/rational.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")

const OPERATION_ADD := &"add"
const OPERATION_MULTIPLY := &"multiply"


static func calculate(
	faces: Array[ScoringTypes.SelectedCardFace],
	normal: ScoringTypes.NormalHandResult,
	context: ScoringTypes.ContextHandResult,
	modifiers: Array[ScoringTypes.ScoreModifier]
) -> ScoringTypes.ScoreBreakdown:
	var base_value := 0
	for face in faces:
		base_value += face.rank

	var before_modifiers := Rational.new(base_value, 1).multiplied(normal.multiplier)
	before_modifiers = before_modifiers.multiplied(context.multiplier)
	var current: Rational = before_modifiers
	var after_each: Array[Rational] = []
	for modifier in modifiers:
		match modifier.operation:
			OPERATION_ADD:
				current = current.added(modifier.value)
			OPERATION_MULTIPLY:
				current = current.multiplied(modifier.value)
			_:
				assert(false, "unknown score modifier operation: %s" % modifier.operation)
		after_each.append(current)

	var unclamped: Rational = current
	var clamped := unclamped.clamped_to_zero()
	return ScoringTypes.ScoreBreakdown.new(
		base_value,
		normal.multiplier,
		context.multiplier,
		before_modifiers,
		after_each,
		unclamped,
		clamped,
		clamped.ceiling()
	)
