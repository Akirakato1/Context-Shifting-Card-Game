extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")
const ContextHandDefinition = preload("res://src/core/scoring/context_hand_definition.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const EventKinds = preload("res://src/core/events/event_kinds.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")


func test_joker_staging_lock_and_reveal_use_sanitized_resolved_faces() -> void:
	var state := _hand_play_state(71)
	var joker := _joker_card(&"fixture-joker", state.active_context)
	state.players[&"one"].hand[0] = joker
	var controller := MatchController.new(state)
	var choices := [{
		"half_index": 0,
		"context": GameTypes.Context.C,
		"suit": GameTypes.Suit.THREE,
	}]

	var staged := controller.submit(_stage(
		&"stage-joker", &"one", [_selection(joker.card_id, 0, choices)]
	), 1)
	assert_true(staged.accepted)
	assert_eq(state.players[&"one"].staged_submission[0]["joker_choices"], choices)
	assert_true(controller.submit(_lock(&"lock-one", &"one"), 2).accepted)
	assert_eq(controller.submit(_stage(
		&"revise-locked", &"one", []
	), 3).error_code, &"hand_already_locked")
	controller.submit(_stage(&"pass-two", &"two", []), 2)
	var resolved := controller.submit(_lock(&"lock-two", &"two"), 3)

	var player = state.players[&"one"]
	assert_eq(player.submitted_faces[0].rank, 0)
	assert_eq(player.submitted_faces[0].suit, GameTypes.Suit.THREE)
	assert_eq(player.submitted_card_views.size(), 1)
	var resolved_joker: Dictionary = player.submitted_card_views[0]["halves"][0]
	assert_eq(resolved_joker["context"], GameTypes.Context.C)
	assert_eq(resolved_joker["rank"], 0)
	assert_eq(resolved_joker["suit"], GameTypes.Suit.THREE)
	assert_eq(resolved_joker["joker"], true)
	assert_eq(joker.first.base_context, GameTypes.Context.B)
	assert_eq(joker.first.base_rank, 0)
	assert_eq(joker.first.base_suit, HalfCardState.NO_SUIT)

	var reveal = _player_event(resolved.events, EventKinds.HAND_REVEALED, &"one")
	assert_eq(reveal.payload.cards, player.submitted_card_views)
	var reveal_text := str(reveal.payload.cards)
	assert_eq(reveal_text.find("copy_id"), -1)
	assert_eq(reveal_text.find("base_context"), -1)
	assert_eq(reveal_text.find("joker_choices"), -1)


func test_invalid_joker_replacement_preserves_previous_draft_and_missing_default_rejects() -> void:
	var state := _hand_play_state(72)
	var joker := _joker_card(&"fixture-joker", state.active_context)
	state.players[&"one"].hand[0] = joker
	var controller := MatchController.new(state)
	var valid := [_selection(joker.card_id, 0, [{
		"half_index": 0,
		"context": GameTypes.Context.A,
		"suit": GameTypes.Suit.ONE,
	}])]
	assert_true(controller.submit(_stage(&"valid", &"one", valid), 1).accepted)
	var before: Array = state.players[&"one"].staged_submission.duplicate(true)

	var missing := controller.submit(_stage(
		&"missing", &"one", [{"card_id": joker.card_id, "half_index": 0}]
	), 2)
	assert_eq(missing.error_code, &"joker_choice_required")
	assert_eq(state.players[&"one"].staged_submission, before)

	var invalid := controller.submit(_stage(
		&"invalid", &"one", [_selection(joker.card_id, 0, [{
			"half_index": 0,
			"context": GameTypes.Context.A,
			"suit": 99,
		}])]
	), 3)
	assert_eq(invalid.error_code, &"invalid_joker_suit")
	assert_eq(state.players[&"one"].staged_submission, before)


func test_double_joker_lock_resolves_independent_choices() -> void:
	var state := _hand_play_state(73)
	var card := FullCardState.new(
		&"double-joker",
		_joker_half(&"joker-a", GameTypes.Context.A),
		_joker_half(&"joker-b", GameTypes.Context.B),
	)
	state.players[&"one"].hand[0] = card
	var controller := MatchController.new(state)
	var choices := [
		{"half_index": 0, "context": GameTypes.Context.A, "suit": GameTypes.Suit.ONE},
		{"half_index": 1, "context": GameTypes.Context.C, "suit": GameTypes.Suit.TWO},
	]
	controller.submit(_stage(
		&"stage-one", &"one", [_selection(card.card_id, 1, choices)]
	), 1)
	controller.submit(_stage(&"pass-two", &"two", []), 1)
	controller.submit(_lock(&"lock-one", &"one"), 2)
	controller.submit(_lock(&"lock-two", &"two"), 2)

	var player = state.players[&"one"]
	assert_eq(player.submitted_faces[0].suit, GameTypes.Suit.TWO)
	assert_eq(player.locked_context.counts[GameTypes.Context.A], 1)
	assert_eq(player.locked_context.counts[GameTypes.Context.C], 1)
	assert_eq(player.submitted_card_views[0]["halves"][0]["context"], GameTypes.Context.A)
	assert_eq(player.submitted_card_views[0]["halves"][1]["context"], GameTypes.Context.C)


func test_replacing_or_passing_clears_staged_joker_choices() -> void:
	var state := _hand_play_state(74)
	var joker := _joker_card(&"fixture-joker", state.active_context)
	var ordinary := _normal_card(&"ordinary", state.active_context)
	state.players[&"one"].hand[0] = joker
	state.players[&"one"].hand[1] = ordinary
	var controller := MatchController.new(state)
	controller.submit(_stage(
		&"joker", &"one", [_selection(joker.card_id, 0, [{
			"half_index": 0,
			"context": GameTypes.Context.B,
			"suit": GameTypes.Suit.TWO,
		}])]
	), 1)

	assert_true(controller.submit(_stage(
		&"ordinary", &"one", [{"card_id": ordinary.card_id, "half_index": 0}]
	), 2).accepted)
	assert_eq(state.players[&"one"].staged_submission.size(), 1)
	assert_eq(state.players[&"one"].staged_submission[0]["card_id"], ordinary.card_id)
	assert_eq(state.players[&"one"].staged_submission[0]["joker_choices"], [])

	assert_true(controller.submit(_stage(&"pass", &"one", []), 3).accepted)
	assert_true(state.players[&"one"].staged_submission.is_empty())


func test_timeout_defaults_incomplete_internal_joker_draft_to_pass() -> void:
	var state := _hand_play_state(75)
	var joker := _joker_card(&"fixture-joker", state.active_context)
	state.players[&"one"].hand[0] = joker
	state.players[&"one"].staged_submission.assign([{
		"card_id": joker.card_id, "half_index": 0, "joker_choices": [],
	}])
	state.players[&"one"].has_staged_submission = true
	var controller := MatchController.new(state)
	controller.tick(0)

	controller.tick(5001)

	assert_eq(state.phase, GameTypes.Phase.MAIN_2)
	assert_true(state.players[&"one"].submitted_cards.is_empty())
	assert_true(state.players[&"one"].submitted_card_views.is_empty())
	assert_true(state.players[&"one"].staged_submission.is_empty())


func test_round_cleanup_clears_resolved_views() -> void:
	var state := _hand_play_state(76)
	var joker := _joker_card(&"fixture-joker", state.active_context)
	state.players[&"one"].hand[0] = joker
	var controller := MatchController.new(state)
	controller.submit(_stage(
		&"stage-one", &"one", [_selection(joker.card_id, 0, [{
			"half_index": 0,
			"context": GameTypes.Context.A,
			"suit": GameTypes.Suit.ONE,
		}])]
	), 1)
	controller.submit(_stage(&"pass-two", &"two", []), 1)
	controller.submit(_lock(&"lock-one", &"one"), 2)
	controller.submit(_lock(&"lock-two", &"two"), 2)
	assert_eq(state.players[&"one"].submitted_card_views.size(), 1)

	controller.submit(_ready(&"ready-one", &"one"), 3)
	controller.submit(_ready(&"ready-two", &"two"), 3)

	assert_true(state.players[&"one"].submitted_card_views.is_empty())


func _hand_play_state(seed_value: int) -> MatchState:
	var abilities: Array[AbilityDefinition] = []
	for index in range(12):
		abilities.append(AbilityDefinition.new(
			StringName("base-%d" % index), AbilityDefinition.Timing.HAND_SHAPE, [], &"noop"
		))
	var normal_definitions: Array[NormalHandDefinition] = [
		NormalHandDefinition.new(&"high_card", 10, 1, &"high_card", Rational.new(1, 1)),
		NormalHandDefinition.new(&"pair", 20, 2, &"pair", Rational.new(2, 1)),
	]
	var context_definitions: Array[ContextHandDefinition] = [
		ContextHandDefinition.new(
			&"abc", 20,
			{GameTypes.Context.A: 1, GameTypes.Context.B: 1, GameTypes.Context.C: 1},
			Rational.new(2, 1)
		),
	]
	var config := MatchConfig.new(
		[&"one", &"two"], [], GameTypes.VictoryMode.SCORE_RACE, 100,
		GameTypes.InformationVisibility.PUBLIC,
		{GameTypes.Phase.START: 5000, GameTypes.Phase.MAIN_1: 5000,
		GameTypes.Phase.HAND_PLAY: 5000, GameTypes.Phase.MAIN_2: 5000,
		GameTypes.Phase.END: 2000}, 1000, 5000, 30000, abilities,
		normal_definitions, context_definitions
	)
	var state := MatchState.create(config, seed_value)
	state.phase = GameTypes.Phase.HAND_PLAY
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	return state


func _joker_card(id: StringName, normal_context: int) -> FullCardState:
	return FullCardState.new(
		id,
		_joker_half(StringName("%s-joker" % id), GameTypes.Context.B),
		HalfCardState.new(
			StringName("%s-normal" % id), normal_context, 5, GameTypes.Suit.ONE
		),
	)


func _joker_half(id: StringName, origin_context: int) -> HalfCardState:
	return HalfCardState.new(
		id, origin_context, 0, HalfCardState.NO_SUIT, GameTypes.HalfKind.JOKER
	)


func _normal_card(id: StringName, context: int) -> FullCardState:
	return FullCardState.new(
		id,
		HalfCardState.new(StringName("%s-first" % id), context, 7, GameTypes.Suit.ONE),
		HalfCardState.new(
			StringName("%s-second" % id), (context + 1) % 3, 4, GameTypes.Suit.TWO
		),
	)


func _selection(card_id: StringName, half_index: int, choices: Array) -> Dictionary:
	return {"card_id": card_id, "half_index": half_index, "joker_choices": choices}


func _stage(id: StringName, player_id: StringName, cards: Array) -> GameCommand:
	return GameCommand.new(id, player_id, CommandKinds.STAGE_HAND, {"cards": cards})


func _lock(id: StringName, player_id: StringName) -> GameCommand:
	return GameCommand.new(id, player_id, CommandKinds.LOCK_HAND)


func _ready(id: StringName, player_id: StringName) -> GameCommand:
	return GameCommand.new(id, player_id, CommandKinds.SET_READY, {"ready": true})


func _player_event(events: Array, kind: StringName, player_id: StringName):
	for event in events:
		if event.kind == kind and event.payload.player_id == str(player_id):
			return event
	return null
