extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const EventKinds = preload("res://src/core/events/event_kinds.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")


func test_main_one_readies_only_players_with_publicly_empty_ability_trays() -> void:
	var state := _main_one_state(301)
	state.phase = GameTypes.Phase.START
	state.players[&"one"].ability_hand.clear()
	for ability in state.players[&"two"].ability_hand:
		ability.definition = _ability(&"private", AbilityDefinition.Timing.HAND_MANIPULATION, &"noop")
	var controller := MatchController.new(state)
	controller.begin_match(0)
	assert_eq(state.phase, GameTypes.Phase.MAIN_1)
	assert_true(state.players[&"one"].ready, "An empty tray readies immediately on phase entry")
	assert_false(state.players[&"two"].ready, "A nonempty tray keeps its timing information private")
	controller.submit(GameCommand.new(&"unready", &"one", CommandKinds.SET_READY, {"ready": false}), 10)
	assert_true(state.players[&"one"].ready)
	controller.submit(_ready(&"ready-nonempty", &"two"), 20)
	assert_eq(state.phase, GameTypes.Phase.HAND_PLAY)


func test_last_public_ability_readies_empty_trays_but_keeps_reaction_window() -> void:
	var state := _main_one_state(302)
	state.players[&"one"].ability_hand.resize(1)
	state.players[&"two"].ability_hand.clear()
	_set_ability(state, &"one", 0, _ability(&"buff", AbilityDefinition.Timing.HAND_SHAPE, &"factor_modifier"))
	var controller := MatchController.new(state)
	var result := controller.submit(_play(
		&"last-public-ability", &"one", state.players[&"one"].ability_hand[0].copy_id, &"two"
	), 100)
	assert_true(result.accepted)
	assert_true(state.players[&"one"].ready, "The player who spent their last card is ready again")
	assert_true(state.players[&"two"].ready, "The empty opponent tray stays ready after a public action")
	controller.tick(1099)
	assert_eq(state.phase, GameTypes.Phase.MAIN_1)
	controller.tick(1100)
	assert_eq(state.phase, GameTypes.Phase.HAND_PLAY)


func test_empty_main_two_trays_allow_the_reveal_to_play_before_scoring() -> void:
	var state := _main_one_state(303)
	state.phase = GameTypes.Phase.HAND_PLAY
	state.phase_started_msec = 0
	state.phase_deadline_msec = 100
	for player in state.players.values():
		player.ability_hand.clear()
	var controller := MatchController.new(state, null, Callable(), false)
	var revealed := controller.tick(100)
	assert_true(_first_event(revealed, EventKinds.HAND_REVEALED) != null)
	assert_eq(state.phase, GameTypes.Phase.MAIN_2)
	assert_true(state.players[&"one"].ready)
	assert_true(state.players[&"two"].ready)
	assert_true(controller.tick(6099).is_empty())
	assert_eq(state.phase, GameTypes.Phase.MAIN_2)
	assert_true(_first_event(controller.tick(6100), EventKinds.ROUND_FINALIZED) != null)


func test_main_two_manual_ready_can_finalize_during_the_reveal() -> void:
	var state := _main_one_state(304)
	state.phase = GameTypes.Phase.HAND_PLAY
	state.phase_started_msec = 0
	state.phase_deadline_msec = 100
	state.players[&"one"].ability_hand.clear()
	for ability in state.players[&"two"].ability_hand:
		ability.definition = _ability(&"private", AbilityDefinition.Timing.HAND_MANIPULATION, &"noop")
	var controller := MatchController.new(state)
	controller.tick(100)
	assert_eq(state.phase, GameTypes.Phase.MAIN_2)
	assert_true(state.players[&"one"].ready)
	assert_false(state.players[&"two"].ready)
	var result := controller.submit(_ready(&"ready-nonempty", &"two"), 101)
	assert_true(_first_event(result.events, EventKinds.ROUND_FINALIZED) != null)


