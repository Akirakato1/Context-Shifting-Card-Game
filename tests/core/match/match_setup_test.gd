extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const Rational = preload("res://src/core/common/rational.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")
const ContextHandDefinition = preload("res://src/core/scoring/context_hand_definition.gd")


func test_config_rejects_active_and_spectator_count_limits() -> void:
	assert_eq(_config([&"one"], []).validate(), &"active_player_count_out_of_range")
	assert_eq(
		_config([&"one", &"two", &"three", &"four", &"five"], []).validate(),
		&"active_player_count_out_of_range"
	)
	assert_eq(
		_config([&"one", &"two"], [&"s1", &"s2", &"s3", &"s4", &"s5"]).validate(),
		&"spectator_count_out_of_range"
	)


func test_config_rejects_nonpositive_targets_and_timers() -> void:
	var target := _config([&"one", &"two"], [])
	target.set_victory_target(0)
	assert_eq(target.validate(), &"invalid_victory_target")

	var phase_timer := _config([&"one", &"two"], [])
	phase_timer.set_phase_timer(GameTypes.Phase.MAIN_1, 0)
	assert_eq(phase_timer.validate(), &"invalid_phase_timer")

	var reaction := _config([&"one", &"two"], [])
	reaction.set_reaction_window_msec(0)
	assert_eq(reaction.validate(), &"invalid_reaction_window")

	var hard_limit := _config([&"one", &"two"], [])
	hard_limit.set_public_hard_limit_msec(0)
	assert_eq(hard_limit.validate(), &"invalid_public_hard_limit")

	var reconnect := _config([&"one", &"two"], [])
	reconnect.set_reconnect_grace_msec(0)
	assert_eq(reconnect.validate(), &"invalid_reconnect_grace")


func test_config_changes_are_rejected_after_match_start() -> void:
	var config := _config([&"one", &"two"], [])
	config.lock_for_match()

	assert_eq(config.set_victory_target(99), &"config_locked")
	assert_eq(config.set_phase_timer(GameTypes.Phase.START, 99), &"config_locked")
	assert_eq(config.victory_target, 10)
	assert_eq(config.phase_timers[GameTypes.Phase.START], 5000)


func test_setup_uses_shared_piles_and_deals_opening_hands_then_start_abilities() -> void:
	var state := MatchState.create(_config([&"one", &"two"], [&"watcher"]), 4242)

	assert_eq(state.round_number, 1)
	assert_eq(state.active_context, GameTypes.Context.RISE)
	assert_eq(state.phase, GameTypes.Phase.START)
	assert_eq(state.seat_order, [&"one", &"two"])
	assert_eq(state.players.size(), 3)
	assert_eq(state.players[&"watcher"].hand.size(), 0)
	for player_id in state.seat_order:
		assert_eq(state.players[player_id].hand.size(), 6)
		assert_eq(_pair_shapes(state.players[player_id].hand), {
			&"rise_flourish": 2,
			&"rise_fall": 2,
			&"flourish_fall": 2,
		})
		assert_eq(state.players[player_id].ability_hand.size(), 2)
	assert_eq(state.piles[GameTypes.Context.RISE].draw_count(), 83)
	assert_eq(state.piles[GameTypes.Context.FLOURISH].draw_count(), 83)
	assert_eq(state.piles[GameTypes.Context.FALL].draw_count(), 83)

	state.deal_start_abilities()
	assert_eq(state.players[&"one"].ability_hand.size(), 3)
	assert_eq(state.players[&"two"].ability_hand.size(), 3)


