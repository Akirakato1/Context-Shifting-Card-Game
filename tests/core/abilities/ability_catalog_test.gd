extends "res://tests/test_case.gd"

const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const AbilityDeckState = preload("res://src/core/abilities/ability_deck_state.gd")
const AbilityState = preload("res://src/core/abilities/ability_state.gd")
const GameTypes = preload("res://src/core/common/game_types.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")


func test_manipulation_catalog_has_seventeen_unique_designs_and_two_copies_each() -> void:
	var definitions: Array[AbilityDefinition] = AbilityCatalog.manipulation_definitions()
	var counts := {}
	for definition in definitions:
		counts[definition.id] = int(counts.get(definition.id, 0)) + 1
		assert_eq(definition.timing, AbilityDefinition.Timing.HAND_MANIPULATION)
		assert_eq(definition.effect_id, &"manipulate_cards")

	assert_eq(definitions.size(), 34)
	assert_eq(counts.size(), 17)
	for id in counts:
		assert_eq(counts[id], 2, "expected two copies of %s" % id)


func test_hand_shape_catalog_has_sixteen_unique_factor_category_sign_combinations() -> void:
	var definitions := AbilityCatalog.hand_shape_designs()
	var combinations := {}
	var card_count := 0
	var context_count := 0
	for definition in definitions:
		var parameters := definition.effect_parameters
		var key := "%s:%s:%d" % [parameters.factor_id, parameters.category_id, sign(parameters.numerator)]
		combinations[key] = true
		if parameters.factor_id == &"card_hand": card_count += 1
		if parameters.factor_id == &"context_hand": context_count += 1
	assert_eq(definitions.size(), 16)
	assert_eq(combinations.size(), 16)
	assert_eq(card_count, 10)
	assert_eq(context_count, 6)


func test_hand_shape_cards_target_players_and_adjust_the_factor_by_half() -> void:
	for definition in AbilityCatalog.hand_shape_designs():
		assert_eq(definition.timing, AbilityDefinition.Timing.HAND_SHAPE)
		assert_eq(definition.effect_id, &"factor_modifier")
		assert_eq(abs(definition.effect_parameters.numerator), 1)
		assert_eq(definition.effect_parameters.denominator, 2)
		assert_true(definition.rules_text.contains("0.5"))
		assert_eq(definition.choice_schema.steps.size(), 1)
		assert_eq(definition.choice_schema.steps[0].kind, "player")


func test_field_catalog_has_fifteen_valid_main_one_designs_without_prime_favor() -> void:
	var by_id := _definitions_by_id(AbilityCatalog.field_designs())
	assert_eq(by_id.size(), 15)
	assert_false(by_id.has(&"prime_rank_favor"))
	for definition: AbilityDefinition in by_id.values():
		assert_eq(definition.timing, AbilityDefinition.Timing.FIELD)
		assert_true(definition.allows_phase(GameTypes.Phase.MAIN_1))
		assert_false(definition.allows_phase(GameTypes.Phase.MAIN_2))
		assert_false(definition.display_name.is_empty())
		assert_false(definition.rules_text.is_empty())
		assert_eq(definition.choice_schema.get("steps", []), [])

	for id in [&"shift_to_rise", &"shift_to_flourish", &"shift_to_fall"]:
		assert_eq(by_id[id].field_duration, AbilityDefinition.FIELD_DURATION_INSTANT)
		assert_eq(by_id[id].effect_id, &"context_jump")
	assert_eq(by_id.reverse_cycle.field_duration, AbilityDefinition.FIELD_DURATION_PERSISTENT)
	assert_eq(by_id.reverse_cycle.effect_id, &"reverse_direction")
	assert_eq(by_id.reverse_cycle.conflict_group, &"direction")

	for id in [&"rise_resonance", &"flourish_resonance", &"fall_resonance"]:
		assert_eq(by_id[id].field_duration, 1)
		assert_eq(by_id[id].effect_id, &"field_rule")
		assert_eq(by_id[id].effect_parameters.field_rule, &"additional_context")
	for id in [
		&"mountain_favor", &"cloud_favor", &"sea_favor",
		&"even_rank_favor", &"odd_rank_favor",
		&"rise_ascendancy", &"flourish_ascendancy", &"fall_ascendancy",
	]:
		assert_eq(by_id[id].field_duration, 3)
		assert_eq(by_id[id].effect_id, &"field_rule")


