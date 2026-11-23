extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const EventKinds = preload("res://src/core/events/event_kinds.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")


func test_begin_match_skips_round_one_start_effects_and_enters_main_one() -> void:
	var state := MatchState.create(_config(GameTypes.InformationVisibility.PUBLIC), 9)
	state.config.match_started = false
	var controller := MatchController.new(state)
	var opening_hands := {}
	var opening_abilities := {}
	for player_id in state.seat_order:
		opening_hands[player_id] = state.players[player_id].hand.size()
		opening_abilities[player_id] = state.players[player_id].ability_hand.size()

	var events: Array = controller.begin_match(1200)

	assert_true(state.config.match_started)
	assert_eq(state.round_number, 1)
	assert_eq(state.phase, GameTypes.Phase.MAIN_1)
	assert_eq(state.active_context, GameTypes.Context.RISE)
	assert_eq(state.phase_started_msec, 1200)
	assert_eq(state.phase_deadline_msec, 6200)
	assert_eq(state.start_prepared_round, 1)
	assert_eq(state.start_ability_drawn_round, 1)
	assert_eq(events.size(), 1)
	assert_eq(events[0].kind, EventKinds.PHASE_CHANGED)
	assert_eq(events[0].payload.phase, GameTypes.Phase.MAIN_1)
	for player_id in state.seat_order:
		assert_eq(state.players[player_id].hand.size(), opening_hands[player_id])
		assert_eq(state.players[player_id].ability_hand.size(), opening_abilities[player_id])
		assert_eq(opening_hands[player_id], 6)
		assert_eq(opening_abilities[player_id], 3)
		assert_false(state.players[player_id].ready)
	assert_eq(_event_count_for_player(events, EventKinds.ABILITY_DRAWN, &"one"), 0)
	assert_true(_first_event(events, EventKinds.REPLENISHMENT_REQUESTS_REVEALED) == null)


func test_open_lobby_poll_and_ready_toggle_cannot_start_round_one() -> void:
	var state := MatchState.create(_config(GameTypes.InformationVisibility.PUBLIC), 90)
	state.config.match_started = false
	var controller := MatchController.new(state)

	assert_false(state.players[&"one"].ready)
	assert_false(state.players[&"two"].ready)
	assert_eq(controller.tick(1000), [])
	var ready := controller.submit(GameCommand.new(
		&"lobby-ready", &"one", CommandKinds.SET_READY, {"ready": true}
	), 1100)

	assert_true(ready.accepted)
	assert_true(state.players[&"one"].ready)
	assert_eq(state.phase, GameTypes.Phase.START)
	assert_false(state.config.match_started)
	assert_eq(state.phase_started_msec, -1)
	assert_eq(state.players[&"one"].ability_hand.size(), 3)
	assert_eq(controller.tick(10_000), [])


func test_round_one_stays_rise_and_round_two_advances_to_flourish() -> void:
	var first := MatchState.create(_config(GameTypes.InformationVisibility.PUBLIC), 10)
	MatchController.new(first)
	assert_eq(first.active_context, GameTypes.Context.RISE)

	var second := MatchState.create(_config(GameTypes.InformationVisibility.PUBLIC), 11)
	second.round_number = 2
	second.phase = GameTypes.Phase.START
	MatchController.new(second)
	assert_eq(second.active_context, GameTypes.Context.FLOURISH)


func test_timeout_completes_partial_requests_replenishes_then_draws_abilities() -> void:
	var state := MatchState.create(_config(GameTypes.InformationVisibility.PUBLIC), 12)
	_set_up_second_round(state)
	_discard_one_full_card(state, &"one")
	_discard_one_full_card(state, &"two")
	var original_ids := _hand_ids(state.players[&"one"].hand)
	var original_ability_counts := {
		&"one": state.players[&"one"].ability_hand.size(),
		&"two": state.players[&"two"].ability_hand.size(),
	}
	var controller := MatchController.new(state)
	controller.tick(1000)

	var result := controller.submit(GameCommand.new(
		&"request-one", &"one", CommandKinds.SET_REPLENISHMENT_REQUEST,
		{"request": {GameTypes.Context.RISE: 1}}
	), 1200)
	var events := controller.tick(6001)

	assert_true(result.accepted)
	assert_eq(state.phase, GameTypes.Phase.MAIN_1)
	assert_eq(state.players[&"one"].hand.size(), 6)
	assert_eq(state.players[&"two"].hand.size(), 6)
	assert_eq(state.players[&"one"].ability_hand.size(), original_ability_counts[&"one"] + 3)
	assert_eq(state.players[&"two"].ability_hand.size(), original_ability_counts[&"two"] + 3)
	assert_eq(_event_count_for_player(events, EventKinds.ABILITY_DRAWN, &"one"), 3)
	assert_eq(_event_count_for_player(events, EventKinds.ABILITY_DRAWN, &"two"), 3)
	var new_card = _new_card(state.players[&"one"].hand, original_ids)
	assert_true(
		new_card.first.base_context == GameTypes.Context.RISE
		or new_card.second.base_context == GameTypes.Context.RISE
	)
	var reveal = _first_event(events, EventKinds.REPLENISHMENT_REQUESTS_REVEALED)
	assert_true(reveal != null)
	assert_eq(_request_total(reveal.payload.requests.one), 2)
	assert_eq(reveal.payload.requests.one[GameTypes.Context.RISE], 1)
	assert_true(
		_event_index(events, EventKinds.HAND_REPLENISHED)
		< _event_index(events, EventKinds.ABILITY_DRAWN)
	)


