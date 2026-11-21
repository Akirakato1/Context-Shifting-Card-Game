class_name AbilityCatalog
extends RefCounted

const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const GameTypes = preload("res://src/core/common/game_types.gd")


static func manipulation_definitions(copies_per_design: int = 2) -> Array[AbilityDefinition]:
	assert(copies_per_design > 0, "ability copy count must be positive")
	var designs: Array[AbilityDefinition] = [
		_definition(
			&"context_exchange", "Context Exchange",
			"Select 1 full card. Swap the contexts of its two halves.",
			&"context_exchange", {}, [_fixed_full_card_step()]
		),
		_definition(
			&"context_convergence", "Context Convergence",
			"Select 1 full card, then select 1 of its halves. That half becomes the same context as the other half.",
			&"context_convergence", {}, [
				_fixed_full_card_step(),
				{"key": "half_index", "kind": "half_index", "count": 1,
				"eligible": [0, 1], "prompt": "Select the half to change"},
			]
		),
		_definition(
			&"context_roulette", "Context Roulette",
			"Select any number of half-cards in your hand. Randomize each selected context. The current context can be rolled again.",
			&"random_context", {}, [{
				"key": "halves", "kind": "half_card", "min_count": 1,
				"max_count": 12, "prompt": "Select half-cards to randomize",
			}]
		),
		_definition(
			&"suit_imprint", "Suit Imprint",
			"Select 1 full card and 1 suit. Change both halves to that suit. Joker halves are unchanged.",
			&"suit_imprint", {}, [
				_fixed_full_card_step(),
				{"key": "suit", "kind": "suit", "count": 1,
				"eligible": [GameTypes.Suit.ONE, GameTypes.Suit.TWO, GameTypes.Suit.THREE],
				"prompt": "Choose a suit"},
			]
		),
		_fixed_context_definition(
			&"rise_infusion", "Rise Infusion", GameTypes.Context.RISE
		),
		_fixed_context_definition(
			&"flourish_infusion", "Flourish Infusion", GameTypes.Context.FLOURISH
		),
		_fixed_context_definition(
			&"fall_infusion", "Fall Infusion", GameTypes.Context.FALL
		),
		_rank_roll_definition(&"low_roll", "Low Roll", [1, 2, 3, 4, 5], "ranks 1–5"),
		_rank_roll_definition(&"high_roll", "High Roll", [6, 7, 8, 9, 10], "ranks 6–10"),
		_rank_roll_definition(&"even_roll", "Even Roll", [2, 4, 6, 8, 10], "an even rank"),
		_rank_roll_definition(&"odd_roll", "Odd Roll", [1, 3, 5, 7, 9], "an odd rank"),
		_cycle_definition(&"ride_the_cycle", "Ride the Cycle", 1,
			"Advance both halves one step in the context clock's current direction."),
		_cycle_definition(&"against_the_cycle", "Against the Cycle", -1,
			"Move both halves one step against the context clock's current direction."),
		_definition(
			&"mirror_rank", "Mirror Rank",
			"Select 1 full card. Mirror both ranks: 1↔10, 2↔9, 3↔8, 4↔7, and 5↔6.",
			&"mirror_rank", {}, [_fixed_full_card_step()]
		),
	]
	var result: Array[AbilityDefinition] = []
	for definition in designs:
		for _copy_index in range(copies_per_design):
			result.append(definition)
	return result


static func _definition(
	id: StringName,
	display_name: String,
	rules_text: String,
	operation: StringName,
	parameters: Dictionary,
	steps: Array
) -> AbilityDefinition:
	var effect_parameters := parameters.duplicate(true)
	effect_parameters["operation"] = operation
	return AbilityDefinition.new(
		id,
		AbilityDefinition.Timing.HAND_MANIPULATION,
		[&"manipulation"],
		&"manipulate_cards",
		0,
		&"",
		effect_parameters,
		{"steps": steps.duplicate(true)},
		display_name,
		rules_text
	)


static func _fixed_context_definition(
	id: StringName,
	display_name: String,
	context: int
) -> AbilityDefinition:
	return _definition(
		id,
		display_name,
		"Select 1 full card. Change both halves to %s. Joker halves are unchanged." % GameTypes.context_name(context),
		&"set_context",
		{"context": context},
		[_fixed_full_card_step()]
	)


static func _rank_roll_definition(
	id: StringName,
	display_name: String,
	ranks: Array,
	range_text: String
) -> AbilityDefinition:
	return _definition(
		id,
		display_name,
		"Select any number of full cards. Randomize both halves of each card to %s. Current ranks can be rolled again." % range_text,
		&"random_rank",
		{"ranks": ranks.duplicate()},
		[_variable_full_card_step()]
	)


static func _cycle_definition(
	id: StringName,
	display_name: String,
	relative_direction: int,
	effect_text: String
) -> AbilityDefinition:
	return _definition(
		id,
		display_name,
		"Select any number of full cards. %s" % effect_text,
		&"shift_context",
		{"relative_direction": relative_direction},
		[_variable_full_card_step()]
	)


static func _fixed_full_card_step() -> Dictionary:
	return {
		"key": "cards", "kind": "full_card", "count": 1,
		"prompt": "Select 1 full card",
	}


static func _variable_full_card_step() -> Dictionary:
	return {
		"key": "cards", "kind": "full_card", "min_count": 1,
		"max_count": 6, "prompt": "Select full cards",
	}