func test_public_action_clears_readiness_and_grace_delays_all_ready_close() -> void:
	var state := _main_one_state(31)
	_set_ability(state, &"one", 0, _ability(&"buff", AbilityDefinition.Timing.HAND_SHAPE, &"factor_modifier"))
	var controller := MatchController.new(state)
	controller.tick(0)
	controller.submit(_ready(&"r1", &"one"), 10)
	controller.submit(_ready(&"r2", &"two"), 20)
	assert_eq(state.phase, GameTypes.Phase.HAND_PLAY)

	# Re-open a fresh Main 1 to exercise an action before all-ready closes it.
	state = _main_one_state(32)
	_set_ability(state, &"one", 0, _ability(&"buff", AbilityDefinition.Timing.HAND_SHAPE, &"factor_modifier"))
	controller = MatchController.new(state)
	controller.tick(0)
	controller.submit(_ready(&"r1", &"one"), 10)
	var action := controller.submit(_play(
		&"buff-play", &"one", state.players[&"one"].ability_hand[0].copy_id, &"two",
		{"operation": &"add", "numerator": 1, "denominator": 1}
	), 100)
	assert_true(action.accepted)
	assert_false(state.players[&"one"].ready)
	assert_false(state.players[&"two"].ready)
	controller.submit(_ready(&"r3", &"one"), 110)
	controller.submit(_ready(&"r4", &"two"), 120)
	assert_eq(state.phase, GameTypes.Phase.MAIN_1)
	controller.tick(1099)
	assert_eq(state.phase, GameTypes.Phase.MAIN_1)
	controller.tick(1100)
	assert_eq(state.phase, GameTypes.Phase.HAND_PLAY)


func test_actions_at_hard_deadline_resolve_before_close_and_late_actions_reject() -> void:
	var at_limit := _main_one_state(33)
	_set_ability(at_limit, &"one", 0, _ability(&"buff", AbilityDefinition.Timing.HAND_SHAPE, &"factor_modifier"))
	var controller := MatchController.new(at_limit)
	controller.tick(0)
	var accepted := controller.submit(_play(
		&"at-limit", &"one", at_limit.players[&"one"].ability_hand[0].copy_id, &"one",
		{"operation": &"add", "numerator": 2, "denominator": 1}
	), 5000)
	assert_true(accepted.accepted)
	assert_eq(at_limit.players[&"one"].factor_modifiers.size(), 1)
	assert_eq(at_limit.phase, GameTypes.Phase.HAND_PLAY)
	assert_true(_first_event(accepted.events, EventKinds.PHASE_CHANGED) != null)

	var late := _main_one_state(34)
	_set_ability(late, &"one", 0, _ability(&"buff", AbilityDefinition.Timing.HAND_SHAPE, &"factor_modifier"))
	controller = MatchController.new(late)
	controller.tick(0)
	var rejected := controller.submit(_play(
		&"late", &"one", late.players[&"one"].ability_hand[0].copy_id, &"one",
		{"operation": &"add", "numerator": 2, "denominator": 1}
	), 5001)
	assert_false(rejected.accepted)
	assert_eq(rejected.error_code, &"phase_deadline_passed")
	assert_eq(late.players[&"one"].factor_modifiers.size(), 0)


func test_public_actions_resolve_in_host_receipt_order_and_modifiers_stack() -> void:
	var state := _main_one_state(35)
	_set_ability(state, &"one", 0, _ability(&"add", AbilityDefinition.Timing.HAND_SHAPE, &"factor_modifier"))
	_set_ability(state, &"two", 0, _ability(&"multiply", AbilityDefinition.Timing.HAND_SHAPE, &"factor_modifier"))
	var controller := MatchController.new(state)
	controller.tick(0)

	controller.submit(_play(
		&"first", &"one", state.players[&"one"].ability_hand[0].copy_id, &"one",
		{"operation": &"add", "numerator": 3, "denominator": 1}
	), 100)
	controller.submit(_play(
		&"second", &"two", state.players[&"two"].ability_hand[0].copy_id, &"one",
		{"operation": &"multiply", "numerator": 2, "denominator": 1}
	), 101)

	assert_eq(state.players[&"one"].factor_modifiers.size(), 2)
	assert_eq(state.players[&"one"].factor_modifiers[0].factor_id, &"card_hand")
	assert_eq(state.players[&"one"].factor_modifiers[1].category_id, &"high_card")


func test_hand_shape_modifier_targets_self_or_active_opponent_with_dynamic_player_choice() -> void:
	var state := _main_one_state(351)
	var definition: AbilityDefinition = AbilityCatalog.hand_shape_designs()[0]
	_set_ability(state, &"one", 0, definition)
	_set_ability(state, &"one", 1, definition)
	var controller := MatchController.new(state)
	controller.tick(0)
	for target in [&"one", &"two"]:
		var ability = state.players[&"one"].ability_hand[0]
		var result := controller.submit(GameCommand.new(
			StringName("dynamic-%s" % target), &"one", CommandKinds.PLAY_PUBLIC_ABILITY,
			{"copy_id": ability.copy_id, "target_player_id": target,
			"choices": {"target_player_id": [target]}}
		), 100)
		assert_true(result.accepted)
		assert_eq(state.players[target].factor_modifiers.size(), 1)


