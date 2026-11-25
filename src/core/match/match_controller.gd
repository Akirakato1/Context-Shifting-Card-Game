class_name MatchController
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const CardFactory = preload("res://src/core/cards/card_factory.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const AbilityState = preload("res://src/core/abilities/ability_state.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const ManipulationResolver = preload("res://src/core/abilities/manipulation_resolver.gd")
const EffectRegistry = preload("res://src/core/abilities/effect_registry.gd")
const EventKinds = preload("res://src/core/events/event_kinds.gd")
const DomainEvent = preload("res://src/core/events/domain_event.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const CommandResult = preload("res://src/core/commands/command_result.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const PlayerState = preload("res://src/core/match/player_state.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const Rational = preload("res://src/core/common/rational.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")
const ScoreCalculator = preload("res://src/core/scoring/score_calculator.gd")
const SubmissionEvaluator = preload("res://src/core/scoring/submission_evaluator.gd")
const FieldEffectResolver = preload("res://src/core/abilities/field_effect_resolver.gd")

var state: MatchState
var _accepted_command_ids: Dictionary = {}
var _start_requests: Dictionary = {}
var _effect_registry: EffectRegistry
var _end_transaction_active := false
var _queued_disconnects: Array[Dictionary] = []
var _reconnect_token_provider: Callable
var _phase_deadlines_enabled: bool
var end_transaction_probe: Callable


func _init(
	match_state: MatchState,
	effects: EffectRegistry = null,
	reconnect_token_provider: Callable = Callable(),
	phase_deadlines_enabled: bool = true
) -> void:
	state = match_state
	_effect_registry = effects if effects != null else EffectRegistry.new()
	_reconnect_token_provider = reconnect_token_provider
	_phase_deadlines_enabled = phase_deadlines_enabled
	_accepted_command_ids = state.accepted_command_ids
	_start_requests = state.start_requests
	for player_id in state.players:
		if not _accepted_command_ids.has(player_id):
			_accepted_command_ids[player_id] = {}
	if state.phase == GameTypes.Phase.START:
		_prepare_start_phase()
	elif state.phase in [GameTypes.Phase.MAIN_1, GameTypes.Phase.MAIN_2]:
		_update_main_readiness(false)


func begin_match(now_msec: int) -> Array[DomainEvent]:
	if state.round_number != 1 or state.phase != GameTypes.Phase.START or state.match_complete:
		return []
	state.config.lock_for_match()
	state.start_ability_drawn_round = state.round_number
	var clock_start := state.freeze_started_msec if state.frozen else now_msec
	return _record_events([_begin_main_one(clock_start)])


func submit(command: GameCommand, now_msec: int) -> CommandResult:
	if command != null and command.kind == CommandKinds.JOIN_ACTIVE:
		return _record_result(_join_active(command))
	if command != null and command.kind == CommandKinds.JOIN_SPECTATOR:
		return _record_result(_join_spectator(command))
	if command != null and command.kind == CommandKinds.SET_AVATAR:
		return _set_avatar(command)
	if command != null and command.kind == CommandKinds.RECONNECT:
		return _record_result(_submit_reconnect(command, now_msec))
	if command != null and command.kind == CommandKinds.FORFEIT:
		return _record_result(_forfeit_command(command, now_msec))
	if state.frozen:
		return CommandResult.new(false, &"match_frozen")
	var common_error := _validate_common(command)
	if not common_error.is_empty():
		return CommandResult.new(false, common_error)
	if _accepted_command_ids[command.player_id].has(command.command_id):
		return CommandResult.new(false, &"duplicate_command")
	if not _command_allowed_in_current_phase(command.kind):
		return CommandResult.new(false, &"command_not_allowed_in_phase")
	if state.phase_deadline_msec >= 0 and now_msec > state.phase_deadline_msec:
		return CommandResult.new(false, &"phase_deadline_passed")
	if state.players[command.player_id].abilities_disabled and command.kind in [
		CommandKinds.PLAY_PUBLIC_ABILITY, CommandKinds.STAGE_MANIPULATION, CommandKinds.COMMIT_MANIPULATION,
	]:
		return CommandResult.new(false, &"abilities_disabled")

	var result: CommandResult
	if command.kind == CommandKinds.CONFIGURE_JOKER:
		result = _configure_joker(command)
	elif state.phase == GameTypes.Phase.START:
		result = _submit_start(command, now_msec)
	elif state.phase == GameTypes.Phase.MAIN_1:
		result = _submit_main_one(command, now_msec)
	elif state.phase == GameTypes.Phase.HAND_PLAY:
		result = _submit_hand_play(command, now_msec)
	elif state.phase == GameTypes.Phase.MAIN_2:
		result = _submit_main_two(command, now_msec)
	elif state.phase == GameTypes.Phase.END:
		result = _submit_end(command, now_msec)
	else:
		result = CommandResult.new(false, &"command_not_allowed_in_phase")
	if result.accepted:
		_accepted_command_ids[command.player_id][command.command_id] = true
		state.record_public_events(result.events)
	return result


func _record_result(result: CommandResult) -> CommandResult:
	if result.accepted:
		state.record_public_events(result.events)
	return result


func tick(now_msec: int) -> Array[DomainEvent]:
	if state.match_complete and state.phase != GameTypes.Phase.END:
		return []
	if state.frozen:
		return _record_events(_tick_disconnects(now_msec))
	if state.phase == GameTypes.Phase.START:
		if not state.config.match_started:
			return []
		_ensure_phase_clock(now_msec)
		if _all_active_ready() or _phase_deadline_reached(now_msec):
			return _record_events(_finish_start(now_msec))
	elif state.phase == GameTypes.Phase.MAIN_1:
		_ensure_phase_clock(now_msec)
		if _phase_deadline_reached(now_msec):
			return _record_events(_finish_main_one(now_msec))
		if _can_close_main_phase(now_msec):
			return _record_events(_finish_main_one(now_msec))
	elif state.phase == GameTypes.Phase.HAND_PLAY:
		_ensure_phase_clock(now_msec)
		if _phase_deadline_reached(now_msec):
			return _record_events(_finish_hand_play(now_msec))
		if _all_hands_locked():
			return _record_events(_resolve_hand_play(now_msec))
	elif state.phase == GameTypes.Phase.MAIN_2:
		_ensure_phase_clock(now_msec)
		if _phase_deadline_reached(now_msec):
			return _record_events(_finish_main_two(now_msec))
		if _can_close_main_phase(now_msec):
			return _record_events(_finish_main_two(now_msec))
	elif state.phase == GameTypes.Phase.END:
		if state.match_complete:
			return _record_events(_complete_end(now_msec))
		_ensure_phase_clock(now_msec)
		if _all_end_discards_complete() or _phase_deadline_reached(now_msec):
			return _record_events(_finish_end_discards(now_msec))
	return []


func _phase_deadline_reached(now_msec: int) -> bool:
	return state.phase_deadline_msec >= 0 and now_msec >= state.phase_deadline_msec


func _phase_deadline_after(now_msec: int, duration_msec: int) -> int:
	return now_msec + duration_msec if _phase_deadlines_enabled and not state.config.no_time_limit else -1


func _record_events(events: Array[DomainEvent]) -> Array[DomainEvent]:
	state.record_public_events(events)
	return events


func _validate_common(command: GameCommand) -> StringName:
	if command == null or command.command_id.is_empty() or command.player_id.is_empty() or command.kind.is_empty():
		return &"malformed_command"
	if not state.players.has(command.player_id):
		return &"unknown_player"
	if not state.players[command.player_id].active or state.players[command.player_id].pending:
		return &"not_active_player"
	return &""


func _validate_lifecycle_command(command: GameCommand) -> StringName:
	if command == null or command.command_id.is_empty() or command.player_id.is_empty():
		return &"malformed_command"
	if not state.players.has(command.player_id):
		return &"unknown_player"
	if not _accepted_command_ids.has(command.player_id):
		_accepted_command_ids[command.player_id] = {}
	if _accepted_command_ids[command.player_id].has(command.command_id):
		return &"duplicate_command"
	return &""


func _set_avatar(command: GameCommand) -> CommandResult:
	var error := _validate_lifecycle_command(command)
	if not error.is_empty():
		return CommandResult.new(false, error)
	var player: PlayerState = state.players[command.player_id]
	var avatar: Variant = command.payload.get("avatar_id")
	if not avatar is String or avatar not in GameTypes.AVATAR_IDS:
		return CommandResult.new(false, &"invalid_avatar")
	if not player.avatar_id.is_empty():
		return CommandResult.new(false, &"avatar_already_set")
	if not (player.active or player.pending or player.spectator):
		return CommandResult.new(false, &"not_active_player")
	player.avatar_id = avatar
	_accepted_command_ids[command.player_id][command.command_id] = true
	return CommandResult.new(true)


func _is_identifier(value: Variant) -> bool:
	return value is String or value is StringName


func _command_allowed_in_current_phase(kind: StringName) -> bool:
	if kind == CommandKinds.CONFIGURE_JOKER:
		return state.phase in [GameTypes.Phase.START, GameTypes.Phase.MAIN_1, GameTypes.Phase.HAND_PLAY]
	match state.phase:
		GameTypes.Phase.START:
			if not state.config.match_started:
				return kind in [CommandKinds.SET_LOBBY_READY, CommandKinds.SET_READY]
			return kind in [CommandKinds.SET_REPLENISHMENT_REQUEST, CommandKinds.SET_READY]
		GameTypes.Phase.MAIN_1, GameTypes.Phase.MAIN_2:
			return kind in [CommandKinds.SET_READY, CommandKinds.PLAY_PUBLIC_ABILITY]
		GameTypes.Phase.HAND_PLAY:
			return kind in [
				CommandKinds.STAGE_MANIPULATION, CommandKinds.CANCEL_MANIPULATION,
				CommandKinds.COMMIT_MANIPULATION, CommandKinds.STAGE_HAND,
				CommandKinds.UPDATE_HAND_DRAFT,
				CommandKinds.LOCK_HAND, CommandKinds.UNLOCK_HAND,
			]
		GameTypes.Phase.END:
			return kind == CommandKinds.CHOOSE_ABILITY_DISCARDS
	return false


func _submit_start(command: GameCommand, now_msec: int) -> CommandResult:
	if not state.config.match_started:
		if not command.payload.get("ready") is bool:
			return CommandResult.new(false, &"malformed_command")
		state.players[command.player_id].ready = command.payload.ready
		return CommandResult.new(true)
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
			if (
				state.players[command.player_id].replenishment_needed == 0
				and not command.payload.ready
			):
				return CommandResult.new(false, &"no_replenishment_needed")
			state.players[command.player_id].ready = command.payload.ready
			_ensure_phase_clock(now_msec)
			var events: Array[DomainEvent] = []
			if _all_active_ready():
				events = _finish_start(now_msec)
			return CommandResult.new(true, &"", events)
	return CommandResult.new(false, &"command_not_allowed_in_phase")


func _prepare_start_phase() -> Array[DomainEvent]:
	var events: Array[DomainEvent] = []
	if state.start_prepared_round == state.round_number:
		return events
	if state.round_number > 1:
		state.active_context = posmod(
			state.active_context + state.context_direction, 3
		)
		events.append(DomainEvent.new(
			EventKinds.CONTEXT_ADVANCED,
			{"context": state.active_context, "direction": state.context_direction}, &"public"
		))
	for player_id in state.seat_order:
		var pending_player = state.players[player_id]
		if pending_player.pending and pending_player.activation_round <= state.round_number:
			pending_player.pending = false
			pending_player.active = true
			pending_player.match_score = 0
			pending_player.round_wins = 0
			pending_player.hand = CardFactory.build_opening_hand(
				state.piles, state.rng, state.allocate_card_id
			)
			pending_player.ability_hand = state.ability_deck.draw(
				player_id, mini(state.ability_deck.starting_hand_size, state.ability_deck.end_hand_limit), state.rng
			)
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if player.active and not player.pending:
			player.replenishment_needed = max(6 - player.hand.size(), 0)
			player.ready = state.config.match_started and player.replenishment_needed == 0
	state.start_prepared_round = state.round_number
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	state.reaction_deadline_msec = -1
	return events


func _ensure_phase_clock(now_msec: int) -> void:
	if state.phase_started_msec >= 0:
		return
	state.phase_started_msec = now_msec
	if state.phase == GameTypes.Phase.MAIN_1 or state.phase == GameTypes.Phase.MAIN_2:
		state.phase_deadline_msec = _phase_deadline_after(now_msec, state.config.public_hard_limit_msec)
	else:
		state.phase_deadline_msec = _phase_deadline_after(now_msec, state.config.phase_timers[state.phase])


func _finish_start(now_msec: int) -> Array[DomainEvent]:
	var events: Array[DomainEvent] = []
	var completed_requests := {}
	var replacement_counts := {}
	var timeout_halves := {}
	var timed_out := _phase_deadline_reached(now_msec)
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
		replacement_counts[str(player_id)] = player.replenishment_needed
		if timed_out:
			var remaining: int = player.replenishment_needed * 2
			for count: int in partial.values():
				remaining -= count
			timeout_halves[player_id] = remaining

	if not completed_requests.is_empty():
		var reveal_payload := {"counts": replacement_counts}
		if state.config.information_visibility == GameTypes.InformationVisibility.PUBLIC:
			reveal_payload["requests"] = completed_requests
		events.append(DomainEvent.new(
			EventKinds.REPLENISHMENT_REQUESTS_REVEALED,
			reveal_payload, &"public"
		))

	for player_id in state.seat_order:
		var player = state.players[player_id]
		if not player.active or player.pending:
			continue
		if player.replenishment_needed > 0:
			var cards: Array[FullCardState] = CardFactory.draw_replenishment(
				state.piles, completed_requests[str(player_id)], state.rng,
				state.allocate_card_id
			)
			player.hand.append_array(cards)
			player.replenishment_needed = 0
			var payload := {"player_id": str(player_id), "cards": _private_card_payload(cards)}
			if timeout_halves.get(player_id, 0) > 0:
				payload["automatic_halves"] = timeout_halves[player_id]
				payload["round_number"] = state.round_number
			events.append(DomainEvent.new(
				EventKinds.HAND_REPLENISHED, payload, &"player", player_id
			))

	var drawn_by_player := state.deal_start_abilities()
	for player_id in drawn_by_player:
		for ability: AbilityState in drawn_by_player[player_id]:
			events.append(DomainEvent.new(
				EventKinds.ABILITY_DRAWN,
				{"player_id": str(player_id), "copy_id": str(ability.copy_id), "definition_id": str(ability.definition.id)},
				&"player", player_id
			))
	events.append(_begin_main_one(now_msec))
	return events


func _begin_main_one(now_msec: int) -> DomainEvent:
	_update_main_readiness()
	state.phase = GameTypes.Phase.MAIN_1
	state.phase_started_msec = now_msec
	state.phase_deadline_msec = _phase_deadline_after(now_msec, state.config.public_hard_limit_msec)
	state.reaction_deadline_msec = -1
	_start_requests.clear()
	return DomainEvent.new(
		EventKinds.PHASE_CHANGED, {"phase": GameTypes.Phase.MAIN_1}, &"public"
	)


func _submit_main_one(command: GameCommand, now_msec: int) -> CommandResult:
	match command.kind:
		CommandKinds.SET_READY:
			if not command.payload.has("ready") or not command.payload.ready is bool:
				return CommandResult.new(false, &"malformed_command")
			_ensure_phase_clock(now_msec)
			if state.phase_deadline_msec >= 0 and now_msec > state.phase_deadline_msec:
				return CommandResult.new(false, &"phase_deadline_passed")
			var player: PlayerState = state.players[command.player_id]
			player.ready = command.payload.ready or player.ability_hand.is_empty()
			var ready_events: Array[DomainEvent] = []
			if _can_close_main_phase(now_msec):
				ready_events = _finish_main_one(now_msec)
			return CommandResult.new(true, &"", ready_events)
		CommandKinds.PLAY_PUBLIC_ABILITY:
			return _play_public_ability(command, now_msec)
	return CommandResult.new(false, &"command_not_allowed_in_phase")


func _submit_main_two(command: GameCommand, now_msec: int) -> CommandResult:
	match command.kind:
		CommandKinds.SET_READY:
			if not command.payload.has("ready") or not command.payload.ready is bool:
				return CommandResult.new(false, &"malformed_command")
			_ensure_phase_clock(now_msec)
			if state.phase_deadline_msec >= 0 and now_msec > state.phase_deadline_msec:
				return CommandResult.new(false, &"phase_deadline_passed")
			var player: PlayerState = state.players[command.player_id]
			player.ready = command.payload.ready or player.ability_hand.is_empty()
			var ready_events: Array[DomainEvent] = []
			if _can_close_main_phase(now_msec):
				ready_events = _finish_main_two(now_msec)
			return CommandResult.new(true, &"", ready_events)
		CommandKinds.PLAY_PUBLIC_ABILITY:
			return _play_public_ability(command, now_msec)
	return CommandResult.new(false, &"command_not_allowed_in_phase")


func _play_public_ability(command: GameCommand, now_msec: int) -> CommandResult:
	for key in command.payload:
		if key not in ["copy_id", "target_player_id", "choices"]:
			return CommandResult.new(false, &"unexpected_effect_payload")
	if not command.payload.has("copy_id") or not _is_identifier(command.payload.copy_id):
		return CommandResult.new(false, &"malformed_command")
	if command.payload.has("effect"):
		return CommandResult.new(false, &"unexpected_effect_payload")
	var copy_id := StringName(command.payload.copy_id)
	var ability := _held_ability(command.player_id, copy_id)
	if ability == null:
		return CommandResult.new(false, &"ability_not_in_hand")
	if not ability.definition.allows_phase(state.phase):
		return CommandResult.new(false, &"ability_timing_not_allowed")
	if ability.definition.timing == AbilityDefinition.Timing.HAND_MANIPULATION:
		return CommandResult.new(false, &"ability_timing_not_allowed")
	var raw_target: Variant = command.payload.get("target_player_id", &"")
	if not _is_identifier(raw_target):
		return CommandResult.new(false, &"malformed_command")
	var target_player_id := StringName(raw_target)
	var choices: Variant = command.payload.get("choices", {})
	if not choices is Dictionary:
		return CommandResult.new(false, &"malformed_command")
	var choice_error := _validate_public_ability_choices(
		ability.definition.choice_schema, choices
	)
	if not choice_error.is_empty():
		return CommandResult.new(false, choice_error)
	if choices.has("target_player_id"):
		var selected_targets: Array = choices.target_player_id
		if selected_targets.size() != 1 or str(selected_targets[0]) != str(target_player_id):
			return CommandResult.new(false, &"target_choice_mismatch")
	var effect_payload: Dictionary = ability.definition.effect_parameters
	var effect_context := {
		"state": state, "source_player_id": command.player_id,
		"target_player_id": target_player_id, "ability": ability,
		"effect": effect_payload, "choices": choices.duplicate(true),
	}
	var effect_error := _effect_registry.validate(ability.definition.effect_id, effect_context)
	if not effect_error.is_empty():
		return CommandResult.new(false, effect_error)
	_ensure_phase_clock(now_msec)
	if state.phase_deadline_msec >= 0 and now_msec > state.phase_deadline_msec:
		return CommandResult.new(false, &"phase_deadline_passed")

	var events: Array[DomainEvent] = [DomainEvent.new(
		EventKinds.PUBLIC_ABILITY_PLAYED,
		{"ability_id": str(ability.definition.id), "source_player_id": str(command.player_id),
		"target_player_id": str(target_player_id)}, &"public"
	)]
	_remove_held_ability(command.player_id, ability)
	if ability.definition.timing == AbilityDefinition.Timing.FIELD:
		var field_result := {"field": null, "replaced": null}
		if ability.definition.is_instant_field():
			state.ability_deck.discard(ability)
		else:
			field_result = state.ability_deck.play_field(ability, command.player_id)
		events.append(DomainEvent.new(
			EventKinds.FIELD_PLAYED,
			{"ability_id": str(ability.definition.id), "source_player_id": str(command.player_id)},
			&"public"
		))
		if field_result.replaced != null:
			events.append(DomainEvent.new(
				EventKinds.FIELD_REPLACED,
				{"old_ability_id": str(field_result.replaced.ability.definition.id),
				"new_ability_id": str(ability.definition.id)}, &"public"
			))
	else:
		state.ability_deck.discard(ability)
	events.append_array(_effect_registry.apply(ability.definition.effect_id, effect_context))
	if state.phase == GameTypes.Phase.MAIN_2 and not target_player_id.is_empty():
		var target = state.players.get(target_player_id)
		if target != null and target.locked_normal != null and target.locked_context != null:
			target.provisional_score = _calculate_player_score(target)
			events.append(DomainEvent.new(
				EventKinds.PROVISIONAL_SCORE_UPDATED,
				{"player_id": str(target_player_id),
				"provisional_score": target.provisional_score.final_score}, &"public"
			))
	_update_main_readiness()
	state.reaction_deadline_msec = now_msec + state.config.reaction_window_msec
	if state.phase_deadline_msec >= 0:
		state.reaction_deadline_msec = mini(state.reaction_deadline_msec, state.phase_deadline_msec)
	if _phase_deadline_reached(now_msec):
		if state.phase == GameTypes.Phase.MAIN_1:
			events.append_array(_finish_main_one(now_msec))
		else:
			events.append_array(_finish_main_two(now_msec))
	return CommandResult.new(true, &"", events)


func _finish_main_one(now_msec: int) -> Array[DomainEvent]:
	for player_id in state.seat_order:
		state.players[player_id].ready = false
	state.phase = GameTypes.Phase.HAND_PLAY
	state.phase_started_msec = now_msec
	state.phase_deadline_msec = _phase_deadline_after(now_msec, state.config.phase_timers[GameTypes.Phase.HAND_PLAY])
	state.reaction_deadline_msec = -1
	return [DomainEvent.new(
		EventKinds.PHASE_CHANGED, {"phase": GameTypes.Phase.HAND_PLAY}, &"public"
	)]


func _finish_main_two(now_msec: int) -> Array[DomainEvent]:
	for player_id in state.seat_order:
		state.players[player_id].ready = false
	return _begin_end(now_msec)


func _begin_end(now_msec: int) -> Array[DomainEvent]:
	_end_transaction_active = true
	var events: Array[DomainEvent] = []
	var final_scores := {}
	var previous_match_scores := {}
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if not player.active or player.pending:
			continue
		player.provisional_score = _calculate_player_score(player)
		player.finalized_score = player.provisional_score.final_score
		final_scores[player_id] = player.finalized_score
		previous_match_scores[player_id] = player.match_score
	state.last_round_winner_id = state.resolve_round(final_scores)
	var outcome := {
		"scores": _string_key_scores(final_scores),
		"round_number": state.round_number,
		"winner_id": str(state.last_round_winner_id),
	}
	if state.config.victory_mode == GameTypes.VictoryMode.SCORE_RACE:
		var winner := state.last_round_winner_id
		outcome["points_awarded"] = 0 if winner.is_empty() else state.players[winner].match_score - previous_match_scores[winner]
	events.append(DomainEvent.new(EventKinds.ROUND_FINALIZED, outcome, &"public"))
	if end_transaction_probe.is_valid():
		end_transaction_probe.call()
		end_transaction_probe = Callable()

	for player_id in state.seat_order:
		var player = state.players[player_id]
		for card in player.submitted_cards.duplicate():
			player.hand.erase(card)
			card.leave_hand()
			state.piles[card.first.base_context].discard(card.first)
			state.piles[card.second.base_context].discard(card.second)
		player.submitted_cards.clear()
		player.submitted_faces.clear()
		# The public card views are detached from the cards returning to the piles.
		# Keep them available while players resolve ability discards in End.
		player.factor_modifiers.clear()
		player.pending_manipulation.clear()
		player.staged_submission.clear()
		player.has_staged_submission = false
		player.deadline_submission = null
		player.hand_locked = false
		player.abilities_disabled = false
		player.completed_manipulation_ids.clear()
		player.submission_locked_card_ids.clear()
		player.ready = false
		player.end_discard_copy_ids.clear()
		player.end_discard_complete = player.ability_hand.size() <= state.ability_deck.end_hand_limit

	var expired_fields = state.ability_deck.tick_fields_end()
	for field in expired_fields:
		events.append(DomainEvent.new(
			EventKinds.FIELD_EXPIRED, {"ability_id": str(field.ability.definition.id)}, &"public"
		))
	_end_transaction_active = false
	for queued: Dictionary in _queued_disconnects:
		_apply_disconnect(queued.player_id, queued.detected_msec)
	_queued_disconnects.clear()

	if state.match_complete or _all_end_discards_complete():
		events.append_array(_complete_end(now_msec))
	else:
		state.phase = GameTypes.Phase.END
		state.phase_started_msec = now_msec
		state.phase_deadline_msec = _phase_deadline_after(now_msec, state.config.phase_timers[GameTypes.Phase.END])
		state.reaction_deadline_msec = -1
	return events


func _submit_end(command: GameCommand, now_msec: int) -> CommandResult:
	if command.kind != CommandKinds.CHOOSE_ABILITY_DISCARDS:
		return CommandResult.new(false, &"command_not_allowed_in_phase")
	if not command.payload.has("copy_ids") or not command.payload.copy_ids is Array:
		return CommandResult.new(false, &"malformed_command")
	var player = state.players[command.player_id]
	if player.end_discard_complete:
		return CommandResult.new(false, &"discard_already_confirmed")
	var excess: int = max(player.ability_hand.size() - state.ability_deck.end_hand_limit, 0)
	if command.payload.copy_ids.size() != excess:
		return CommandResult.new(false, &"incorrect_discard_count")
	var selected: Array[StringName] = []
	for raw_id in command.payload.copy_ids:
		if not _is_identifier(raw_id):
			return CommandResult.new(false, &"malformed_command")
		var copy_id := StringName(raw_id)
		if copy_id in selected:
			return CommandResult.new(false, &"duplicate_ability_discard")
		if _held_ability(command.player_id, copy_id) == null:
			return CommandResult.new(false, &"ability_not_in_hand")
		selected.append(copy_id)
	_ensure_phase_clock(now_msec)
	player.end_discard_copy_ids = selected
	player.end_discard_complete = true
	var events: Array[DomainEvent] = []
	if _all_end_discards_complete():
		events = _finish_end_discards(now_msec)
	return CommandResult.new(true, &"", events)


func _finish_end_discards(now_msec: int) -> Array[DomainEvent]:
	var events: Array[DomainEvent] = []
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if not player.active or player.pending:
			continue
		var cards: Array[AbilityState] = []
		for copy_id: StringName in player.end_discard_copy_ids:
			var selected := _held_ability(player_id, copy_id)
			if selected != null:
				cards.append(selected)
		if not player.end_discard_complete:
			var excess := maxi(player.ability_hand.size() - state.ability_deck.end_hand_limit, 0)
			if excess > 0:
				cards.assign(state.rng.shuffle(player.ability_hand).slice(0, excess))
		if not cards.is_empty():
			events.append_array(_discard_abilities(player_id, cards))
		player.end_discard_copy_ids.clear()
		player.end_discard_complete = true
	events.append_array(_complete_end(now_msec))
	return events


func _discard_abilities(player_id: StringName, cards: Array[AbilityState]) -> Array[DomainEvent]:
	var ability_ids: Array = []
	for ability in cards:
		state.players[player_id].ability_hand.erase(ability)
		state.ability_deck.discard(ability)
		ability_ids.append(str(ability.definition.id))
	var public_payload := {"player_id": str(player_id), "count": cards.size()}
	var events: Array[DomainEvent] = []
	if state.config.information_visibility == GameTypes.InformationVisibility.PUBLIC:
		public_payload["ability_ids"] = ability_ids
		events.append(DomainEvent.new(EventKinds.ABILITIES_DISCARDED, public_payload, &"public"))
	else:
		events.append(DomainEvent.new(EventKinds.ABILITIES_DISCARDED, public_payload, &"public"))
		events.append(DomainEvent.new(EventKinds.ABILITIES_DISCARDED, {
			"player_id": str(player_id), "ability_ids": ability_ids,
		}, &"player", player_id))
	return events


func _complete_end(now_msec: int) -> Array[DomainEvent]:
	for player_id in state.seat_order:
		var player = state.players[player_id]
		player.submitted_card_views.clear()
		player.submission_revealed = false
	if state.match_complete:
		state.phase = GameTypes.Phase.COMPLETE
		state.phase_started_msec = now_msec
		state.phase_deadline_msec = -1
		state.reaction_deadline_msec = -1
		state.config.match_started = false
		return [DomainEvent.new(EventKinds.MATCH_ENDED, {
			"winner_id": str(state.winner_id), "reason": state.end_reason,
		}, &"public")]
	state.round_number += 1
	state.phase = GameTypes.Phase.START
	state.start_prepared_round = 0
	state.start_ability_drawn_round = 0
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	state.reaction_deadline_msec = -1
	var events := _prepare_start_phase()
	events.append(DomainEvent.new(
		EventKinds.PHASE_CHANGED,
		{"phase": GameTypes.Phase.START, "round_number": state.round_number}, &"public"
	))
	return events


func notify_player_disconnected(player_id: StringName, now_msec: int = 0) -> void:
	if not state.players.has(player_id):
		return
	if _end_transaction_active:
		for queued: Dictionary in _queued_disconnects:
			if queued.player_id == player_id:
				return
		_queued_disconnects.append({"player_id": player_id, "detected_msec": now_msec})
		return
	_apply_disconnect(player_id, now_msec)


func remove_transient_participant(player_id: StringName) -> Array[DomainEvent]:
	if player_id == state.host_player_id or not state.players.has(player_id):
		return []
	var player: PlayerState = state.players[player_id]
	var keep_result := state.match_complete and not player.spectator and not player.pending
	if player.spectator:
		state.config.unregister_spectator(player_id)
	elif player.pending or not state.config.match_started or keep_result:
		state.seat_order.erase(player_id)
		state.config.unregister_active_participant(player_id)
		if not keep_result:
			_discard_player_hand(player)
			for ability in player.ability_hand:
				state.ability_deck.discard(ability)
	else:
		return []
	if keep_result:
		player.active = false
		player.connected = false
		player.ready = false
		player.disconnect_deadline_msec = -1
		player.reconnect_token = ""
	else:
		state.players.erase(player_id)
	_accepted_command_ids.erase(player_id)
	_start_requests.erase(player_id)
	return [DomainEvent.new(
		&"participant_left", {"player_id": str(player_id)}, &"public"
	)]


func _apply_disconnect(player_id: StringName, now_msec: int) -> void:
	if player_id == state.host_player_id:
		state.players[player_id].connected = false
		state.match_complete = true
		state.winner_id = &""
		state.end_reason = "host_disconnect"
		state.phase = GameTypes.Phase.COMPLETE
		state.config.match_started = false
		return
	var player = state.players[player_id]
	if not player.active or not player.connected:
		return
	player.connected = false
	player.ready = false
	player.disconnect_deadline_msec = now_msec + state.config.reconnect_grace_msec
	if player.reconnect_token.is_empty():
		player.reconnect_token = _new_reconnect_token(player_id)
	if not state.frozen:
		state.frozen = true
		state.freeze_started_msec = now_msec


func _new_reconnect_token(player_id: StringName) -> String:
	if _reconnect_token_provider.is_valid():
		var provided: Variant = _reconnect_token_provider.call(player_id)
		assert(provided is String and not provided.is_empty(), "token provider returned invalid token")
		return provided
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(32).hex_encode()


func reset_for_rematch(new_seed: int, lobby_phase: int = GameTypes.Phase.SETUP) -> void:
	assert(state.match_complete, "only a completed match can reset for rematch")
	var previous := state
	state.config.match_started = false
	var fresh := MatchState.create(state.config, new_seed, true)
	fresh.config.match_started = false
	fresh.phase = lobby_phase
	fresh.frozen = previous.frozen
	fresh.freeze_started_msec = previous.freeze_started_msec
	state = fresh
	_accepted_command_ids = state.accepted_command_ids
	_start_requests = state.start_requests
	for player_id in state.players:
		if previous.players.has(player_id):
			var player: PlayerState = state.players[player_id]
			var old_player: PlayerState = previous.players[player_id]
			player.reconnect_token = old_player.reconnect_token
			player.avatar_id = old_player.avatar_id
			player.connected = old_player.connected
			player.disconnect_deadline_msec = old_player.disconnect_deadline_msec
		if not _accepted_command_ids.has(player_id):
			_accepted_command_ids[player_id] = {}
	if state.phase == GameTypes.Phase.START:
		_prepare_start_phase()


func _all_end_discards_complete() -> bool:
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if player.active and not player.pending and not player.end_discard_complete:
			return false
	return true


func _string_key_scores(scores: Dictionary) -> Dictionary:
	var result := {}
	for player_id in scores:
		result[str(player_id)] = scores[player_id]
	return result


func _join_active(command: GameCommand) -> CommandResult:
	if command.command_id.is_empty() or command.player_id.is_empty():
		return CommandResult.new(false, &"malformed_command")
	if state.players.has(command.player_id):
		return CommandResult.new(false, &"participant_id_in_use")
	if state.seat_order.size() >= 4:
		return CommandResult.new(false, &"active_seats_full")
	var seat_index := _first_open_seat()
	var player = PlayerState.new(command.player_id, seat_index)
	var joining_open_lobby := (
		not state.config.match_started and state.phase == GameTypes.Phase.START
	)
	player.pending = not joining_open_lobby
	player.active = true
	player.activation_round = state.round_number if joining_open_lobby else state.round_number + 1
	if joining_open_lobby:
		player.hand = CardFactory.build_opening_hand(
			state.piles, state.rng, state.allocate_card_id
		)
		player.ability_hand = state.ability_deck.draw(
			command.player_id, state.ability_deck.starting_hand_size, state.rng
		)
	state.players[command.player_id] = player
	state.seat_order.append(command.player_id)
	state.config.register_active_participant(command.player_id)
	_accepted_command_ids[command.player_id] = {command.command_id: true}
	return CommandResult.new(true)


func _join_spectator(command: GameCommand) -> CommandResult:
	if command.command_id.is_empty() or command.player_id.is_empty():
		return CommandResult.new(false, &"malformed_command")
	if state.players.has(command.player_id):
		return CommandResult.new(false, &"participant_id_in_use")
	var spectator_count := 0
	for player in state.players.values():
		if player.spectator:
			spectator_count += 1
	if spectator_count >= 4:
		return CommandResult.new(false, &"spectator_slots_full")
	state.players[command.player_id] = PlayerState.new(command.player_id, -1, true)
	state.config.register_spectator(command.player_id)
	_accepted_command_ids[command.player_id] = {command.command_id: true}
	return CommandResult.new(true)


func _submit_reconnect(command: GameCommand, now_msec: int) -> CommandResult:
	var common_error := _validate_lifecycle_command(command)
	if not common_error.is_empty():
		return CommandResult.new(false, common_error)
	var player = state.players[command.player_id]
	if not player.active or player.pending:
		return CommandResult.new(false, &"not_active_player")
	if player.connected or player.disconnect_deadline_msec < 0:
		return CommandResult.new(false, &"player_not_disconnected")
	if now_msec > player.disconnect_deadline_msec:
		return CommandResult.new(false, &"reconnect_grace_expired")
	if (
		not command.payload.has("token") or not command.payload.token is String
		or command.payload.token != player.reconnect_token
	):
		return CommandResult.new(false, &"invalid_reconnect_token")
	player.connected = true
	player.disconnect_deadline_msec = -1
	player.reconnect_token = _new_reconnect_token(command.player_id)
	_accepted_command_ids[command.player_id][command.command_id] = true
	_resume_if_resolved(now_msec)
	return CommandResult.new(true, &"", [DomainEvent.new(
		&"player_reconnected", {"player_id": str(command.player_id)}, &"public"
	)])


func _forfeit_command(command: GameCommand, now_msec: int) -> CommandResult:
	var common_error := _validate_lifecycle_command(command)
	if not common_error.is_empty():
		return CommandResult.new(false, common_error)
	var player = state.players[command.player_id]
	if not player.active or player.pending or player.spectator:
		return CommandResult.new(false, &"not_active_player")
	if not state.config.match_started or state.match_complete:
		return CommandResult.new(false, &"no_active_match")
	var events := _forfeit_player(command.player_id)
	if command.player_id == state.host_player_id:
		state.match_complete = true
		state.winner_id = &""
		state.end_reason = "forfeit"
	_accepted_command_ids[command.player_id][command.command_id] = true
	_resume_if_resolved(now_msec)
	if state.match_complete:
		events.append_array(_complete_end(now_msec))
	return CommandResult.new(true, &"", events)


func _tick_disconnects(now_msec: int) -> Array[DomainEvent]:
	var events: Array[DomainEvent] = []
	var expired: Array[StringName] = []
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if (
			player.active and not player.connected and player.disconnect_deadline_msec >= 0
			and now_msec >= player.disconnect_deadline_msec
		):
			expired.append(player_id)
	for player_id in expired:
		events.append_array(_forfeit_player(player_id))
	_resume_if_resolved(now_msec)
	if not expired.is_empty() and state.match_complete:
		events.append_array(_complete_end(now_msec))
	return events


func _forfeit_player(player_id: StringName) -> Array[DomainEvent]:
	var player: PlayerState = state.players[player_id]
	var events: Array[DomainEvent] = []
	_discard_player_hand(player)
	var discarded: Array[AbilityState] = []
	discarded.assign(player.ability_hand.duplicate())
	events.append_array(_discard_abilities(player_id, discarded))
	player.pending_manipulation.clear()
	player.staged_submission.clear()
	player.deadline_submission = null
	player.submission_locked_card_ids.clear()
	player.end_discard_copy_ids.clear()
	player.submitted_cards.clear()
	player.submitted_faces.clear()
	player.submitted_card_views.clear()
	player.submission_revealed = false
	player.connected = false
	player.disconnect_deadline_msec = -1
	player.reconnect_token = ""
	_start_requests.erase(player_id)
	state.remove_active_player(player_id)
	state.seat_order.erase(player_id)
	state.config.unregister_active_participant(player_id)
	events.append(DomainEvent.new(
		&"player_forfeited", {"player_id": str(player_id)}, &"public"
	))
	return events


func _discard_player_hand(player: PlayerState) -> void:
	for card in player.hand:
		card.leave_hand()
		state.piles[card.first.base_context].discard(card.first)
		state.piles[card.second.base_context].discard(card.second)
	player.hand.clear()


func _resume_if_resolved(now_msec: int) -> void:
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if player.active and not player.connected and player.disconnect_deadline_msec >= 0:
			return
	if not state.frozen:
		return
	var paused_duration: int = max(now_msec - state.freeze_started_msec, 0)
	if state.phase_started_msec >= 0:
		state.phase_started_msec += paused_duration
	if state.phase_deadline_msec >= 0:
		state.phase_deadline_msec += paused_duration
	if state.reaction_deadline_msec >= 0:
		state.reaction_deadline_msec += paused_duration
	state.frozen = false
	state.freeze_started_msec = -1


func _first_open_seat() -> int:
	var occupied := {}
	for player in state.players.values():
		if not player.spectator and (player.active or player.pending):
			occupied[player.seat_index] = true
	for seat in range(4):
		if not occupied.has(seat):
			return seat
	return -1


func _submit_hand_play(command: GameCommand, now_msec: int) -> CommandResult:
	var player: PlayerState = state.players[command.player_id]
	if command.kind == CommandKinds.UNLOCK_HAND:
		if not player.hand_locked:
			return CommandResult.new(false, &"hand_not_locked")
		if _all_hands_locked():
			return CommandResult.new(false, &"hand_submissions_complete")
		player.hand_locked = false
		player.ready = false
		player.submitted_cards.clear()
		player.submitted_faces.clear()
		player.submitted_card_views.clear()
		player.locked_normal = null
		player.locked_context = null
		player.provisional_score = null
		return CommandResult.new(true)
	if player.hand_locked:
		return CommandResult.new(false, &"hand_already_locked")
	match command.kind:
		CommandKinds.STAGE_MANIPULATION:
			if not command.payload.has("copy_id") or not _is_identifier(command.payload.copy_id):
				return CommandResult.new(false, &"malformed_command")
			var ability := _held_ability(command.player_id, StringName(command.payload.copy_id))
			if ability == null:
				return CommandResult.new(false, &"ability_not_in_hand")
			if ability.definition.timing != AbilityDefinition.Timing.HAND_MANIPULATION:
				return CommandResult.new(false, &"ability_timing_not_allowed")
			if not state.players[command.player_id].pending_manipulation.is_empty():
				return CommandResult.new(false, &"manipulation_already_pending")
			_ensure_phase_clock(now_msec)
			state.players[command.player_id].pending_manipulation = {
				"copy_id": ability.copy_id,
			}
			return CommandResult.new(true)
		CommandKinds.CANCEL_MANIPULATION:
			if state.players[command.player_id].pending_manipulation.is_empty():
				return CommandResult.new(false, &"no_pending_manipulation")
			_ensure_phase_clock(now_msec)
			state.players[command.player_id].pending_manipulation.clear()
			return CommandResult.new(true)
		CommandKinds.COMMIT_MANIPULATION:
			return _commit_manipulation(command, now_msec)
		CommandKinds.STAGE_HAND:
			return _stage_hand(command, now_msec)
		CommandKinds.UPDATE_HAND_DRAFT:
			var round_number: Variant = command.payload.get("round_number")
			if not round_number is int or round_number != state.round_number:
				return CommandResult.new(false, &"invalid_draft_round")
			return _stage_hand(command, now_msec, true)
		CommandKinds.LOCK_HAND:
			if not state.players[command.player_id].pending_manipulation.is_empty():
				return CommandResult.new(false, &"manipulation_incomplete")
			var lock_error := _lock_player_hand(command.player_id, false)
			if not lock_error.is_empty():
				return CommandResult.new(false, lock_error)
			_ensure_phase_clock(now_msec)
			var lock_events: Array[DomainEvent] = []
			if _all_hands_locked():
				lock_events = _resolve_hand_play(now_msec)
			return CommandResult.new(true, &"", lock_events)
	return CommandResult.new(false, &"command_not_allowed_in_phase")


func _commit_manipulation(command: GameCommand, now_msec: int) -> CommandResult:
	var player = state.players[command.player_id]
	if player.pending_manipulation.is_empty():
		return CommandResult.new(false, &"no_pending_manipulation")
	if not command.payload.has("choices") or not command.payload.choices is Dictionary:
		return CommandResult.new(false, &"malformed_command")
	var ability := _held_ability(command.player_id, player.pending_manipulation.copy_id)
	if ability == null:
		return CommandResult.new(false, &"ability_not_in_hand")
	var choice_error := ManipulationResolver.validate(
		ability.definition, player.hand, command.payload.choices
	)
	if not choice_error.is_empty():
		return CommandResult.new(false, choice_error)
	_ensure_phase_clock(now_msec)
	var before := {}
	for card: FullCardState in player.hand:
		before[card.card_id] = card.face_snapshot()
	ManipulationResolver.apply(
		ability.definition,
		player.hand,
		command.payload.choices,
		state.rng,
		state.context_direction
	)
	_remove_held_ability(command.player_id, ability)
	state.ability_deck.discard(ability)
	player.completed_manipulation_ids.append(ability.definition.id)
	player.pending_manipulation.clear()
	var changes: Array = []
	for card: FullCardState in player.hand:
		var after := card.face_snapshot()
		if before[card.card_id] != after:
			changes.append({"before": before[card.card_id], "after": after})
	return CommandResult.new(true, &"", [DomainEvent.new(EventKinds.MANIPULATION_RESOLVED, {
		"ability_id": str(ability.definition.id), "source_player_id": str(command.player_id),
		"card_changes": changes,
	}, &"player", command.player_id)])


func _configure_joker(command: GameCommand) -> CommandResult:
	var player = state.players[command.player_id]
	if player.hand_locked:
		return CommandResult.new(false, &"hand_already_locked")
	var payload := command.payload
	if not _is_identifier(payload.get("card_id")):
		return CommandResult.new(false, &"malformed_command")
	var half_index: Variant = payload.get("half_index")
	if not half_index is int or half_index < 0 or half_index > 1:
		return CommandResult.new(false, &"invalid_joker_half_index")
	var card := _hand_card(command.player_id, StringName(payload.card_id))
	if card == null:
		return CommandResult.new(false, &"card_not_in_hand")
	var half := card.half_at(half_index)
	if not half.is_joker():
		return CommandResult.new(false, &"joker_choice_for_normal_half")
	var context: Variant = payload.get("context")
	var suit: Variant = payload.get("suit")
	var rank: Variant = payload.get("rank", half.joker_rank)
	var error := HalfCardState.joker_choice_error(context, suit, rank)
	if not error.is_empty():
		return CommandResult.new(false, error)
	half.set_joker_choice(context, suit, rank)
	for selection in player.staged_submission:
		if selection.card_id == card.card_id:
			for choice: Dictionary in selection.joker_choices:
				if choice.half_index == half_index:
					choice.context = context
					choice.suit = suit
					if rank > 0:
						choice.rank = rank
					else:
						choice.erase("rank")
			break
	return CommandResult.new(true)


func _stage_hand(command: GameCommand, now_msec: int, for_deadline := false) -> CommandResult:
	if not command.payload.has("cards") or not command.payload.cards is Array:
		return CommandResult.new(false, &"malformed_command")
	var selections: Array = command.payload.cards
	var candidate: Array = []
	for raw_selection in selections:
		if (
			not raw_selection is Dictionary or not raw_selection.has("card_id")
			or not _is_identifier(raw_selection.card_id)
		):
			return CommandResult.new(false, &"malformed_command")
		if not raw_selection.has("half_index"):
			return CommandResult.new(false, &"half_choice_required")
		var normalized: Dictionary = raw_selection.duplicate(true)
		if not normalized.has("joker_choices"):
			normalized["joker_choices"] = []
		candidate.append(normalized)
	var player = state.players[command.player_id]
	for selection: Dictionary in candidate:
		if player.submission_locked_card_ids.has(StringName(selection.card_id)):
			return CommandResult.new(false, &"card_submission_locked")
	var evaluation := SubmissionEvaluator.evaluate(
		player.hand,
		candidate,
		state.active_context,
		state.config.normal_definitions,
		state.config.context_definitions,
		player.factor_modifiers,
		state.ability_deck.active_fields()
	)
	if not evaluation.is_valid:
		return CommandResult.new(false, evaluation.error_code)
	_ensure_phase_clock(now_msec)
	var normalized_submission: Array[Dictionary] = []
	for index in candidate.size():
		var selection: Dictionary = candidate[index]
		var card := evaluation.submitted_cards[index]
		var canonical_choices: Array = []
		for choice: Dictionary in selection.joker_choices:
			var half := card.half_at(choice.half_index)
			var rank: int = choice.get("rank", half.joker_rank)
			if not for_deadline:
				half.set_joker_choice(choice.context, choice.suit, rank)
			var canonical := {
				"half_index": choice.half_index,
				"context": choice.context,
				"suit": choice.suit,
			}
			if rank > 0 or for_deadline:
				canonical["rank"] = rank
			canonical_choices.append(canonical)
		canonical_choices.sort_custom(func(left: Dictionary, right: Dictionary):
			return left.half_index < right.half_index
		)
		normalized_submission.append({
			"card_id": StringName(selection.card_id), "half_index": selection.half_index,
			"joker_choices": canonical_choices,
		})
	if for_deadline:
		player.deadline_submission = normalized_submission
	else:
		player.staged_submission = normalized_submission
		player.has_staged_submission = true
		player.deadline_submission = null
	return CommandResult.new(true)


func _lock_player_hand(
	player_id: StringName,
	default_invalid_to_pass: bool
) -> StringName:
	var player = state.players[player_id]
	var selections: Array = player.staged_submission if player.has_staged_submission else []
	for selection: Dictionary in selections:
		if player.submission_locked_card_ids.has(StringName(selection.card_id)):
			if not default_invalid_to_pass:
				return &"card_submission_locked"
			selections = []
			player.staged_submission.clear()
			player.has_staged_submission = true
			break
	var evaluation := SubmissionEvaluator.evaluate(
		player.hand,
		selections,
		state.active_context,
		state.config.normal_definitions,
		state.config.context_definitions,
		player.factor_modifiers,
		state.ability_deck.active_fields()
	)
	if not evaluation.is_valid:
		if not default_invalid_to_pass:
			return evaluation.error_code
		player.staged_submission.clear()
		player.has_staged_submission = true
		evaluation = SubmissionEvaluator.evaluate(
			player.hand,
			[],
			state.active_context,
			state.config.normal_definitions,
			state.config.context_definitions,
			player.factor_modifiers,
			state.ability_deck.active_fields()
		)
	player.submitted_cards.assign(evaluation.submitted_cards)
	player.submitted_faces.assign(evaluation.selected_faces)
	player.submitted_card_views.assign(evaluation.resolved_cards)
	player.locked_normal = evaluation.normal_result
	player.locked_context = evaluation.context_result
	player.provisional_score = evaluation.score_breakdown
	player.hand_locked = true
	player.ready = true
	return &""


func _calculate_player_score(player: PlayerState) -> ScoringTypes.ScoreBreakdown:
	var field_components: Array[ScoringTypes.MultiplierComponent] = []
	if player.locked_context != null:
		field_components = FieldEffectResolver.score_components(
			player.submitted_faces,
			player.locked_context.counts,
			state.ability_deck.active_fields()
		)
	return ScoreCalculator.calculate(
		player.submitted_faces,
		player.locked_normal,
		player.locked_context,
		player.factor_modifiers,
		field_components
	)


func _finish_hand_play(now_msec: int) -> Array[DomainEvent]:
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if not player.active or player.pending:
			continue
		player.pending_manipulation.clear()
		if not player.hand_locked:
			if player.deadline_submission is Array:
				player.staged_submission.assign(player.deadline_submission)
				player.has_staged_submission = true
			_lock_player_hand(player_id, true)
		player.deadline_submission = null
	return _resolve_hand_play(now_msec)


func _resolve_hand_play(now_msec: int) -> Array[DomainEvent]:
	var events: Array[DomainEvent] = []
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if not player.active or player.pending:
			continue
		player.submission_revealed = true
		var manipulation_ids: Array = []
		for ability_id in player.completed_manipulation_ids:
			manipulation_ids.append(str(ability_id))
		events.append(DomainEvent.new(EventKinds.HAND_REVEALED, {
			"player_id": str(player_id), "cards": player.submitted_card_views.duplicate(true),
			"normal_category": str(player.locked_normal.category_id),
			"context_category": str(player.locked_context.category_id),
			"base_value": player.provisional_score.base_value,
			"provisional_score": player.provisional_score.final_score,
			"manipulation_ability_ids": manipulation_ids,
		}, &"public"))
		events.append(DomainEvent.new(EventKinds.HAND_RESULT_PRIVATE, {
			"player_id": str(player_id), "staged_submission": player.staged_submission.duplicate(true),
			"raw_numerator": player.provisional_score.raw_score.numerator,
			"raw_denominator": player.provisional_score.raw_score.denominator,
		}, &"player", player_id))
	_update_main_readiness()
	state.phase = GameTypes.Phase.MAIN_2
	state.phase_started_msec = now_msec
	state.phase_deadline_msec = _phase_deadline_after(now_msec, state.config.public_hard_limit_msec)
	state.reaction_deadline_msec = -1
	events.append(DomainEvent.new(
		EventKinds.PHASE_CHANGED, {"phase": GameTypes.Phase.MAIN_2}, &"public"
	))
	return events


func _all_hands_locked() -> bool:
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if player.active and not player.pending and not player.hand_locked:
			return false
	return true


func _hand_card(player_id: StringName, card_id: StringName) -> FullCardState:
	for card in state.players[player_id].hand:
		if card.card_id == card_id:
			return card
	return null


func _validate_public_ability_choices(
	schema: Dictionary,
	choices: Dictionary
) -> StringName:
	var steps: Variant = schema.get("steps", [])
	if not steps is Array:
		return &"invalid_choice_schema"
	if steps.is_empty():
		return &"unexpected_ability_choices" if not choices.is_empty() else &""
	var expected_keys := {}
	for raw_step in steps:
		if not raw_step is Dictionary:
			return &"invalid_choice_schema"
		var key := str(raw_step.get("key", ""))
		var kind := StringName(str(raw_step.get("kind", "")))
		var eligible: Variant = raw_step.get("eligible", [])
		var count := int(raw_step.get("count", 1))
		if key.is_empty() or not eligible is Array or count <= 0:
			return &"invalid_choice_schema"
		expected_keys[key] = true
		var selected: Variant = choices.get(key)
		if not selected is Array or selected.size() != count:
			return &"incomplete_ability_choices"
		var unique: Array = []
		for value in selected:
			if kind == &"player":
				if not _is_identifier(value): return &"invalid_ability_choice"
				var selected_player = state.players.get(StringName(str(value)))
				if selected_player == null or not selected_player.active or selected_player.pending or selected_player.spectator:
					return &"invalid_ability_choice"
			elif value not in eligible:
				return &"invalid_ability_choice"
			if value in unique:
				return &"duplicate_ability_choice"
			unique.append(value)
	for key in choices:
		if not expected_keys.has(str(key)):
			return &"unexpected_ability_choice"
	return &""


func _held_ability(player_id: StringName, copy_id: StringName) -> AbilityState:
	for ability in state.players[player_id].ability_hand:
		if ability.copy_id == copy_id:
			return ability
	return null


func _remove_held_ability(player_id: StringName, ability: AbilityState) -> void:
	state.players[player_id].ability_hand.erase(ability)


func _validate_partial_request(request: Dictionary, needed_halves: int) -> StringName:
	var total := 0
	for context in request:
		if not context is int or context < GameTypes.Context.RISE or context > GameTypes.Context.FALL:
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


func _update_main_readiness(reset_manual_ready: bool = true) -> void:
	for player_id in state.seat_order:
		var player: PlayerState = state.players[player_id]
		# Total tray size is public. Card timing is private even if nothing can be played.
		if player.active and not player.pending and player.ability_hand.is_empty():
			player.ready = true
		elif reset_manual_ready:
			player.ready = false


func _can_close_main_phase(now_msec: int) -> bool:
	if not _all_active_ready() or now_msec < state.reaction_deadline_msec:
		return false
	if state.phase != GameTypes.Phase.MAIN_2:
		return true
	var revealed_seats := 0
	for player_id in state.seat_order:
		var player: PlayerState = state.players[player_id]
		if not player.active or player.pending:
			continue
		if not player.ability_hand.is_empty():
			return true
		if player.submission_revealed:
			revealed_seats += 1
	return now_msec >= state.phase_started_msec + revealed_seats * GameTypes.MAIN_2_REVIEW_MSEC_PER_PLAYER


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
			"first": _private_half(card.first), "second": _private_half(card.second),
		})
	return result


func _private_half(half: HalfCardState) -> Dictionary:
	return {
		"copy_id": str(half.copy_id), "base_context": half.base_context,
		"base_rank": half.base_rank, "base_suit": half.base_suit, "kind": half.effective_kind(),
		"effective_context": half.effective_context(), "rank": half.effective_rank(),
		"suit": half.effective_suit(),
	}

