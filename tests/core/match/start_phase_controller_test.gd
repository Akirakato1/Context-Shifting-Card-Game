extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const EventKinds = preload("res://src/core/events/event_kinds.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")


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
	assert_eq(state.players[&"one"].ability_hand.size(), original_ability_counts[&"one"] + 2)
	assert_eq(state.players[&"two"].ability_hand.size(), original_ability_counts[&"two"] + 2)
	assert_eq(_event_count_for_player(events, EventKinds.ABILITY_DRAWN, &"one"), 2)
	assert_eq(_event_count_for_player(events, EventKinds.ABILITY_DRAWN, &"two"), 2)
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


func test_all_ready_advances_before_deadline_and_clears_readiness() -> void:
	var state := MatchState.create(_config(GameTypes.InformationVisibility.PUBLIC), 14)
	var controller := MatchController.new(state)
	controller.tick(1000)

	var first := controller.submit(GameCommand.new(
		&"ready-one", &"one", CommandKinds.SET_READY, {"ready": true}
	), 1100)
	var second := controller.submit(GameCommand.new(
		&"ready-two", &"two", CommandKinds.SET_READY, {"ready": true}
	), 1200)

	assert_true(first.accepted)
	assert_true(second.accepted)
	assert_eq(state.phase, GameTypes.Phase.MAIN_1)
	assert_false(state.players[&"one"].ready)
	assert_false(state.players[&"two"].ready)
	assert_true(_first_event(second.events, EventKinds.PHASE_CHANGED) != null)
	assert_eq(state.players[&"one"].ability_hand.size(), 4)


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
