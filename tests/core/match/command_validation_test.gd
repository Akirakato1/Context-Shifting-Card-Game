extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")


func test_malformed_command_is_rejected_without_state_change() -> void:
	var state := MatchState.create(_config(), 21)
	var controller := MatchController.new(state)
	var before := state.to_dict()

	var result := controller.submit(GameCommand.new(
		&"", &"one", CommandKinds.SET_READY, {"ready": true}
	), 100)

	assert_false(result.accepted)
	assert_eq(result.error_code, &"malformed_command")
	assert_eq(state.to_dict(), before)


func test_unknown_and_nonactive_players_are_rejected_without_mutation() -> void:
	var state := MatchState.create(_config(), 22)
	var controller := MatchController.new(state)
	var before := state.to_dict()

	var unknown := controller.submit(GameCommand.new(
		&"ghost-command", &"ghost", CommandKinds.SET_READY, {"ready": true}
	), 100)
	var spectator := controller.submit(GameCommand.new(
		&"watcher-command", &"watcher", CommandKinds.SET_READY, {"ready": true}
	), 100)

	assert_eq(unknown.error_code, &"unknown_player")
	assert_eq(spectator.error_code, &"not_active_player")
	assert_eq(state.to_dict(), before)


func test_accepted_command_ids_are_deduplicated_per_player() -> void:
	var state := MatchState.create(_config(), 23)
	var controller := MatchController.new(state)
	var command := GameCommand.new(
		&"same-id", &"one", CommandKinds.SET_READY, {"ready": true}
	)
	var accepted := controller.submit(command, 100)
	var after_first := state.to_dict()

	var duplicate := controller.submit(command, 101)

	assert_true(accepted.accepted)
	assert_false(duplicate.accepted)
	assert_eq(duplicate.error_code, &"duplicate_command")
	assert_eq(state.to_dict(), after_first)


func test_out_of_phase_command_is_rejected_without_state_change() -> void:
	var state := MatchState.create(_config(), 24)
	state.phase = GameTypes.Phase.MAIN_1
	var controller := MatchController.new(state)
	var before := state.to_dict()

	var result := controller.submit(GameCommand.new(
		&"late-request", &"one", CommandKinds.SET_REPLENISHMENT_REQUEST,
		{"request": {GameTypes.Context.A: 2}}
	), 100)

	assert_false(result.accepted)
	assert_eq(result.error_code, &"command_not_allowed_in_phase")
	assert_eq(state.to_dict(), before)


func _config() -> MatchConfig:
	var abilities: Array[AbilityDefinition] = []
	for index in range(12):
		abilities.append(AbilityDefinition.new(
			StringName("ability-%d" % index), AbilityDefinition.Timing.HAND_SHAPE, [], &"fixture"
		))
	return MatchConfig.new(
		[&"one", &"two"], [&"watcher"], GameTypes.VictoryMode.SCORE_RACE, 20,
		GameTypes.InformationVisibility.PUBLIC,
		{GameTypes.Phase.START: 5000, GameTypes.Phase.MAIN_1: 5000,
		GameTypes.Phase.HAND_PLAY: 5000, GameTypes.Phase.MAIN_2: 5000,
		GameTypes.Phase.END: 2000},
		1000, 5000, 30000, abilities
	)
