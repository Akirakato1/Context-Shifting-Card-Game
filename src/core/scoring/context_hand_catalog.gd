class_name ContextHandCatalog
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const ScoringCategories = preload("res://src/core/scoring/scoring_categories.gd")
const ContextHandDefinition = preload("res://src/core/scoring/context_hand_definition.gd")

const ALL_CONTEXT_TIERS := [
	[1, 10, 5, 4],
	[2, 20, 3, 2],
	[3, 40, 11, 4],
	[4, 90, 4, 1],
]
const SINGLE_CONTEXT_TIERS := [
	[5, 1, 5, 4],
	[6, 5, 11, 8],
	[7, 9, 3, 2],
	[8, 19, 13, 8],
	[9, 39, 15, 8],
	[10, 59, 17, 8],
	[11, 89, 5, 2],
	[12, 101, 11, 4],
]
const TWO_CONTEXT_TIERS := [
	[3, 30, 11, 8],
	[4, 60, 15, 8],
	[5, 100, 19, 8],
	[6, 130, 13, 4],
]
const CONTEXTS := [
	[GameTypes.Context.RISE, "rise"],
	[GameTypes.Context.FLOURISH, "flourish"],
	[GameTypes.Context.FALL, "fall"],
]


static func definitions() -> Array[ContextHandDefinition]:
	var result: Array[ContextHandDefinition] = []
	for tier in ALL_CONTEXT_TIERS:
		var threshold: int = tier[0]
		result.append(ContextHandDefinition.new(
			StringName("all_contexts_%d" % threshold), tier[1],
			{
				GameTypes.Context.RISE: threshold,
				GameTypes.Context.FLOURISH: threshold,
				GameTypes.Context.FALL: threshold,
			},
			Rational.new(tier[2], tier[3]), ScoringCategories.THREE_CONTEXT
		))
	for context_data in CONTEXTS:
		var context: int = context_data[0]
		var context_id: String = context_data[1]
		for tier in SINGLE_CONTEXT_TIERS:
			var threshold: int = tier[0]
			result.append(ContextHandDefinition.new(
				StringName("%s_%d" % [context_id, threshold]), tier[1],
				{context: threshold}, Rational.new(tier[2], tier[3]),
				ScoringCategories.SINGLE_CONTEXT
			))
	for first_index in range(CONTEXTS.size()):
		for second_index in range(first_index + 1, CONTEXTS.size()):
			var first_context: int = CONTEXTS[first_index][0]
			var second_context: int = CONTEXTS[second_index][0]
			var pair_id := "%s_%s" % [CONTEXTS[first_index][1], CONTEXTS[second_index][1]]
			for tier in TWO_CONTEXT_TIERS:
				var threshold: int = tier[0]
				result.append(ContextHandDefinition.new(
					StringName("%s_%d" % [pair_id, threshold]), tier[1],
					{first_context: threshold, second_context: threshold},
					Rational.new(tier[2], tier[3]), ScoringCategories.TWO_CONTEXT
				))
	return result
