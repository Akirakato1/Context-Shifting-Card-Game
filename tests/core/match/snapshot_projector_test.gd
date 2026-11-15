extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const SnapshotProjector = preload("res://src/core/match/snapshot_projector.gd")

const FORBIDDEN_PUBLIC_KEYS := [
	"card_id", "copy_id", "ability_hand", "private_hand", "private_abilities",
	"pending_manipulation", "staged_submission", "rng_state", "base_context",
	"base_rank", "base_suit", "request", "discarded_ability_ids",
]


func test_public_and_spectator_snapshots_recursively_omit_private_state() -> void:
	var state := _state(GameTypes.InformationVisibility.PUBLIC)
	state.players[&"one"].pending_manipulation = {
		"copy_id": &"secret-ability", "target_card_id": state.players[&"one"].hand[0].card_id,
	}
	var public_snapshot := SnapshotProjector.for_recipient(
		state, &"", GameTypes.RecipientRole.SPECTATOR
	)
	var spectator_snapshot := SnapshotProjector.for_recipient(
		state, &"watcher", GameTypes.RecipientRole.SPECTATOR
	)

	_assert_no_forbidden_keys(public_snapshot)
	_assert_no_forbidden_keys(spectator_snapshot)
	assert_true(public_snapshot.has("pile_counts"))
	assert_false(JSON.stringify(public_snapshot).contains(str(state.players[&"one"].hand[0].card_id)))


func test_private_visibility_omits_exact_pile_counts() -> void:
	var state := _state(GameTypes.InformationVisibility.PRIVATE)
	var snapshot := SnapshotProjector.for_recipient(
		state, &"", GameTypes.RecipientRole.SPECTATOR
	)
	assert_false(snapshot.has("pile_counts"))


func test_player_snapshot_contains_only_that_players_private_values() -> void:
	var state := _state(GameTypes.InformationVisibility.PUBLIC)
	var own_card_id := str(state.players[&"one"].hand[0].card_id)
	var opponent_card_id := str(state.players[&"two"].hand[0].card_id)
	var snapshot := SnapshotProjector.for_recipient(
		state, &"one", GameTypes.RecipientRole.ACTIVE_PLAYER
	)
	var encoded := JSON.stringify(snapshot)

	assert_true(snapshot.has("private_hand"))
	assert_true(snapshot.has("private_abilities"))
	assert_true(encoded.contains(own_card_id))
	assert_false(encoded.contains(opponent_card_id))
	assert_eq(snapshot.private_player_id, "one")


func _state(visibility: int) -> MatchState:
	var abilities: Array[AbilityDefinition] = []
	for index in range(12): abilities.append(AbilityDefinition.new(
		StringName("ability-%d" % index), AbilityDefinition.Timing.HAND_SHAPE, [], &"noop"
	))
	var config := MatchConfig.new(
		[&"one", &"two"], [&"watcher"], GameTypes.VictoryMode.SCORE_RACE, 100, visibility,
		{GameTypes.Phase.START: 5000, GameTypes.Phase.MAIN_1: 5000,
		GameTypes.Phase.HAND_PLAY: 5000, GameTypes.Phase.MAIN_2: 5000,
		GameTypes.Phase.END: 2000}, 1000, 5000, 30000, abilities
	)
	return MatchState.create(config, 88)


func _assert_no_forbidden_keys(value: Variant) -> void:
	if value is Dictionary:
		for key in value:
			assert_false(str(key) in FORBIDDEN_PUBLIC_KEYS, "public snapshot leaked key %s" % key)
			_assert_no_forbidden_keys(value[key])
	elif value is Array:
		for item in value:
			_assert_no_forbidden_keys(item)
