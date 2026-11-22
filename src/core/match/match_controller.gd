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
const ScoreCalculator = preload("res://src/core/scoring/score_calculator.gd")
const SubmissionEvaluator = preload("res://src/core/scoring/submission_evaluator.gd")

var state: MatchState
var _accepted_command_ids: Dictionary = {}
var _start_requests: Dictionary = {}
var _effect_registry: EffectRegistry
var _end_transaction_active := false
var _queued_disconnects: Array[Dictionary] = []
var _reconnect_token_provider: Callable
var end_transaction_probe: Callable


func _init(
	match_state: MatchState,
	effects: EffectRegistry = null,
	reconnect_token_provider: Callable = Callable()
) -> void:
	state = match_state
	_effect_registry = effects if effects != null else EffectRegistry.new()
	_reconnect_token_provider = reconnect_token_provider
	_accepted_command_ids = state.accepted_command_ids
	_start_requests = state.start_requests
	for player_id in state.players:
		if not _accepted_command_ids.has(player_id):
			_accepted_command_ids[player_id] = {}
	if state.phase == GameTypes.Phase.START:
		_prepare_start_phase()


func submit(command: GameCommand, now_msec: int) -> CommandResult:
	if command != null and command.kind == CommandKinds.JOIN_ACTIVE:
		return _join_active(command)
	if command != null and command.kind == CommandKinds.JOIN_SPECTATOR:
		return _join_spectator(command)
	if command != null and command.kind == CommandKinds.RECONNECT:
		return _submit_reconnect(command, now_msec)
	if command != null and command.kind == CommandKinds.FORFEIT:
		return _forfeit_command(command, now_msec)
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

	var result: CommandResult
	if state.phase == GameTypes.Phase.START:
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
	return result


func tick(now_msec: int) -> Array[DomainEvent]:
	if state.frozen:
		return _tick_disconnects(now_msec)
	if state.match_complete and state.phase != GameTypes.Phase.END:
		return []
	if state.phase == GameTypes.Phase.START:
		_ensure_phase_clock(now_msec)
		if now_msec >= state.phase_deadline_msec:
			return _finish_start(now_msec)
	elif state.phase == GameTypes.Phase.MAIN_1:
		_ensure_phase_clock(now_msec)
		if now_msec >= state.phase_deadline_msec:
			return _finish_main_one(now_msec)
		if (
			_all_active_ready()
			and (state.reaction_deadline_msec < 0 or now_msec >= state.reaction_deadline_msec)
		):
			return _finish_main_one(now_msec)
	elif state.phase == GameTypes.Phase.HAND_PLAY:
		_ensure_phase_clock(now_msec)
		if now_msec >= state.phase_deadline_msec:
			return _finish_hand_play(now_msec)
	elif state.phase == GameTypes.Phase.MAIN_2:
		_ensure_phase_clock(now_msec)
		if now_msec >= state.phase_deadline_msec:
			return _finish_main_two(now_msec)
		if (
			_all_active_ready()
			and (state.reaction_deadline_msec < 0 or now_msec >= state.reaction_deadline_msec)
		):
			return _finish_main_two(now_msec)
	elif state.phase == GameTypes.Phase.END:
		_ensure_phase_clock(now_msec)
		if now_msec >= state.phase_deadline_msec:
			return _finish_end_discards(now_msec)
	return []


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


func _is_identifier(value: Variant) -> bool:
	return value is String or value is StringName


