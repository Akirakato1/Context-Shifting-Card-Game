class_name MatchController
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const CardFactory = preload("res://src/core/cards/card_factory.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const AbilityState = preload("res://src/core/abilities/ability_state.gd")
const EventKinds = preload("res://src/core/events/event_kinds.gd")
const DomainEvent = preload("res://src/core/events/domain_event.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const CommandResult = preload("res://src/core/commands/command_result.gd")
const MatchState = preload("res://src/core/match/match_state.gd")

var state: MatchState
var _accepted_command_ids: Dictionary = {}
var _start_requests: Dictionary = {}


func _init(match_state: MatchState) -> void:
	state = match_state
	for player_id in state.players:
		_accepted_command_ids[player_id] = {}
	if state.phase == GameTypes.Phase.START:
		_prepare_start_phase()


func submit(command: GameCommand, now_msec: int) -> CommandResult:
	var common_error := _validate_common(command)
	if not common_error.is_empty():
		return CommandResult.new(false, common_error)
	if _accepted_command_ids[command.player_id].has(command.command_id):
		return CommandResult.new(false, &"duplicate_command")

	var result: CommandResult
	if state.phase == GameTypes.Phase.START:
		result = _submit_start(command, now_msec)
	else:
		result = CommandResult.new(false, &"command_not_allowed_in_phase")
	if result.accepted:
		_accepted_command_ids[command.player_id][command.command_id] = true
	return result


func tick(now_msec: int) -> Array[DomainEvent]:
	if state.match_complete:
		return []
	if state.phase == GameTypes.Phase.START:
		_ensure_phase_clock(now_msec)
		if now_msec >= state.phase_deadline_msec:
			return _finish_start(now_msec)
	return []


func _validate_common(command: GameCommand) -> StringName:
	if command == null or command.command_id.is_empty() or command.player_id.is_empty() or command.kind.is_empty():
		return &"malformed_command"
	if not state.players.has(command.player_id):
		return &"unknown_player"
	if not state.players[command.player_id].active or state.players[command.player_id].pending:
		return &"not_active_player"
	return &""


func _submit_start(command: GameCommand, now_msec: int) -> CommandResult:
	match command.kind:
		CommandKinds.SET_REPLENISHMENT_REQUEST:
			if not command.payload.has("request") or not command.payload.request is Dictionary:
				return CommandResult.new(false, &"malformed_command")
			var needed_halves: int = state.players[command.player_id].replenishment_needed * 2
			if needed_halves == 0:
				return CommandResult.new(false, &"no_replenishment_needed")
			var request_error := _validate_partial_request(command.payload.request, needed_halves)
			if not request_error.is_empty():
				return CommandResult.new(false, request_error)
			_start_requests[command.player_id] = command.payload.request.duplicate()
			_ensure_phase_clock(now_msec)
			return CommandResult.new(true)
		CommandKinds.SET_READY:
			if not command.payload.has("ready") or not command.payload.ready is bool:
				return CommandResult.new(false, &"malformed_command")
			state.players[command.player_id].ready = command.payload.ready
			_ensure_phase_clock(now_msec)
			var events: Array[DomainEvent] = []
			if _all_active_ready():
				events = _finish_start(now_msec)
			return CommandResult.new(true, &"", events)
	return CommandResult.new(false, &"command_not_allowed_in_phase")


func _prepare_start_phase() -> void:
	if state.start_prepared_round == state.round_number:
		return
	if state.round_number > 1:
		state.active_context = posmod(
			state.active_context + state.context_direction, 3
		)
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if player.active and not player.pending:
			player.replenishment_needed = max(6 - player.hand.size(), 0)
			player.ready = false
	state.start_prepared_round = state.round_number
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1


func _ensure_phase_clock(now_msec: int) -> void:
	if state.phase_started_msec >= 0:
		return
	state.phase_started_msec = now_msec
	state.phase_deadline_msec = now_msec + state.config.phase_timers[state.phase]


func _finish_start(now_msec: int) -> Array[DomainEvent]:
	var events: Array[DomainEvent] = []
	var completed_requests := {}
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if not player.active or player.pending or player.replenishment_needed == 0:
			continue
		var partial: Dictionary = _start_requests.get(player_id, {})
		var completion := CardFactory.complete_request(
			partial, player.replenishment_needed * 2, state.rng
		)
		assert(completion.ok, "stored replenishment request must be completable")
		completed_requests[str(player_id)] = completion.request.duplicate()

	if (
		not completed_requests.is_empty()
		and state.config.information_visibility == GameTypes.InformationVisibility.PUBLIC
	):
		events.append(DomainEvent.new(
			EventKinds.REPLENISHMENT_REQUESTS_REVEALED,
			{"requests": completed_requests}, &"public"
		))

	for player_id in state.seat_order:
		var player = state.players[player_id]
		if not player.active or player.pending:
			continue
		if player.replenishment_needed > 0:
			var cards: Array[FullCardState] = CardFactory.draw_replenishment(
				state.piles, completed_requests[str(player_id)], state.rng
			)
			player.hand.append_array(cards)
			player.replenishment_needed = 0
			events.append(DomainEvent.new(
				EventKinds.HAND_REPLENISHED,
				{"player_id": str(player_id), "cards": _private_card_payload(cards)},
				&"player", player_id
			))

	for player_id in state.seat_order:
		var player = state.players[player_id]
		if not player.active or player.pending:
			continue
		var drawn: Array[AbilityState] = state.ability_deck.draw(
			player_id, state.ability_deck.start_draw_count, state.rng
		)
		player.ability_hand.append_array(drawn)
		for ability in drawn:
			events.append(DomainEvent.new(
				EventKinds.ABILITY_DRAWN,
				{"player_id": str(player_id), "copy_id": str(ability.copy_id), "definition_id": str(ability.definition.id)},
				&"player", player_id
			))
	state.start_ability_drawn_round = state.round_number
	for player_id in state.seat_order:
		state.players[player_id].ready = false
	state.phase = GameTypes.Phase.MAIN_1
	state.phase_started_msec = now_msec
	state.phase_deadline_msec = now_msec + state.config.phase_timers[GameTypes.Phase.MAIN_1]
	events.append(DomainEvent.new(
		EventKinds.PHASE_CHANGED, {"phase": GameTypes.Phase.MAIN_1}, &"public"
	))
	_start_requests.clear()
	return events


func _validate_partial_request(request: Dictionary, needed_halves: int) -> StringName:
	var total := 0
	for context in request:
		if not context is int or context < GameTypes.Context.A or context > GameTypes.Context.C:
			return &"unknown_context"
		if not request[context] is int:
			return &"invalid_context_count"
		if request[context] < 0:
			return &"negative_context_count"
		if request[context] > CardFactory.CONTEXT_DRAW_CAP:
			return &"context_count_exceeds_cap"
		total += request[context]
	if total > needed_halves:
		return &"request_exceeds_needed_halves"
	return &""


func _all_active_ready() -> bool:
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if player.active and not player.pending and not player.ready:
			return false
	return true


func _private_card_payload(cards: Array[FullCardState]) -> Array:
	var result: Array = []
	for card in cards:
		result.append({
			"card_id": str(card.card_id),
			"first_id": str(card.first.copy_id), "second_id": str(card.second.copy_id),
		})
	return result
