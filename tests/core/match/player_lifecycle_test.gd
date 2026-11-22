extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")


func test_late_active_join_waits_for_next_start_and_does_not_affect_current_readiness() -> void:
	var state := _state(71, 3, 24)
	var controller := MatchController.new(state)
	controller.tick(0)
	var joined := controller.submit(GameCommand.new(
		&"join-four", &"four", CommandKinds.JOIN_ACTIVE
	), 10)

	assert_true(joined.accepted)
	assert_true(state.players[&"four"].pending)
	assert_eq(state.players[&"four"].hand.size(), 0)
	for player_id in [&"one", &"two", &"three"]:
		controller.submit(GameCommand.new(
			StringName("ready-%s" % player_id), player_id, CommandKinds.SET_READY, {"ready": true}
		), 20)
	assert_eq(state.phase, GameTypes.Phase.HAND_PLAY)
	assert_eq(controller.submit(GameCommand.new(
		&"too-many", &"five", CommandKinds.JOIN_ACTIVE
	), 21).error_code, &"active_seats_full")

	state.phase = GameTypes.Phase.START
	state.round_number = 2
	state.start_prepared_round = 0
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	controller = MatchController.new(state)
	assert_true(state.players[&"four"].ready)
	controller.tick(0)
	controller.tick(5001)
	assert_false(state.players[&"four"].pending)
	assert_true(state.players[&"four"].active)
	assert_eq(state.players[&"four"].match_score, 0)
	assert_eq(state.players[&"four"].round_wins, 0)
	assert_eq(state.players[&"four"].hand.size(), 6)
	assert_eq(_pair_shapes(state.players[&"four"].hand), {
		&"rise_flourish": 2,
		&"rise_fall": 2,
		&"flourish_fall": 2,
	})
	assert_eq(state.players[&"four"].ability_hand.size(), 4)


func test_spectator_cap_and_spectators_never_affect_readiness() -> void:
	var state := _state(72, 2, 20)
	var controller := MatchController.new(state)
	for index in range(4):
		assert_true(controller.submit(GameCommand.new(
			StringName("spectate-%d" % index), StringName("watcher-%d" % index),
			CommandKinds.JOIN_SPECTATOR
		), 1).accepted)
	assert_eq(controller.submit(GameCommand.new(
		&"spectate-five", &"watcher-4", CommandKinds.JOIN_SPECTATOR
	), 2).error_code, &"spectator_slots_full")
	controller.submit(GameCommand.new(&"r1", &"one", CommandKinds.SET_READY, {"ready": true}), 3)
	controller.submit(GameCommand.new(&"r2", &"two", CommandKinds.SET_READY, {"ready": true}), 3)
	assert_eq(state.phase, GameTypes.Phase.HAND_PLAY)


func test_short_ability_draw_for_late_entry_is_legal() -> void:
	var state := _state(73, 3, 9)
	var controller := MatchController.new(state)
	controller.submit(GameCommand.new(&"join", &"four", CommandKinds.JOIN_ACTIVE), 1)
	state.phase = GameTypes.Phase.START
	state.round_number = 2
	state.start_prepared_round = 0
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	controller = MatchController.new(state)
	controller.tick(0)
	controller.tick(5001)
	assert_true(state.players[&"four"].ability_hand.size() >= 2)
	assert_true(state.players[&"four"].ability_hand.size() <= 4)
	assert_eq(state.players[&"four"].hand.size(), 6)


func test_disconnects_freeze_commands_use_independent_deadlines_and_resume_after_all_resolve() -> void:
	var state := _state(74, 3, 24)
	var controller := MatchController.new(state)
	controller.tick(0)
	var private_hand_ids := _hand_ids(state.players[&"two"].hand)
	controller.notify_player_disconnected(&"two", 100)
	assert_true(state.frozen)
	var before := state.to_dict()
	var rejected := controller.submit(GameCommand.new(
		&"blocked", &"two", CommandKinds.SET_READY, {"ready": true}
	), 110)
	assert_eq(rejected.error_code, &"match_frozen")
	assert_eq(state.to_dict(), before)

	controller.notify_player_disconnected(&"three", 200)
	var token: String = state.players[&"two"].reconnect_token
	var reconnected := controller.submit(GameCommand.new(
		&"reconnect", &"two", CommandKinds.RECONNECT, {"token": token}
	), 500)
	assert_true(reconnected.accepted)
	assert_eq(_hand_ids(state.players[&"two"].hand), private_hand_ids)
	assert_true(state.frozen, "player three is still unresolved")
	controller.tick(30199)
	assert_true(state.players[&"three"].active)
	assert_true(state.frozen)
	controller.tick(30200)
	assert_false(state.players[&"three"].active)
	assert_false(state.frozen)
	assert_eq(state.players[&"three"].hand.size(), 0)
	assert_eq(state.players[&"three"].ability_hand.size(), 0)


func test_forfeit_retains_fields_and_last_player_standing_wins() -> void:
	var state := _state(75, 2, 20)
	var field_card = state.players[&"two"].ability_hand[0]
	field_card.definition = AbilityDefinition.new(
		&"lasting", AbilityDefinition.Timing.FIELD, [], &"noop", 3
	)
	state.players[&"two"].ability_hand.erase(field_card)
	state.ability_deck.play_field(field_card, &"two")
	var controller := MatchController.new(state)
	controller.notify_player_disconnected(&"two", 0)
	controller.tick(30000)

	assert_eq(state.ability_deck.active_fields().size(), 1)
	assert_eq(state.winner_id, &"one")
	assert_true(state.match_complete)


func test_host_disconnect_ends_match_without_round_progress() -> void:
	var state := _state(76, 2, 20)
	var controller := MatchController.new(state)
	controller.notify_player_disconnected(&"one", 1)
	assert_true(state.match_complete)
	assert_eq(state.winner_id, &"")
	assert_eq(state.players[&"two"].match_score, 0)


func _state(seed_value: int, active_count: int, ability_count: int) -> MatchState:
	var ids: Array[StringName] = [&"one", &"two", &"three", &"four"]
	var active_ids: Array[StringName] = []
	for index in range(active_count): active_ids.append(ids[index])
	var abilities: Array[AbilityDefinition] = []
	for index in range(ability_count): abilities.append(AbilityDefinition.new(
		StringName("ability-%d" % index), AbilityDefinition.Timing.HAND_SHAPE, [], &"noop"
	))
	var config := MatchConfig.new(
		active_ids, [], GameTypes.VictoryMode.SCORE_RACE, 100,
		GameTypes.InformationVisibility.PUBLIC,
		{GameTypes.Phase.START: 5000, GameTypes.Phase.MAIN_1: 5000,
		GameTypes.Phase.HAND_PLAY: 5000, GameTypes.Phase.MAIN_2: 5000,
		GameTypes.Phase.END: 2000}, 1000, 5000, 30000, abilities
	)
	var state := MatchState.create(config, seed_value)
	state.phase = GameTypes.Phase.MAIN_1
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	return state


func _hand_ids(hand: Array) -> Array:
	var result: Array = []
	for card in hand: result.append(card.card_id)
	result.sort()
	return result


func _pair_shapes(hand: Array) -> Dictionary:
	var counts := {
		&"rise_flourish": 0,
		&"rise_fall": 0,
		&"flourish_fall": 0,
	}
	var names := {0: "rise", 1: "flourish", 2: "fall"}
	for card in hand:
		var contexts := [card.first.base_context, card.second.base_context]
		contexts.sort()
		counts[StringName("%s_%s" % [names[contexts[0]], names[contexts[1]]])] += 1
	return counts
