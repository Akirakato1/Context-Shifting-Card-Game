class_name ContextHandEvaluator
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")
const ContextHandDefinition = preload("res://src/core/scoring/context_hand_definition.gd")


static func evaluate(
	cards: Array[FullCardState],
	definitions: Array[ContextHandDefinition]
) -> ScoringTypes.ContextHandResult:
	var contexts := PackedInt32Array()
	for card in cards:
		contexts.append(card.first.effective_context())
		contexts.append(card.second.effective_context())
	return evaluate_contexts(contexts, definitions)


static func evaluate_contexts(
	contexts: PackedInt32Array,
	definitions: Array[ContextHandDefinition]
) -> ScoringTypes.ContextHandResult:
	var counts := {
		GameTypes.Context.RISE: 0,
		GameTypes.Context.FLOURISH: 0,
		GameTypes.Context.FALL: 0,
	}
	for context in contexts:
		assert(counts.has(context), "unknown resolved context")
		counts[context] += 1

	var best: ContextHandDefinition = null
	for definition in definitions:
		if not _qualifies(counts, definition.minimums):
			continue
		if (
			best == null
			or definition.priority > best.priority
			or (
				definition.priority == best.priority
				and str(definition.id) < str(best.id)
			)
		):
			best = definition

	if best == null:
		return ScoringTypes.ContextHandResult.new(
			&"no_context", -1, Rational.new(1, 1), counts
		)
	return ScoringTypes.ContextHandResult.new(
		best.id, best.priority, best.multiplier, counts
	)


static func _qualifies(counts: Dictionary, minimums: Dictionary) -> bool:
	for context in minimums:
		if counts.get(context, 0) < minimums[context]:
			return false
	return true