func _command_allowed_in_current_phase(kind: StringName) -> bool:
	match state.phase:
		GameTypes.Phase.START:
			return kind in [CommandKinds.SET_REPLENISHMENT_REQUEST, CommandKinds.SET_READY]
		GameTypes.Phase.MAIN_1, GameTypes.Phase.MAIN_2:
			return kind in [CommandKinds.SET_READY, CommandKinds.PLAY_PUBLIC_ABILITY]
		GameTypes.Phase.HAND_PLAY:
			return kind in [
				CommandKinds.STAGE_MANIPULATION, CommandKinds.CANCEL_MANIPULATION,
				CommandKinds.COMMIT_MANIPULATION, CommandKinds.STAGE_HAND,
				CommandKinds.LOCK_HAND,
			]
		GameTypes.Phase.END:
			return kind == CommandKinds.CHOOSE_ABILITY_DISCARDS
	return false


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
				player_id, state.ability_deck.starting_hand_size, state.rng
			)
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if player.active and not player.pending:
			player.replenishment_needed = max(6 - player.hand.size(), 0)
			player.ready = false
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
		state.phase_deadline_msec = now_msec + state.config.public_hard_limit_msec
	else:
		state.phase_deadline_msec = now_msec + state.config.phase_timers[state.phase]


func _finish_start(now_msec: int) -> Array[DomainEvent]:
	var events: Array[DomainEvent] = []
	var completed_requests := {}
	var replacement_counts := {}
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
	state.phase_deadline_msec = now_msec + state.config.public_hard_limit_msec
	state.reaction_deadline_msec = -1
	events.append(DomainEvent.new(
		EventKinds.PHASE_CHANGED, {"phase": GameTypes.Phase.MAIN_1}, &"public"
	))
	_start_requests.clear()
	return events


func _submit_main_one(command: GameCommand, now_msec: int) -> CommandResult:
	match command.kind:
		CommandKinds.SET_READY:
			if not command.payload.has("ready") or not command.payload.ready is bool:
				return CommandResult.new(false, &"malformed_command")
			_ensure_phase_clock(now_msec)
			if now_msec > state.phase_deadline_msec:
				return CommandResult.new(false, &"phase_deadline_passed")
			state.players[command.player_id].ready = command.payload.ready
			var ready_events: Array[DomainEvent] = []
			if (
				_all_active_ready()
				and (state.reaction_deadline_msec < 0 or now_msec >= state.reaction_deadline_msec)
			):
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
			if now_msec > state.phase_deadline_msec:
				return CommandResult.new(false, &"phase_deadline_passed")
			state.players[command.player_id].ready = command.payload.ready
			var ready_events: Array[DomainEvent] = []
			if (
				_all_active_ready()
				and (state.reaction_deadline_msec < 0 or now_msec >= state.reaction_deadline_msec)
			):
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
	if now_msec > state.phase_deadline_msec:
		return CommandResult.new(false, &"phase_deadline_passed")

	var events: Array[DomainEvent] = [DomainEvent.new(
		EventKinds.PUBLIC_ABILITY_PLAYED,
		{"ability_id": str(ability.definition.id), "source_player_id": str(command.player_id),
		"target_player_id": str(target_player_id)}, &"public"
	)]
	_remove_held_ability(command.player_id, ability)
	if ability.definition.timing == AbilityDefinition.Timing.FIELD:
		var field_result := state.ability_deck.play_field(ability, command.player_id)
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
			target.provisional_score = ScoreCalculator.calculate(
				target.submitted_faces, target.locked_normal, target.locked_context,
				target.factor_modifiers
			)
			events.append(DomainEvent.new(
				EventKinds.PROVISIONAL_SCORE_UPDATED,
				{"player_id": str(target_player_id),
				"provisional_score": target.provisional_score.final_score}, &"public"
			))
	for player_id in state.seat_order:
		if state.players[player_id].active:
			state.players[player_id].ready = false
	state.reaction_deadline_msec = min(
		now_msec + state.config.reaction_window_msec, state.phase_deadline_msec
	)
	if now_msec >= state.phase_deadline_msec:
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
	state.phase_deadline_msec = now_msec + state.config.phase_timers[GameTypes.Phase.HAND_PLAY]
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
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if not player.active or player.pending:
			continue
		player.provisional_score = ScoreCalculator.calculate(
			player.submitted_faces, player.locked_normal, player.locked_context,
			player.factor_modifiers
		)
		player.finalized_score = player.provisional_score.final_score
		final_scores[player_id] = player.finalized_score
	state.last_round_winner_id = state.resolve_round(final_scores)
	events.append(DomainEvent.new(EventKinds.ROUND_FINALIZED, {
		"scores": _string_key_scores(final_scores),
		"winner_id": str(state.last_round_winner_id),
	}, &"public"))
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
		player.submitted_card_views.clear()
		player.submission_revealed = false
		player.factor_modifiers.clear()
		player.pending_manipulation.clear()
		player.staged_submission.clear()
		player.has_staged_submission = false
		player.hand_locked = false
		player.completed_manipulation_ids.clear()
		player.ready = false
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

	if _all_end_discards_complete():
		events.append_array(_complete_end(now_msec))
	else:
		state.phase = GameTypes.Phase.END
		state.phase_started_msec = now_msec
		state.phase_deadline_msec = now_msec + state.config.phase_timers[GameTypes.Phase.END]
		state.reaction_deadline_msec = -1
	return events


