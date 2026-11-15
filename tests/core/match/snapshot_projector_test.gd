extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")
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


func test_joker_draft_is_owner_only_and_resolved_view_is_public() -> void:
	var state := _state(GameTypes.InformationVisibility.PUBLIC)
	state.phase = GameTypes.Phase.HAND_PLAY
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	var joker := FullCardState.new(
		&"private-joker-card",
		HalfCardState.new(
			&"private-joker-half", GameTypes.Context.B, 0, HalfCardState.NO_SUIT,
			GameTypes.HalfKind.JOKER
		),
		HalfCardState.new(
			&"private-normal-half", state.active_context, 4, GameTypes.Suit.ONE
		),
	)
	state.players[&"one"].hand[0] = joker
	var controller := MatchController.new(state)
	var choices := [{
		"half_index": 0,
		"context": GameTypes.Context.C,
		"suit": GameTypes.Suit.THREE,
	}]
	assert_true(controller.submit(GameCommand.new(
		&"stage-joker", &"one", CommandKinds.STAGE_HAND, {"cards": [{
			"card_id": joker.card_id, "half_index": 0, "joker_choices": choices,
		}]}
	), 1).accepted)

	var owner := SnapshotProjector.for_recipient(
		state, &"one", GameTypes.RecipientRole.ACTIVE_PLAYER
	)
	var opponent := SnapshotProjector.for_recipient(
		state, &"two", GameTypes.RecipientRole.ACTIVE_PLAYER
	)
	var spectator := SnapshotProjector.for_recipient(
		state, &"watcher", GameTypes.RecipientRole.SPECTATOR
	)
	assert_eq(owner.private_staging.staged_submission[0].joker_choices, choices)
	assert_true(opponent.has("private_staging"))
	assert_false(spectator.has("private_staging"))
	assert_false(JSON.stringify(opponent.private_staging).contains(str(joker.card_id)))
	assert_false(JSON.stringify(spectator).contains(str(joker.card_id)))

	controller.submit(GameCommand.new(
		&"pass-two", &"two", CommandKinds.STAGE_HAND, {"cards": []}
	), 1)
	controller.submit(GameCommand.new(&"lock-one", &"one", CommandKinds.LOCK_HAND), 2)
	var between_locks := SnapshotProjector.for_recipient(
		state, &"watcher", GameTypes.RecipientRole.SPECTATOR
	)
	assert_false(
		_player_view(between_locks.players, &"one").has("revealed_submission"),
		"a locked hand must remain private until every hand resolves"
	)
	assert_false(JSON.stringify(between_locks).contains(str(joker.card_id)))
	controller.submit(GameCommand.new(&"lock-two", &"two", CommandKinds.LOCK_HAND), 2)
	var revealed_views: Array = []
	for entry in [
		[&"one", GameTypes.RecipientRole.ACTIVE_PLAYER],
		[&"two", GameTypes.RecipientRole.ACTIVE_PLAYER],
		[&"watcher", GameTypes.RecipientRole.SPECTATOR],
	]:
		var projected := SnapshotProjector.for_recipient(state, entry[0], entry[1])
		revealed_views.append(_player_view(projected.players, &"one").revealed_submission.cards)
	assert_eq(revealed_views[0], revealed_views[1])
	assert_eq(revealed_views[1], revealed_views[2])
	assert_eq(revealed_views[0][0].halves[0].context, GameTypes.Context.C)
	assert_eq(revealed_views[0][0].halves[0].rank, 0)
	assert_eq(revealed_views[0][0].halves[0].suit, GameTypes.Suit.THREE)
	var public_text := JSON.stringify(revealed_views[0])
	assert_false(public_text.contains("copy_id"))
	assert_false(public_text.contains("base_context"))
	assert_false(public_text.contains("joker_choices"))


func _state(visibility: int) -> MatchState:
	var abilities: Array[AbilityDefinition] = []
	for index in range(12): abilities.append(AbilityDefinition.new(
		StringName("ability-%d" % index), AbilityDefinition.Timing.HAND_SHAPE, [], &"noop"
	))
	var config := MatchConfig.new(
		[&"one", &"two"], [&"watcher"], GameTypes.VictoryMode.SCORE_RACE, 100, visibility,
		{GameTypes.Phase.START: 5000, GameTypes.Phase.MAIN_1: 5000,
		GameTypes.Phase.HAND_PLAY: 5000, GameTypes.Phase.MAIN_2: 5000,
		GameTypes.Phase.END: 2000}, 1000, 5000, 30000, abilities,
		[NormalHandDefinition.new(
			&"high_card", 1, 1, &"high_card", Rational.new(1, 1)
		)], []
	)
	return MatchState.create(config, 88)


func _player_view(players: Array, player_id: StringName) -> Dictionary:
	for player: Dictionary in players:
		if player.player_id == str(player_id):
			return player
	return {}


func _assert_no_forbidden_keys(value: Variant) -> void:
	if value is Dictionary:
		for key in value:
			assert_false(str(key) in FORBIDDEN_PUBLIC_KEYS, "public snapshot leaked key %s" % key)
			_assert_no_forbidden_keys(value[key])
	elif value is Array:
		for item in value:
			_assert_no_forbidden_keys(item)
