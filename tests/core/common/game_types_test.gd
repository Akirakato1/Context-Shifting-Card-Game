extends "res://tests/test_case.gd"

const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const GameTypes = preload("res://src/core/common/game_types.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")


func test_context_values_preserve_protocol_order_and_names() -> void:
	assert_eq(GameTypes.Context.RISE, 0)
	assert_eq(GameTypes.Context.FLOURISH, 1)
	assert_eq(GameTypes.Context.FALL, 2)
	assert_eq(GameTypes.context_name(0), "Rise")
	assert_eq(GameTypes.context_name(1), "Flourish")
	assert_eq(GameTypes.context_name(2), "Fall")
	assert_eq(GameTypes.context_name(-1), "Unknown")
	assert_eq(GameTypes.context_name(3), "Unknown")


func test_suit_values_preserve_protocol_order_and_names() -> void:
	assert_eq(GameTypes.Suit.MOUNTAIN, 0)
	assert_eq(GameTypes.Suit.CLOUD, 1)
	assert_eq(GameTypes.Suit.SEA, 2)
	assert_eq(GameTypes.suit_name(0), "Mountain")
	assert_eq(GameTypes.suit_name(1), "Cloud")
	assert_eq(GameTypes.suit_name(2), "Sea")
	assert_eq(GameTypes.suit_name(-1), "Unknown")
	assert_eq(GameTypes.suit_name(3), "Unknown")


func test_context_integer_snapshot_round_trip_preserves_final_meaning() -> void:
	var state := MatchState.create(_config(), 411)
	var expected := [
		{"value": 0, "name": "Rise"},
		{"value": 1, "name": "Flourish"},
		{"value": 2, "name": "Fall"},
	]
	for entry in expected:
		state.active_context = entry.value
		var snapshot := state.to_dict()
		assert_eq(typeof(snapshot.active_context), TYPE_INT)
		assert_eq(snapshot.active_context, entry.value)
		var restored := MatchState.from_dict(snapshot)
		assert_eq(restored.active_context, entry.value)
		assert_eq(GameTypes.context_name(restored.active_context), entry.name)


func _config() -> MatchConfig:
	var timers := {
		GameTypes.Phase.START: 5000,
		GameTypes.Phase.MAIN_1: 5000,
		GameTypes.Phase.HAND_PLAY: 5000,
		GameTypes.Phase.MAIN_2: 5000,
		GameTypes.Phase.END: 2000,
	}
	var abilities: Array[AbilityDefinition] = []
	for index in range(6):
		abilities.append(AbilityDefinition.new(
			StringName("ability-%d" % index),
			AbilityDefinition.Timing.HAND_SHAPE,
			[],
			&"fixture"
		))
	return MatchConfig.new(
		[&"one", &"two"],
		[],
		GameTypes.VictoryMode.SCORE_RACE,
		10,
		GameTypes.InformationVisibility.PUBLIC,
		timers,
		1000,
		5000,
		30000,
		abilities
	)