func test_score_race_and_round_win_race_use_greater_than_or_equal_thresholds() -> void:
	var score_config := _config([&"one", &"two"], [])
	var score_state := MatchState.create(score_config, 1)
	assert_eq(score_state.resolve_round({&"one": 11, &"two": 5}), &"one")
	assert_eq(score_state.players[&"one"].match_score, 11)
	assert_eq(score_state.winner_id, &"one")

	var wins_config := _config([&"one", &"two"], [])
	wins_config.set_victory_mode(GameTypes.VictoryMode.ROUND_WIN_RACE)
	wins_config.set_victory_target(2)
	var wins_state := MatchState.create(wins_config, 2)
	wins_state.resolve_round({&"one": 7, &"two": 2})
	assert_eq(wins_state.winner_id, &"")
	wins_state.resolve_round({&"one": 4, &"two": 1})
	assert_eq(wins_state.players[&"one"].round_wins, 2)
	assert_eq(wins_state.winner_id, &"one")


func test_nil_tie_awards_no_progress() -> void:
	var state := MatchState.create(_config([&"one", &"two", &"three"], []), 3)

	assert_eq(state.resolve_round({&"one": 8, &"two": 8, &"three": 2}), &"")
	for player_id in state.seat_order:
		assert_eq(state.players[player_id].match_score, 0)
		assert_eq(state.players[player_id].round_wins, 0)
	assert_eq(state.winner_id, &"")


func test_last_active_player_wins_immediately_by_forfeit() -> void:
	var state := MatchState.create(_config([&"one", &"two"], []), 4)

	state.remove_active_player(&"two")

	assert_eq(state.winner_id, &"one")
	assert_true(state.match_complete)
	assert_eq(state.players[&"two"].active, false)


func test_snapshot_round_trip_preserves_canonical_match_values() -> void:
	var state := MatchState.create(_config([&"one", &"two"], [&"watcher"]), 99)
	state.deal_start_abilities()
	state.players[&"one"].match_score = 6
	state.players[&"two"].round_wins = 1

	var snapshot := state.to_dict()
	var restored := MatchState.from_dict(snapshot)

	assert_eq(restored.to_dict(), snapshot)
	assert_eq(restored.players[&"one"].hand.size(), 6)
	assert_eq(restored.players[&"one"].ability_hand.size(), 3)
	assert_eq(restored.seat_order, [&"one", &"two"])


func test_scoring_definition_metadata_survives_config_round_trip() -> void:
	var config := _config([&"one", &"two"], [])
	config._normal_definitions = [NormalHandDefinition.new(
		&"full_house", 50, 5, &"grouped_ranks", Rational.new(5, 2),
		&"group", &"rank", {"group_sizes": [3, 2]}
	)]
	config._context_definitions = [ContextHandDefinition.new(
		&"two_context", 20, {0: 2, 1: 2}, Rational.new(3, 1), &"two_context"
	)]

	var restored := MatchConfig.from_dict(config.to_dict())
	assert_eq(restored.normal_definitions[0].broad_category_id, &"group")
	assert_eq(restored.normal_definitions[0].component_group, &"rank")
	assert_eq(restored.normal_definitions[0].rule_parameters, {"group_sizes": [3, 2]})
	assert_eq(restored.context_definitions[0].broad_category_id, &"two_context")


func _config(active_ids: Array, spectator_ids: Array) -> MatchConfig:
	var timers := {
		GameTypes.Phase.START: 5000,
		GameTypes.Phase.MAIN_1: 5000,
		GameTypes.Phase.HAND_PLAY: 5000,
		GameTypes.Phase.MAIN_2: 5000,
		GameTypes.Phase.END: 2000,
	}
	var abilities: Array[AbilityDefinition] = []
	for index in range(20):
		abilities.append(AbilityDefinition.new(
			StringName("ability-%d" % index),
			AbilityDefinition.Timing.HAND_SHAPE,
			[],
			&"fixture"
		))
	return MatchConfig.new(
		active_ids,
		spectator_ids,
		GameTypes.VictoryMode.SCORE_RACE,
		10,
		GameTypes.InformationVisibility.PUBLIC,
		timers,
		1000,
		5000,
		30000,
		abilities
	)


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
		var shape := StringName("%s_%s" % [names[contexts[0]], names[contexts[1]]])
		counts[shape] += 1
	return counts