func _submit_end(command: GameCommand, now_msec: int) -> CommandResult:
	if command.kind != CommandKinds.CHOOSE_ABILITY_DISCARDS:
		return CommandResult.new(false, &"command_not_allowed_in_phase")
	if not command.payload.has("copy_ids") or not command.payload.copy_ids is Array:
		return CommandResult.new(false, &"malformed_command")
	var player = state.players[command.player_id]
	var excess: int = max(player.ability_hand.size() - state.ability_deck.end_hand_limit, 0)
	if command.payload.copy_ids.size() != excess:
		return CommandResult.new(false, &"incorrect_discard_count")
	var cards: Array[AbilityState] = []
	var seen := {}
	for raw_id in command.payload.copy_ids:
		if not _is_identifier(raw_id):
			return CommandResult.new(false, &"malformed_command")
		var copy_id := StringName(raw_id)
		if seen.has(copy_id):
			return CommandResult.new(false, &"duplicate_ability_discard")
		seen[copy_id] = true
		var ability := _held_ability(command.player_id, copy_id)
		if ability == null:
			return CommandResult.new(false, &"ability_not_in_hand")
		cards.append(ability)
	_ensure_phase_clock(now_msec)
	var events := _discard_abilities(command.player_id, cards)
	player.end_discard_complete = true
	if _all_end_discards_complete():
		events.append_array(_complete_end(now_msec))
	return CommandResult.new(true, &"", events)


