extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
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
	"completed_manipulation_ids",
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


func test_all_visibility_modes_expose_live_draw_pile_counts_only() -> void:
	var state := _state(GameTypes.InformationVisibility.PRIVATE)
	var snapshot := SnapshotProjector.for_recipient(
		state, &"", GameTypes.RecipientRole.SPECTATOR
	)
	assert_true(snapshot.has("pile_counts"))
	for pile in snapshot.pile_counts.values():
		assert_true(pile.has("draw_count"))
		assert_false(pile.has("used_count"))


func test_replacement_context_requests_follow_lobby_visibility_setting() -> void:
	var public_state := _state(GameTypes.InformationVisibility.PUBLIC)
	public_state.start_requests[&"one"] = {0: 3, 1: 2, 2: 1}
	var public_snapshot := SnapshotProjector.for_recipient(
		public_state, &"watcher", GameTypes.RecipientRole.SPECTATOR
	)
	assert_eq(public_snapshot.replacement_requests, {
		"one": {"0": 3, "1": 2, "2": 1},
	})

	var private_state := _state(GameTypes.InformationVisibility.PRIVATE)
	private_state.start_requests[&"one"] = {0: 3, 1: 2, 2: 1}
	var private_snapshot := SnapshotProjector.for_recipient(
		private_state, &"watcher", GameTypes.RecipientRole.SPECTATOR
	)
	assert_false(private_snapshot.has("replacement_requests"))


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
	for card in snapshot.private_hand:
		assert_true(card.has("eligible_half_indexes"))
	for ability in snapshot.private_abilities:
		assert_false(ability.legal)


func test_active_contexts_and_persistent_fields_are_public_for_every_role() -> void:
	var state := _state(GameTypes.InformationVisibility.PUBLIC)
	_activate_field(state, &"one", &"flourish_resonance")
	_activate_field(state, &"two", &"reverse_cycle")
	for entry in [
		[&"one", GameTypes.RecipientRole.HOST],
		[&"one", GameTypes.RecipientRole.ACTIVE_PLAYER],
		[&"watcher", GameTypes.RecipientRole.SPECTATOR],
	]:
		var snapshot := SnapshotProjector.for_recipient(state, entry[0], entry[1])
		assert_eq(snapshot.active_contexts, [GameTypes.Context.RISE, GameTypes.Context.FLOURISH])
		assert_eq(snapshot.active_fields.size(), 2)
		var reverse := _projected_field(snapshot.active_fields, "reverse_cycle")
		assert_true(reverse.persistent)
		assert_eq(reverse.remaining_rounds, AbilityDefinition.FIELD_DURATION_PERSISTENT)
		if entry[1] == GameTypes.RecipientRole.SPECTATOR:
			assert_false(snapshot.has("private_hand"))
	var flourish_card = state.players[&"one"].hand[0]
	if not flourish_card.first.is_joker():
		flourish_card.first.apply_overrides(
			GameTypes.Context.FLOURISH, flourish_card.first.effective_rank(),
			flourish_card.first.effective_suit()
		)
	var owner := SnapshotProjector.for_recipient(
		state, &"one", GameTypes.RecipientRole.ACTIVE_PLAYER
	)
	assert_true(0 in owner.private_hand[0].eligible_half_indexes)


func test_manipulation_targets_and_random_results_are_owner_private() -> void:
	var state := _state(GameTypes.InformationVisibility.PUBLIC)
	state.phase = GameTypes.Phase.HAND_PLAY
	var owner_player = state.players[&"one"]
	var card = owner_player.hand[0]
	var secret_card_id := str(card.card_id)
	var secret_copy_id := str(owner_player.ability_hand[0].copy_id)
	if not card.first.is_joker():
		card.first.apply_overrides(
			GameTypes.Context.FALL, 10, GameTypes.Suit.SEA
		)
	owner_player.pending_manipulation = {"copy_id": secret_copy_id}
	owner_player.completed_manipulation_ids.assign([&"low_roll"])

	var owner := SnapshotProjector.for_recipient(
		state, &"one", GameTypes.RecipientRole.ACTIVE_PLAYER
	)
	var opponent := SnapshotProjector.for_recipient(
		state, &"two", GameTypes.RecipientRole.ACTIVE_PLAYER
	)
	var spectator := SnapshotProjector.for_recipient(
		state, &"watcher", GameTypes.RecipientRole.SPECTATOR
	)
	var owner_text := JSON.stringify(owner)
	var opponent_text := JSON.stringify(opponent)
	var spectator_text := JSON.stringify(spectator)

	assert_true(owner_text.contains(secret_card_id))
	assert_true(owner_text.contains(secret_copy_id))
	assert_eq(owner.private_staging.completed_manipulation_ids, ["low_roll"])
	assert_false(owner_text.contains("choices"))
	assert_false(owner_text.contains("target_card_id"))
	assert_false(owner_text.contains("original_value"))
	assert_false(opponent_text.contains(secret_card_id))
	assert_false(opponent_text.contains(secret_copy_id))
	assert_false(spectator_text.contains(secret_card_id))
	_assert_no_forbidden_keys(spectator)