func test_suit_favors_use_semantic_ids_names_rules_and_parameters() -> void:
	var by_id := _definitions_by_id(AbilityCatalog.field_designs())
	var expected := {
		&"mountain_favor": ["Mountain Favor", "Mountain", GameTypes.Suit.MOUNTAIN],
		&"cloud_favor": ["Cloud Favor", "Cloud", GameTypes.Suit.CLOUD],
		&"sea_favor": ["Sea Favor", "Sea", GameTypes.Suit.SEA],
	}
	for id in expected:
		var definition: AbilityDefinition = by_id.get(id)
		assert_true(definition != null)
		assert_eq(definition.display_name, expected[id][0])
		assert_true(definition.rules_text.contains(expected[id][1]))
		assert_eq(definition.effect_parameters.suit, expected[id][2])
	for numbered_id in [&"suit_1_favor", &"suit_2_favor", &"suit_3_favor"]:
		assert_false(by_id.has(numbered_id))


func test_sabotage_catalog_has_nine_single_opponent_main_one_designs() -> void:
	var by_id := _definitions_by_id(AbilityCatalog.sabotage_designs())
	assert_eq(by_id.size(), 9)
	for id in [
		&"forced_mulligan", &"crossed_wires", &"suit_scramble",
		&"rank_scramble", &"context_scramble", &"rank_nudge",
		&"context_nudge", &"loose_pairing", &"momentary_lock",
	]:
		assert_true(by_id.has(id))
		var definition: AbilityDefinition = by_id[id]
		assert_eq(definition.timing, AbilityDefinition.Timing.SABOTAGE)
		assert_true(&"sabotage" in definition.tags)
		assert_true(&"single_target" in definition.tags)
		assert_true(definition.allows_phase(GameTypes.Phase.MAIN_1))
		assert_false(definition.allows_phase(GameTypes.Phase.MAIN_2))
		assert_false(definition.display_name.is_empty())
		assert_false(definition.rules_text.is_empty())
		assert_eq(definition.choice_schema.steps.size(), 1)
		assert_eq(definition.choice_schema.steps[0].kind, "player")
	assert_eq(by_id.forced_mulligan.effect_id, &"force_redraw")
	for id in by_id:
		if id != &"forced_mulligan":
			assert_eq(by_id[id].effect_id, &"sabotage_cards")


func test_definition_data_is_independent_from_physical_copy_recipe() -> void:
	var designs := AbilityCatalog.all_designs()
	var recipe := AbilityCatalog.provisional_deck_recipe()
	var deck := AbilityCatalog.build_deck(recipe)
	var category_counts := {
		AbilityDefinition.Timing.HAND_MANIPULATION: 0,
		AbilityDefinition.Timing.HAND_SHAPE: 0,
		AbilityDefinition.Timing.SABOTAGE: 0,
		AbilityDefinition.Timing.FIELD: 0,
	}
	var copy_counts := {}
	for definition in deck:
		category_counts[definition.timing] += 1
		copy_counts[definition.id] = int(copy_counts.get(definition.id, 0)) + 1
	assert_eq(designs.size(), 57)
	assert_eq(recipe.size(), 51)
	for definition in designs:
		assert_false(definition.effect_parameters.has("copy_count"))
	assert_eq(deck.size(), 100)
	assert_eq(category_counts[AbilityDefinition.Timing.HAND_MANIPULATION], 65)
	assert_eq(category_counts[AbilityDefinition.Timing.HAND_SHAPE], 12)
	assert_eq(category_counts[AbilityDefinition.Timing.SABOTAGE], 10)
	assert_eq(category_counts[AbilityDefinition.Timing.FIELD], 13)
	for definition in AbilityCatalog.manipulation_designs():
		var copies := 3
		if definition.id in [
			&"context_roulette", &"ride_the_cycle", &"against_the_cycle",
			&"context_exchange", &"context_convergence", &"mirror_rank",
		]:
			copies = 4
		elif definition.id in [&"suit_imprint", &"suit_exchange", &"suit_shift", &"suit_roulette"]:
			copies = 5
		assert_eq(copy_counts.get(definition.id, 0), copies)
	for definition in AbilityCatalog.hand_shape_designs():
		assert_eq(copy_counts.get(definition.id, 0), 0 if definition.id in [
			&"high_card_buff", &"high_card_nerf", &"single_context_buff", &"single_context_nerf",
		] else 1)
	for definition in AbilityCatalog.sabotage_designs():
		assert_eq(copy_counts[definition.id], 2 if definition.id == &"suit_scramble" else 1)
	for definition in AbilityCatalog.field_designs():
		var count: int = recipe.get(definition.id, 0)
		assert_eq(count, 0 if definition.id in [
			&"even_rank_favor", &"odd_rank_favor",
		] else 1)
		assert_eq(copy_counts.get(definition.id, 0), count)


