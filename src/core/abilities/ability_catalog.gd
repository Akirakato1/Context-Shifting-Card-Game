class_name AbilityCatalog
extends RefCounted

const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const GameTypes = preload("res://src/core/common/game_types.gd")
const MAX_RECIPE_COPIES_PER_ABILITY := 20
const MIN_LOBBY_DECK_SIZE := 12


static func manipulation_designs() -> Array[AbilityDefinition]:
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
				"eligible": [GameTypes.Suit.MOUNTAIN, GameTypes.Suit.CLOUD, GameTypes.Suit.SEA],
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
	return designs


static func hand_shape_designs() -> Array[AbilityDefinition]:
	var result: Array[AbilityDefinition] = []
	var categories := [
		[&"card_hand", &"high_card", "High Card"],
		[&"card_hand", &"straight", "Straight"],
		[&"card_hand", &"family", "Family"],
		[&"card_hand", &"group", "Group"],
		[&"card_hand", &"flush", "Flush"],
		[&"context_hand", &"single_context", "Single Context"],
		[&"context_hand", &"two_context", "Two Context"],
		[&"context_hand", &"three_context", "Three Context"],
	]
	for item in categories:
		for sign_value in [1, -1]:
			var suffix := "buff" if sign_value > 0 else "nerf"
			var signed_text := "+3" if sign_value > 0 else "-3"
			var factor_text := "Card Hand" if item[0] == &"card_hand" else "Context Hand"
			result.append(AbilityDefinition.new(
				StringName("%s_%s" % [item[1], suffix]),
				AbilityDefinition.Timing.HAND_SHAPE,
				[&"hand_shape", StringName(suffix)],
				&"factor_modifier", 0, &"",
				{"factor_id": item[0], "category_id": item[1],
				"numerator": 3 * sign_value, "denominator": 1},
				{"steps": [{"key": "target_player_id", "kind": "player", "count": 1,
				"prompt": "Select a player"}]},
				"%s %s" % [item[2], "Buff" if sign_value > 0 else "Nerf"],
				"Target player gets %s %s multiplier if their %s category applies this round." % [signed_text, factor_text, item[2]]
			))
	return result


static func field_designs() -> Array[AbilityDefinition]:
	var result: Array[AbilityDefinition] = []
	var contexts := [
		[&"rise", "Rise", GameTypes.Context.RISE],
		[&"flourish", "Flourish", GameTypes.Context.FLOURISH],
		[&"fall", "Fall", GameTypes.Context.FALL],
	]
	for item in contexts:
		result.append(_field_definition(
			StringName("shift_to_%s" % item[0]), "Shift to %s" % item[1],
			"Move the active context to %s immediately. Do not change the cycle direction." % item[1],
			&"context_jump", AbilityDefinition.FIELD_DURATION_INSTANT,
			{"context": item[2]}
		))
	result.append(_field_definition(
		&"reverse_cycle", "Reverse Cycle",
		"Reverse the context clock direction without changing the current context.",
		&"reverse_direction", AbilityDefinition.FIELD_DURATION_PERSISTENT, {}, &"direction"
	))
	for item in contexts:
		result.append(_field_definition(
			StringName("%s_resonance" % item[0]), "%s Resonance" % item[1],
			"In addition to the currently active contexts, activate %s for this round without moving the clock." % item[1],
			&"field_rule", 1,
			{"field_rule": &"additional_context", "context": item[2]}
		))
	for item in [
		[&"mountain_favor", "Mountain", GameTypes.Suit.MOUNTAIN],
		[&"cloud_favor", "Cloud", GameTypes.Suit.CLOUD],
		[&"sea_favor", "Sea", GameTypes.Suit.SEA],
	]:
		result.append(_field_definition(
			item[0], "%s Favor" % item[1],
			"Add +0.1 to each player's field multiplier per submitted scoring face with %s." % item[1],
			&"field_rule", 3,
			{"field_rule": &"per_selected_suit", "suit": item[2],
			"numerator": 1, "denominator": 10}
		))
	for item in [
		[&"even_rank_favor", "Even Rank Favor", [2, 4, 6, 8, 10], "even"],
		[&"odd_rank_favor", "Odd Rank Favor", [1, 3, 5, 7, 9], "odd"],
	]:
		result.append(_field_definition(
			item[0], item[1],
			"Add +0.1 to each player's field multiplier per submitted non-Joker scoring face with an %s rank." % item[3],
			&"field_rule", 3,
			{"field_rule": &"per_selected_rank_set", "ranks": item[2],
			"numerator": 1, "denominator": 10}
		))
	for item in contexts:
		result.append(_field_definition(
			StringName("%s_ascendancy" % item[0]), "%s Ascendancy" % item[1],
			"Add +0.25 to a player's field multiplier when %s has the strictly highest context tally in their submitted hand." % item[1],
			&"field_rule", 3,
			{"field_rule": &"strict_context_majority", "context": item[2],
			"numerator": 1, "denominator": 4}
		))
	return result


