extends "res://tests/test_case.gd"

const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const AbilityDeckState = preload("res://src/core/abilities/ability_deck_state.gd")
const AbilityState = preload("res://src/core/abilities/ability_state.gd")
const GameTypes = preload("res://src/core/common/game_types.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")


func test_manipulation_catalog_has_fourteen_unique_designs_and_two_copies_each() -> void:
	var definitions: Array[AbilityDefinition] = AbilityCatalog.manipulation_definitions()
	var counts := {}
	for definition in definitions:
		counts[definition.id] = int(counts.get(definition.id, 0)) + 1
		assert_eq(definition.timing, AbilityDefinition.Timing.HAND_MANIPULATION)
		assert_eq(definition.effect_id, &"manipulate_cards")

	assert_eq(definitions.size(), 28)
	assert_eq(counts.size(), 14)
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


func test_hand_shape_cards_use_public_player_target_schema_and_placeholder_three() -> void:
	for definition in AbilityCatalog.hand_shape_designs():
		assert_eq(definition.timing, AbilityDefinition.Timing.HAND_SHAPE)
		assert_eq(definition.effect_id, &"factor_modifier")
		assert_eq(abs(definition.effect_parameters.numerator), 3)
		assert_eq(definition.effect_parameters.denominator, 1)
		assert_eq(definition.choice_schema.steps.size(), 1)
		assert_eq(definition.choice_schema.steps[0].kind, "player")


func test_definition_data_is_independent_from_physical_copy_recipe() -> void:
	var designs := AbilityCatalog.all_designs()
	var recipe := AbilityCatalog.provisional_deck_recipe()
	assert_eq(designs.size(), 30)
	assert_eq(recipe.size(), 30)
	for definition in designs:
		assert_false(definition.effect_parameters.has("copy_count"))


func test_custom_recipe_supports_different_counts_per_definition() -> void:
	var deck := AbilityCatalog.build_deck({&"high_card_buff": 3, &"flush_nerf": 1})
	var counts := {}
	for definition in deck: counts[definition.id] = counts.get(definition.id, 0) + 1
	assert_eq(counts, {&"high_card_buff": 3, &"flush_nerf": 1})


func test_unknown_noninteger_or_nonpositive_recipe_entries_reject() -> void:
	assert_eq(AbilityCatalog.build_deck({&"unknown": 1}), [])
	assert_eq(AbilityCatalog.build_deck({&"high_card_buff": 1.5}), [])
	assert_eq(AbilityCatalog.build_deck({&"high_card_buff": 0}), [])
	assert_eq(AbilityCatalog.build_deck({&"high_card_buff": -1}), [])


func test_manipulation_catalog_defines_exact_target_shapes_and_rules_text() -> void:
	var by_id := _definitions_by_id(AbilityCatalog.manipulation_definitions(1))
	assert_eq(by_id.size(), 14)
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
				assert_eq(int(step.get("count", 0)), 1)

	_assert_variable_step(by_id[&"context_roulette"], &"half_card", 1, 12)
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