func test_private_visibility_reveals_replacement_count_but_not_context_distribution() -> void:
	var state := MatchState.create(_config(GameTypes.InformationVisibility.PRIVATE), 13)
	_discard_one_full_card(state, &"one")
	var controller := MatchController.new(state)
	controller.tick(0)

	var events := controller.tick(5001)

	var revealed = _first_event(events, EventKinds.REPLENISHMENT_REQUESTS_REVEALED)
	assert_true(revealed != null)
	assert_eq(revealed.payload.counts.one, 1)
	assert_false(revealed.payload.has("requests"))
	assert_eq(state.players[&"one"].hand.size(), 6)


func test_later_start_with_full_hands_auto_readies_and_advances_on_first_tick() -> void:
	var state := MatchState.create(_config(GameTypes.InformationVisibility.PUBLIC), 14)
	_set_up_second_round(state)
	var controller := MatchController.new(state)

	assert_true(state.players[&"one"].ready)
	assert_true(state.players[&"two"].ready)
	var events := controller.tick(1000)

	assert_eq(state.phase, GameTypes.Phase.MAIN_1)
	assert_eq(state.players[&"one"].ability_hand.size(), 5)
	assert_eq(state.players[&"two"].ability_hand.size(), 5)
	assert_eq(_event_count_for_player(events, EventKinds.ABILITY_DRAWN, &"one"), 3)
	assert_eq(_event_count_for_player(events, EventKinds.ABILITY_DRAWN, &"two"), 3)
	assert_false(state.players[&"one"].ready)
	assert_false(state.players[&"two"].ready)


func test_only_player_needing_replenishment_must_ready_before_main_one() -> void:
	var state := MatchState.create(_config(GameTypes.InformationVisibility.PUBLIC), 15)
	_discard_one_full_card(state, &"one")
	_set_up_second_round(state)
	var controller := MatchController.new(state)

	assert_false(state.players[&"one"].ready)
	assert_true(state.players[&"two"].ready)
	var cannot_unready := controller.submit(GameCommand.new(
		&"unready-two", &"two", CommandKinds.SET_READY, {"ready": false}
	), 1050)
	assert_false(cannot_unready.accepted)
	assert_eq(cannot_unready.error_code, &"no_replenishment_needed")
	assert_true(state.players[&"two"].ready)
	var result := controller.submit(GameCommand.new(
		&"ready-one", &"one", CommandKinds.SET_READY, {"ready": true}
	), 1100)

	assert_true(result.accepted)
	assert_eq(state.phase, GameTypes.Phase.MAIN_1)
	assert_eq(state.players[&"one"].hand.size(), 6)
	assert_false(state.players[&"one"].ready)
	assert_false(state.players[&"two"].ready)
	assert_true(_first_event(result.events, EventKinds.PHASE_CHANGED) != null)
	assert_eq(state.players[&"one"].ability_hand.size(), 5)


func _set_up_second_round(state: MatchState) -> void:
	state.round_number = 2
	for player_id in state.seat_order:
		state.ability_deck.discard(state.players[player_id].ability_hand.pop_back())


func _config(visibility: int) -> MatchConfig:
	var abilities: Array[AbilityDefinition] = []
	for index in range(12):
		abilities.append(AbilityDefinition.new(
			StringName("ability-%d" % index), AbilityDefinition.Timing.HAND_SHAPE, [], &"fixture"
		))
	return MatchConfig.new(
		[&"one", &"two"], [], GameTypes.VictoryMode.SCORE_RACE, 20, visibility,
		{GameTypes.Phase.START: 5000, GameTypes.Phase.MAIN_1: 5000,
		GameTypes.Phase.HAND_PLAY: 5000, GameTypes.Phase.MAIN_2: 5000,
		GameTypes.Phase.END: 2000},
		1000, 5000, 30000, abilities
	)


func _discard_one_full_card(state: MatchState, player_id: StringName) -> void:
	var card = state.players[player_id].hand.pop_back()
	card.leave_hand()
	state.piles[card.first.base_context].discard(card.first)
	state.piles[card.second.base_context].discard(card.second)


func _hand_ids(hand: Array) -> Dictionary:
	var result := {}
	for card in hand: result[card.card_id] = true
	return result


func _new_card(hand: Array, original_ids: Dictionary):
	for card in hand:
		if not original_ids.has(card.card_id): return card
	return null


func _first_event(events: Array, kind: StringName):
	for event in events:
		if event.kind == kind: return event
	return null


func _event_index(events: Array, kind: StringName) -> int:
	for index in range(events.size()):
		if events[index].kind == kind: return index
	return -1


func _event_count_for_player(events: Array, kind: StringName, player_id: StringName) -> int:
	var count := 0
	for event in events:
		if event.kind == kind and StringName(event.payload.get("player_id", "")) == player_id:
			count += 1
	return count


func _request_total(request: Dictionary) -> int:
	var total := 0
	for count in request.values(): total += count
	return total