static func sabotage_designs() -> Array[AbilityDefinition]:
	return [
		_sabotage_definition(
			&"forced_mulligan", "Forced Mulligan",
			"Target opponent replaces 1 random full card. The game randomly chooses both replacement context piles; both choices may be the same.",
			&"force_redraw"
		),
		_sabotage_definition(
			&"crossed_wires", "Crossed Wires",
			"The game chooses 2 distinct random full cards in the target's hand. On each card, swap the contexts of its two halves.",
			&"sabotage_cards", {"operation": &"exchange_contexts", "card_count": 2}
		),
		_sabotage_definition(
			&"suit_scramble", "Suit Scramble",
			"Randomize the suit of 1 random non-Joker half in the target's hand. Its current suit can be rolled again.",
			&"sabotage_cards", {"operation": &"randomize_suit", "half_count": 1}
		),
		_sabotage_definition(
			&"rank_scramble", "Rank Scramble",
			"Randomize the rank of 1 random non-Joker half in the target's hand from 1–10. Its current rank can be rolled again.",
			&"sabotage_cards", {"operation": &"randomize_rank", "half_count": 1,
			"ranks": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]}
		),
		_sabotage_definition(
			&"context_scramble", "Context Scramble",
			"Randomize the context of 1 random non-Joker half in the target's hand. Its current context can be rolled again.",
			&"sabotage_cards", {"operation": &"randomize_context", "half_count": 1,
			"contexts": [GameTypes.Context.RISE, GameTypes.Context.FLOURISH, GameTypes.Context.FALL]}
		),
		_sabotage_definition(
			&"rank_nudge", "Rank Nudge",
			"Move the rank of 1 random non-Joker half up or down by 1 at random. Rank movement wraps between 1 and 10.",
			&"sabotage_cards", {"operation": &"nudge_rank", "amount": 1,
			"wrap_min": 1, "wrap_max": 10}
		),
		_sabotage_definition(
			&"context_nudge", "Context Nudge",
			"Move the context of 1 random non-Joker half one step with or against the current context-clock direction, chosen at random.",
			&"sabotage_cards", {"operation": &"nudge_context", "amount": 1,
			"direction_mode": &"random_relative"}
		),
		_sabotage_definition(
			&"loose_pairing", "Loose Pairing",
			"The game chooses 2 distinct random full cards in the target's hand and swaps 1 random complete half-card between them.",
			&"sabotage_cards", {"operation": &"swap_halves", "card_count": 2,
			"half_from_each": 1}
		),
		_sabotage_definition(
			&"momentary_lock", "Momentary Lock",
			"Lock 1 random full card in the target's hand. That card cannot be submitted this round.",
			&"sabotage_cards", {"operation": &"lock_card", "card_count": 1,
			"expires": &"round_end"}
		),
	]


static func all_designs() -> Array[AbilityDefinition]:
	var result := manipulation_designs()
	result.append_array(hand_shape_designs())
	result.append_array(field_designs())
	result.append_array(sabotage_designs())
	return result


static func public_catalog(recipe: Dictionary) -> Dictionary:
	var catalog := {}
	for definition in all_designs():
		var id := str(definition.id)
		catalog[id] = {
			"id": id,
			"label": definition.display_name,
			"display_name": definition.display_name,
			"rules_text": definition.rules_text,
			"timing": definition.timing,
			"tags": definition.tags.map(func(tag): return str(tag)),
			"field_duration": definition.field_duration,
			"effect_id": str(definition.effect_id),
			"context_emblem": int(definition.effect_parameters.get("context", -1)),
			"choice_schema": definition.choice_schema,
			"copies": int(recipe.get(id, 0)),
		}
	return catalog


static func provisional_deck_recipe() -> Dictionary:
	var recipe := {}
	for definition in manipulation_designs(): recipe[definition.id] = 3
	for id in [&"context_roulette", &"ride_the_cycle", &"against_the_cycle"]:
		recipe[id] = 4
	for definition in hand_shape_designs(): recipe[definition.id] = 1
	recipe[&"high_card_buff"] = 2
	recipe[&"high_card_nerf"] = 2
	for definition in field_designs(): recipe[definition.id] = 1
	for definition in sabotage_designs(): recipe[definition.id] = 1
	for id in [&"suit_scramble", &"rank_scramble", &"context_scramble"]:
		recipe[id] = 2
	return recipe


static func build_deck(recipe: Dictionary) -> Array[AbilityDefinition]:
	var by_id := {}
	for definition in all_designs(): by_id[definition.id] = definition
	for raw_id in recipe:
		var id := StringName(str(raw_id))
		var count: Variant = recipe[raw_id]
		if not by_id.has(id) or not count is int or count <= 0: return []
	var result: Array[AbilityDefinition] = []
	var ids: Array = recipe.keys()
	ids.sort_custom(func(left, right): return str(left) < str(right))
	for raw_id in ids:
		var definition: AbilityDefinition = by_id[StringName(str(raw_id))]
		for _copy_index in range(recipe[raw_id]): result.append(definition)
	return result


static func manipulation_definitions(copies_per_design: int = 2) -> Array[AbilityDefinition]:
	if copies_per_design <= 0: return []
	var recipe := {}
	for definition in manipulation_designs(): recipe[definition.id] = copies_per_design
	return build_deck(recipe)


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


static func _field_definition(
	id: StringName,
	display_name: String,
	rules_text: String,
	effect_id: StringName,
	duration: int,
	parameters: Dictionary = {},
	conflict_group: StringName = &""
) -> AbilityDefinition:
	return AbilityDefinition.new(
		id,
		AbilityDefinition.Timing.FIELD,
		[&"field"],
		effect_id,
		duration,
		conflict_group,
		parameters,
		{"steps": []},
		display_name,
		rules_text
	)


static func _sabotage_definition(
	id: StringName,
	display_name: String,
	rules_text: String,
	effect_id: StringName,
	parameters: Dictionary = {}
) -> AbilityDefinition:
	return AbilityDefinition.new(
		id,
		AbilityDefinition.Timing.SABOTAGE,
		[&"sabotage", &"single_target"],
		effect_id,
		0,
		&"",
		parameters,
		{"steps": [{
			"key": "target_player_id", "kind": "player", "count": 1,
			"prompt": "Select an opponent",
		}]},
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