func test_forged_factor_fields_or_inactive_player_choice_reject_without_mutation() -> void:
	var state := _main_one_state(352)
	_set_ability(state, &"one", 0, AbilityCatalog.hand_shape_designs()[0])
	state.players[&"two"].pending = true
	var controller := MatchController.new(state)
	controller.tick(0)
	var before := state.to_dict()
	var ability = state.players[&"one"].ability_hand[0]
	var inactive := controller.submit(GameCommand.new(
		&"inactive", &"one", CommandKinds.PLAY_PUBLIC_ABILITY,
		{"copy_id": ability.copy_id, "target_player_id": &"two",
		"choices": {"target_player_id": [&"two"]}}
	), 10)
	assert_eq(inactive.error_code, &"invalid_ability_choice")
	assert_eq(state.to_dict(), before)
	for forged_key in ["factor_id", "category_id", "numerator", "applicable"]:
		var payload := {"copy_id": ability.copy_id, "target_player_id": &"one",
			"choices": {"target_player_id": [&"one"]}}
		payload[forged_key] = 999
		var forged := controller.submit(GameCommand.new(
			StringName("forged-%s" % forged_key), &"one", CommandKinds.PLAY_PUBLIC_ABILITY, payload
		), 11)
		assert_eq(forged.error_code, &"unexpected_effect_payload")
		assert_eq(state.to_dict(), before)


func test_main_one_pass_consumes_modifier_card_and_contributes_zero() -> void:
	var state := _main_one_state(353)
	_set_ability(state, &"one", 0, AbilityCatalog.hand_shape_designs()[0])
	var controller := MatchController.new(state)
	controller.tick(0)
	var copy_id: StringName = state.players[&"one"].ability_hand[0].copy_id
	assert_true(controller.submit(GameCommand.new(
		&"play-before-pass", &"one", CommandKinds.PLAY_PUBLIC_ABILITY,
		{"copy_id": copy_id, "target_player_id": &"one",
		"choices": {"target_player_id": [&"one"]}}
	), 100).accepted)
	assert_true(_held_copy(state.players[&"one"].ability_hand, copy_id) == null)
	controller.submit(_ready(&"pass-ready-one", &"one"), 110)
	controller.submit(_ready(&"pass-ready-two", &"two"), 120)
	controller.tick(1100)
	assert_eq(state.phase, GameTypes.Phase.HAND_PLAY)
	assert_true(controller.submit(GameCommand.new(
		&"stage-pass", &"one", CommandKinds.STAGE_HAND, {"cards": []}
	), 1101).accepted)
	assert_true(controller.submit(GameCommand.new(
		&"lock-pass", &"one", CommandKinds.LOCK_HAND, {}
	), 1102).accepted)
	assert_eq(state.players[&"one"].provisional_score.final_score, 0)
	assert_eq(state.players[&"one"].provisional_score.applied_modifiers.size(), 0)


func test_fields_coexist_conflicts_replace_and_clock_effects_are_immediate() -> void:
	var state := _main_one_state(36)
	_set_ability(state, &"one", 0, _field(&"rain", &"noop", &"weather"))
	_set_ability(state, &"one", 1, _field(&"sun", &"noop", &"weather"))
	_set_ability(state, &"two", 0, _field(&"gravity", &"noop", &"gravity"))
	var controller := MatchController.new(state)
	controller.tick(0)
	controller.submit(_play(&"rain", &"one", state.players[&"one"].ability_hand[0].copy_id), 10)
	controller.submit(_play(&"gravity", &"two", state.players[&"two"].ability_hand[0].copy_id), 11)
	assert_eq(state.ability_deck.active_fields().size(), 2)
	var replacement := controller.submit(_play(
		&"sun", &"one", state.players[&"one"].ability_hand[0].copy_id
	), 12)
	assert_eq(state.ability_deck.active_fields().size(), 2)
	assert_true(_first_event(replacement.events, EventKinds.FIELD_REPLACED) != null)

	var clock := _main_one_state(37)
	_set_ability(clock, &"one", 0, _field(&"jump", &"context_jump", &"clock"))
	_set_ability(clock, &"one", 1, _field(&"reverse", &"reverse_direction", &"direction"))
	controller = MatchController.new(clock)
	controller.tick(0)
	controller.submit(_play(
		&"jump", &"one", clock.players[&"one"].ability_hand[0].copy_id, &"", {"context": GameTypes.Context.FALL}
	), 10)
	assert_eq(clock.active_context, GameTypes.Context.FALL)
	controller.submit(_play(
		&"reverse", &"one", clock.players[&"one"].ability_hand[0].copy_id
	), 11)
	assert_eq(clock.active_context, GameTypes.Context.FALL)
	assert_eq(clock.context_direction, GameTypes.ContextDirection.REVERSE)
	clock.phase = GameTypes.Phase.START
	clock.round_number = 2
	clock.start_prepared_round = 0
	MatchController.new(clock)
	assert_eq(clock.active_context, GameTypes.Context.FLOURISH)