func test_player_lists_follow_seat_order_before_spectators() -> void:
	var state := _state(GameTypes.InformationVisibility.PUBLIC)
	state.seat_order = [&"two", &"one"]
	state.players[&"two"].seat_index = 0
	state.players[&"one"].seat_index = 1
	var host_snapshot := SnapshotProjector.for_recipient(
		state, &"two", GameTypes.RecipientRole.HOST
	)
	var public_snapshot := SnapshotProjector.for_recipient(
		state, &"watcher", GameTypes.RecipientRole.SPECTATOR
	)

	assert_eq(
		host_snapshot.players.map(func(player): return player.player_id),
		["two", "one", "watcher"]
	)
	assert_eq(
		public_snapshot.players.map(func(player): return player.player_id),
		["two", "one", "watcher"]
	)


func test_joker_draft_is_owner_only_and_resolved_view_is_public() -> void:
	var state := _state(GameTypes.InformationVisibility.PUBLIC)
	state.phase = GameTypes.Phase.HAND_PLAY
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	var joker := FullCardState.new(
		&"private-joker-card",
		HalfCardState.new(
			&"private-joker-half", GameTypes.Context.FLOURISH, 0, HalfCardState.NO_SUIT,
			GameTypes.HalfKind.JOKER
		),
		HalfCardState.new(
			&"private-normal-half", state.active_context, 4, GameTypes.Suit.MOUNTAIN
		),
	)
	state.players[&"one"].hand[0] = joker
	var controller := MatchController.new(state)
	var choices := [{
		"half_index": 0,
		"context": GameTypes.Context.FALL,
		"suit": GameTypes.Suit.SEA,
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
	var submitted := SnapshotProjector.for_recipient(
		state, &"one", GameTypes.RecipientRole.ACTIVE_PLAYER
	)
	assert_eq(submitted.private_hand.size(), owner.private_hand.size() - 1)
	assert_false(submitted.private_hand.any(func(card: Dictionary): return card.card_id == str(joker.card_id)))
	assert_eq(submitted.private_staging.get("submitted_score", {}).get("base_value", -1), 0)
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
		var revealed: Dictionary = _player_view(projected.players, &"one").revealed_submission
		assert_eq(_player_view(projected.players, &"one").hand_count, owner.private_hand.size() - 1)
		revealed_views.append(revealed.cards)
		assert_true(revealed.has("score_breakdown"))
		assert_true(revealed.score_breakdown.has("card_hand_components"))
		assert_true(revealed.score_breakdown.has("context_hand_components"))
		assert_true(revealed.score_breakdown.has("applied_modifiers"))
		assert_true(revealed.score_breakdown.has("card_hand_unclamped"))
		assert_true(revealed.score_breakdown.has("card_hand_factor"))
		assert_true(revealed.score_breakdown.has("final_score"))
	assert_eq(revealed_views[0], revealed_views[1])
	assert_eq(revealed_views[1], revealed_views[2])
	assert_eq(revealed_views[0][0].halves[0].context, GameTypes.Context.FALL)
	assert_eq(revealed_views[0][0].halves[0].rank, 0)
	assert_eq(revealed_views[0][0].halves[0].suit, GameTypes.Suit.SEA)
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


func _activate_field(state: MatchState, player_id: StringName, definition_id: StringName) -> void:
	var ability = state.players[player_id].ability_hand[0]
	for definition in AbilityCatalog.field_designs():
		if definition.id == definition_id:
			ability.definition = definition
			state.players[player_id].ability_hand.erase(ability)
			state.ability_deck.play_field(ability, player_id)
			return
	assert(false, "unknown field fixture")


func _projected_field(fields: Array, ability_id: String) -> Dictionary:
	for field in fields:
		if str(field.get("ability_id", "")) == ability_id:
			return field
	assert(false, "missing projected field")
	return {}


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