func test_custom_recipe_supports_different_counts_per_definition() -> void:
	var deck := AbilityCatalog.build_deck({&"high_card_buff": 3, &"flush_nerf": 1, &"even_rank_favor": 1})
	var counts := {}
	for definition in deck: counts[definition.id] = counts.get(definition.id, 0) + 1
	assert_eq(counts, {&"high_card_buff": 3, &"flush_nerf": 1, &"even_rank_favor": 1})


func test_unknown_noninteger_or_nonpositive_recipe_entries_reject() -> void:
	assert_eq(AbilityCatalog.build_deck({&"unknown": 1}), [])
	assert_eq(AbilityCatalog.build_deck({&"high_card_buff": 1.5}), [])
	assert_eq(AbilityCatalog.build_deck({&"high_card_buff": 0}), [])
	assert_eq(AbilityCatalog.build_deck({&"high_card_buff": -1}), [])


func test_manipulation_catalog_defines_exact_target_shapes_and_rules_text() -> void:
	var by_id := _definitions_by_id(AbilityCatalog.manipulation_definitions(1))
	assert_eq(by_id.size(), 17)
	for definition: AbilityDefinition in by_id.values():
		assert_false(definition.display_name.is_empty())
		assert_false(definition.rules_text.is_empty())
		var steps: Array = definition.choice_schema.get("steps", [])
		assert_true(not steps.is_empty(), "missing choice steps for %s" % definition.id)
		for step: Dictionary in steps:
			if step.has("min_count"):
				assert_true(int(step.min_count) >= 1)
				assert_true(int(step.max_count) >= int(step.min_count))
			else:
				assert_eq(int(step.get("count", 0)), 2 if definition.id == &"suit_exchange" else 1)

	_assert_variable_step(by_id[&"context_roulette"], &"half_card", 1, 12)
	for id in [&"suit_shift", &"suit_roulette"]:
		_assert_variable_step(by_id[id], &"half_card", 1, 2)
	for id in [&"low_roll", &"high_roll", &"even_roll", &"odd_roll", &"ride_the_cycle", &"against_the_cycle"]:
		_assert_variable_step(by_id[id], &"full_card", 1, 6)


func test_ability_display_metadata_survives_config_and_deck_round_trip() -> void:
	var definitions: Array[AbilityDefinition] = AbilityCatalog.manipulation_definitions()
	var original: AbilityDefinition = definitions[0]
	var restored_config := MatchConfig.from_dict(_config(definitions).to_dict())
	var restored_definition: AbilityDefinition = restored_config.ability_definitions[0]

	assert_eq(restored_definition.id, original.id)
	assert_eq(restored_definition.display_name, original.display_name)
	assert_eq(restored_definition.rules_text, original.rules_text)
	assert_eq(restored_definition.choice_schema, original.choice_schema)

	var deck := AbilityDeckState.new([
		AbilityState.new(&"copy-one", definitions[0]),
		AbilityState.new(&"copy-two", definitions[1]),
	])
	var restored_deck := AbilityDeckState.new([])
	restored_deck.load_dict(deck.to_dict())
	var restored_card: AbilityState = restored_deck.card_by_id(&"copy-one")
	assert_eq(restored_card.definition.display_name, definitions[0].display_name)
	assert_eq(restored_card.definition.rules_text, definitions[0].rules_text)
	assert_eq(restored_card.definition.choice_schema, definitions[0].choice_schema)


func _assert_variable_step(
	definition: AbilityDefinition,
	kind: StringName,
	minimum: int,
	maximum: int
) -> void:
	var steps: Array = definition.choice_schema.get("steps", [])
	assert_eq(steps.size(), 1)
	assert_eq(StringName(steps[0].get("kind", "")), kind)
	assert_eq(int(steps[0].get("min_count", 0)), minimum)
	assert_eq(int(steps[0].get("max_count", 0)), maximum)


func _definitions_by_id(definitions: Array[AbilityDefinition]) -> Dictionary:
	var result := {}
	for definition in definitions:
		result[definition.id] = definition
	return result


func _config(definitions: Array[AbilityDefinition]) -> MatchConfig:
	return MatchConfig.new(
		[&"one", &"two"],
		[],
		GameTypes.VictoryMode.SCORE_RACE,
		10,
		GameTypes.InformationVisibility.PUBLIC,
		{
			GameTypes.Phase.START: 5000,
			GameTypes.Phase.MAIN_1: 5000,
			GameTypes.Phase.HAND_PLAY: 5000,
			GameTypes.Phase.MAIN_2: 5000,
			GameTypes.Phase.END: 2000,
		},
		1000,
		5000,
		30000,
		definitions
	)