func _finish_end_discards(now_msec: int) -> Array[DomainEvent]:
	var events: Array[DomainEvent] = []
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if not player.active or player.end_discard_complete:
			continue
		var excess: int = max(player.ability_hand.size() - state.ability_deck.end_hand_limit, 0)
		var shuffled: Array = state.rng.shuffle(player.ability_hand)
		var cards: Array[AbilityState] = []
		for index in range(excess):
			cards.append(shuffled[index])
		events.append_array(_discard_abilities(player_id, cards))
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
	if state.match_complete:
		state.phase = GameTypes.Phase.COMPLETE
		state.config.match_started = false
		return [DomainEvent.new(EventKinds.MATCH_ENDED, {
			"winner_id": str(state.winner_id),
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
	if not state.players.has(player_id):
		return []
	var player = state.players[player_id]
	if player.spectator:
		state.config.unregister_spectator(player_id)
	elif player.pending:
		state.seat_order.erase(player_id)
		state.config.unregister_active_participant(player_id)
	else:
		return []
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


func reset_for_rematch(new_seed: int) -> void:
	assert(state.match_complete, "only a completed match can reset for rematch")
	state.config.match_started = false
	var fresh := MatchState.create(state.config, new_seed)
	fresh.config.match_started = false
	fresh.phase = GameTypes.Phase.SETUP
	state = fresh
	_accepted_command_ids = state.accepted_command_ids
	_start_requests = state.start_requests
	for player_id in state.players:
		if not _accepted_command_ids.has(player_id):
			_accepted_command_ids[player_id] = {}


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
	var events := _forfeit_player(command.player_id)
	if command.player_id == state.host_player_id:
		state.match_complete = true
		state.winner_id = &""
		state.phase = GameTypes.Phase.COMPLETE
		state.config.match_started = false
		events.append(DomainEvent.new(
			EventKinds.MATCH_ENDED, {"winner_id": "", "reason": "host_forfeit"}, &"public"
		))
	_accepted_command_ids[command.player_id][command.command_id] = true
	_resume_if_resolved(now_msec)
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
	return events


func _forfeit_player(player_id: StringName) -> Array[DomainEvent]:
	var player = state.players[player_id]
	var events: Array[DomainEvent] = []
	for card in player.hand.duplicate():
		card.leave_hand()
		state.piles[card.first.base_context].discard(card.first)
		state.piles[card.second.base_context].discard(card.second)
	player.hand.clear()
	var discarded: Array[AbilityState] = []
	discarded.assign(player.ability_hand.duplicate())
	events.append_array(_discard_abilities(player_id, discarded))
	player.pending_manipulation.clear()
	player.staged_submission.clear()
	player.submitted_cards.clear()
	player.submitted_faces.clear()
	player.submitted_card_views.clear()
	player.submission_revealed = false
	player.disconnect_deadline_msec = -1
	player.reconnect_token = ""
	state.remove_active_player(player_id)
	state.seat_order.erase(player_id)
	state.config.unregister_active_participant(player_id)
	if state.match_complete:
		state.config.match_started = false
	events.append(DomainEvent.new(
		&"player_forfeited", {"player_id": str(player_id)}, &"public"
	))
	return events


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
	if state.players[command.player_id].hand_locked:
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
	return CommandResult.new(true)


func _stage_hand(command: GameCommand, now_msec: int) -> CommandResult:
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
	var evaluation := SubmissionEvaluator.evaluate(
		player.hand,
		candidate,
		state.active_context,
		state.config.normal_definitions,
		state.config.context_definitions,
		player.factor_modifiers
	)
	if not evaluation.is_valid:
		return CommandResult.new(false, evaluation.error_code)
	_ensure_phase_clock(now_msec)
	player.staged_submission.clear()
	for selection: Dictionary in candidate:
		var canonical_choices: Array = []
		for choice: Dictionary in selection.joker_choices:
			canonical_choices.append({
				"half_index": choice.half_index,
				"context": choice.context,
				"suit": choice.suit,
			})
		canonical_choices.sort_custom(func(left: Dictionary, right: Dictionary):
			return left.half_index < right.half_index
		)
		player.staged_submission.append({
			"card_id": StringName(selection.card_id), "half_index": selection.half_index,
			"joker_choices": canonical_choices,
		})
	player.has_staged_submission = true
	return CommandResult.new(true)


func _lock_player_hand(
	player_id: StringName,
	default_invalid_to_pass: bool
) -> StringName:
	var player = state.players[player_id]
	var selections: Array = player.staged_submission if player.has_staged_submission else []
	var evaluation := SubmissionEvaluator.evaluate(
		player.hand,
		selections,
		state.active_context,
		state.config.normal_definitions,
		state.config.context_definitions,
		player.factor_modifiers
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
			player.factor_modifiers
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


func _finish_hand_play(now_msec: int) -> Array[DomainEvent]:
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if not player.active or player.pending:
			continue
		player.pending_manipulation.clear()
		if not player.hand_locked:
			_lock_player_hand(player_id, true)
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
		player.ready = false
	state.phase = GameTypes.Phase.MAIN_2
	state.phase_started_msec = now_msec
	state.phase_deadline_msec = now_msec + state.config.public_hard_limit_msec
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
		"base_rank": half.base_rank, "base_suit": half.base_suit, "kind": half.kind,
		"effective_context": half.effective_context(), "rank": half.effective_rank(),
		"suit": half.effective_suit(),
	}