func test_sabotage_resolves_sequentially_and_projects_private_details() -> void:
	var state := _main_one_state(38)
	_set_ability(state, &"one", 0, _ability(&"sabotage-a", AbilityDefinition.Timing.SABOTAGE, &"force_redraw"))
	_set_ability(state, &"one", 1, _ability(&"sabotage-b", AbilityDefinition.Timing.SABOTAGE, &"force_redraw"))
	var controller := MatchController.new(state)
	controller.tick(0)

	var first := controller.submit(_play(
		&"s1", &"one", state.players[&"one"].ability_hand[0].copy_id, &"two"
	), 10)
	var latest_ids := _hand_ids(state.players[&"two"].hand)
	var second := controller.submit(_play(
		&"s2", &"one", state.players[&"one"].ability_hand[0].copy_id, &"two"
	), 11)

	assert_eq(state.players[&"two"].hand.size(), 6)
	var public_event = _audience_event(first.events, &"public")
	var target_event = _recipient_event(first.events, &"two")
	var attacker_event = _recipient_event(first.events, &"one")
	assert_eq(public_event.payload.target_player_id, "two")
	assert_eq(public_event.payload.ability_id, "sabotage-a")
	assert_false(public_event.payload.has("removed_card_id"))
	assert_true(target_event.payload.has("removed_card_id"))
	assert_false(attacker_event.payload.has("removed_card_id"))
	assert_true(attacker_event.payload.success)
	var second_target = _recipient_event(second.events, &"two")
	assert_true(latest_ids.has(StringName(second_target.payload.removed_card_id)))


func _main_one_state(seed_value: int) -> MatchState:
	var definitions: Array[AbilityDefinition] = []
	for index in range(12): definitions.append(_ability(
		StringName("base-%d" % index), AbilityDefinition.Timing.HAND_SHAPE, &"noop"
	))
	var config := MatchConfig.new(
		[&"one", &"two"], [], GameTypes.VictoryMode.SCORE_RACE, 20,
		GameTypes.InformationVisibility.PUBLIC,
		{GameTypes.Phase.START: 5000, GameTypes.Phase.MAIN_1: 5000,
		GameTypes.Phase.HAND_PLAY: 5000, GameTypes.Phase.MAIN_2: 5000,
		GameTypes.Phase.END: 2000},
		1000, 5000, 30000, definitions
	)
	var state := MatchState.create(config, seed_value)
	state.phase = GameTypes.Phase.MAIN_1
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	return state


func _ability(id: StringName, timing: int, effect_id: StringName) -> AbilityDefinition:
	var parameters := {}
	if effect_id == &"factor_modifier":
		parameters = {
			"factor_id": &"card_hand", "category_id": &"high_card",
			"numerator": 2 if id == &"multiply" or id == &"buff" else 3,
			"denominator": 1,
		}
	return AbilityDefinition.new(id, timing, [], effect_id, 0, &"", parameters)


func _field(id: StringName, effect_id: StringName, conflict: StringName) -> AbilityDefinition:
	var parameters := {"context": GameTypes.Context.FALL} if effect_id == &"context_jump" else {}
	return AbilityDefinition.new(
		id, AbilityDefinition.Timing.FIELD, [], effect_id, 2, conflict, parameters
	)


func _set_ability(state: MatchState, player_id: StringName, index: int, definition: AbilityDefinition) -> void:
	state.players[player_id].ability_hand[index].definition = definition


func _ready(id: StringName, player_id: StringName) -> GameCommand:
	return GameCommand.new(id, player_id, CommandKinds.SET_READY, {"ready": true})


func _play(
	id: StringName,
	player_id: StringName,
	copy_id: StringName,
	target_id: StringName = &"",
	_effect_payload: Dictionary = {}
) -> GameCommand:
	return GameCommand.new(id, player_id, CommandKinds.PLAY_PUBLIC_ABILITY, {
		"copy_id": copy_id, "target_player_id": target_id,
	})


func _first_event(events: Array, kind: StringName):
	for event in events:
		if event.kind == kind: return event
	return null


func _audience_event(events: Array, audience: StringName):
	for event in events:
		if event.audience == audience: return event
	return null


func _recipient_event(events: Array, recipient_id: StringName):
	for event in events:
		if event.recipient_id == recipient_id: return event
	return null


func _hand_ids(hand: Array) -> Dictionary:
	var result := {}
	for card in hand: result[card.card_id] = true
	return result


func _held_copy(hand: Array, copy_id: StringName):
	for ability in hand:
		if ability.copy_id == copy_id: return ability
	return null
