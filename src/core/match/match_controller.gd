class_name MatchController
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const CardFactory = preload("res://src/core/cards/card_factory.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const AbilityState = preload("res://src/core/abilities/ability_state.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const EffectRegistry = preload("res://src/core/abilities/effect_registry.gd")
const EventKinds = preload("res://src/core/events/event_kinds.gd")
const DomainEvent = preload("res://src/core/events/domain_event.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const CommandResult = preload("res://src/core/commands/command_result.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const Rational = preload("res://src/core/common/rational.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")
const NormalHandEvaluator = preload("res://src/core/scoring/normal_hand_evaluator.gd")
const ContextHandEvaluator = preload("res://src/core/scoring/context_hand_evaluator.gd")
const ScoreCalculator = preload("res://src/core/scoring/score_calculator.gd")

var state: MatchState
var _accepted_command_ids: Dictionary = {}
var _start_requests: Dictionary = {}
var _effect_registry: EffectRegistry


func _init(match_state: MatchState, effects: EffectRegistry = null) -> void:
	state = match_state
	_effect_registry = effects if effects != null else EffectRegistry.new()
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
	elif state.phase == GameTypes.Phase.MAIN_1:
		result = _submit_main_one(command, now_msec)
	elif state.phase == GameTypes.Phase.HAND_PLAY:
		result = _submit_hand_play(command, now_msec)
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
	state.reaction_deadline_msec = -1


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


func _play_public_ability(command: GameCommand, now_msec: int) -> CommandResult:
	if not command.payload.has("copy_id"):
		return CommandResult.new(false, &"malformed_command")
	var copy_id := StringName(command.payload.copy_id)
	var ability := _held_ability(command.player_id, copy_id)
	if ability == null:
		return CommandResult.new(false, &"ability_not_in_hand")
	if not ability.definition.allows_phase(state.phase):
		return CommandResult.new(false, &"ability_timing_not_allowed")
	if ability.definition.timing == AbilityDefinition.Timing.HAND_MANIPULATION:
		return CommandResult.new(false, &"ability_timing_not_allowed")
	var target_player_id := StringName(command.payload.get("target_player_id", &""))
	var effect_payload: Dictionary = command.payload.get("effect", {})
	var effect_context := {
		"state": state, "source_player_id": command.player_id,
		"target_player_id": target_player_id, "ability": ability,
		"effect": effect_payload,
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
	for player_id in state.seat_order:
		if state.players[player_id].active:
			state.players[player_id].ready = false
	state.reaction_deadline_msec = min(
		now_msec + state.config.reaction_window_msec, state.phase_deadline_msec
	)
	if now_msec >= state.phase_deadline_msec:
		events.append_array(_finish_main_one(now_msec))
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


func _submit_hand_play(command: GameCommand, now_msec: int) -> CommandResult:
	match command.kind:
		CommandKinds.STAGE_MANIPULATION:
			if not command.payload.has("copy_id"):
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
			_ensure_phase_clock(now_msec)
			_lock_player_hand(command.player_id)
			var lock_events: Array[DomainEvent] = []
			if _all_hands_locked():
				lock_events = _resolve_hand_play(now_msec)
			return CommandResult.new(true, &"", lock_events)
	return CommandResult.new(false, &"command_not_allowed_in_phase")


func _commit_manipulation(command: GameCommand, now_msec: int) -> CommandResult:
	var player = state.players[command.player_id]
	if player.pending_manipulation.is_empty():
		return CommandResult.new(false, &"no_pending_manipulation")
	for key in ["card_id", "half_index", "context", "rank", "suit"]:
		if not command.payload.has(key):
			return CommandResult.new(false, &"malformed_command")
	if not command.payload.half_index is int or command.payload.half_index < 0 or command.payload.half_index > 1:
		return CommandResult.new(false, &"invalid_half_index")
	if not HalfCardState.is_valid_base(command.payload.context, command.payload.rank, command.payload.suit):
		return CommandResult.new(false, &"invalid_effective_values")
	var card := _hand_card(command.player_id, StringName(command.payload.card_id))
	if card == null:
		return CommandResult.new(false, &"card_not_in_hand")
	var ability := _held_ability(command.player_id, player.pending_manipulation.copy_id)
	if ability == null:
		return CommandResult.new(false, &"ability_not_in_hand")
	_ensure_phase_clock(now_msec)
	var half = card.first if command.payload.half_index == 0 else card.second
	half.apply_overrides(command.payload.context, command.payload.rank, command.payload.suit)
	_remove_held_ability(command.player_id, ability)
	state.ability_deck.discard(ability)
	player.completed_manipulation_ids.append(ability.definition.id)
	player.pending_manipulation.clear()
	return CommandResult.new(true)


func _stage_hand(command: GameCommand, now_msec: int) -> CommandResult:
	if not command.payload.has("cards") or not command.payload.cards is Array:
		return CommandResult.new(false, &"malformed_command")
	var selections: Array = command.payload.cards
	if selections.size() > 6:
		return CommandResult.new(false, &"submission_size_out_of_range")
	var seen := {}
	for raw_selection in selections:
		if not raw_selection is Dictionary or not raw_selection.has("card_id"):
			return CommandResult.new(false, &"malformed_command")
		if not raw_selection.has("half_index"):
			return CommandResult.new(false, &"half_choice_required")
		if not raw_selection.half_index is int or raw_selection.half_index < 0 or raw_selection.half_index > 1:
			return CommandResult.new(false, &"invalid_half_index")
		var card_id := StringName(raw_selection.card_id)
		if seen.has(card_id):
			return CommandResult.new(false, &"duplicate_submitted_card")
		seen[card_id] = true
		var card := _hand_card(command.player_id, card_id)
		if card == null:
			return CommandResult.new(false, &"card_not_in_hand")
		if card.eligible_half_indexes(state.active_context).is_empty():
			return CommandResult.new(false, &"card_not_eligible")
		var half = card.first if raw_selection.half_index == 0 else card.second
		if half.effective_context() != state.active_context:
			return CommandResult.new(false, &"selected_half_not_active")
	_ensure_phase_clock(now_msec)
	var player = state.players[command.player_id]
	player.staged_submission.clear()
	for selection: Dictionary in selections:
		player.staged_submission.append({
			"card_id": StringName(selection.card_id), "half_index": selection.half_index,
		})
	player.has_staged_submission = true
	return CommandResult.new(true)


func _lock_player_hand(player_id: StringName) -> void:
	var player = state.players[player_id]
	player.submitted_cards.clear()
	player.submitted_faces.clear()
	if player.has_staged_submission:
		for selection in player.staged_submission:
			var card: FullCardState = _hand_card(player_id, selection.card_id)
			player.submitted_cards.append(card)
			var half = card.first if selection.half_index == 0 else card.second
			player.submitted_faces.append(ScoringTypes.SelectedCardFace.new(
				card.card_id, selection.half_index, half.effective_rank(), half.effective_suit()
			))
	player.hand_locked = true
	player.ready = true


func _finish_hand_play(now_msec: int) -> Array[DomainEvent]:
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if not player.active or player.pending:
			continue
		player.pending_manipulation.clear()
		if not player.hand_locked:
			_lock_player_hand(player_id)
	return _resolve_hand_play(now_msec)


func _resolve_hand_play(now_msec: int) -> Array[DomainEvent]:
	var events: Array[DomainEvent] = []
	for player_id in state.seat_order:
		var player = state.players[player_id]
		if not player.active or player.pending:
			continue
		player.locked_normal = NormalHandEvaluator.evaluate(
			player.submitted_faces, state.config.normal_definitions
		)
		player.locked_context = ContextHandEvaluator.evaluate(
			player.submitted_cards, state.config.context_definitions
		)
		player.provisional_score = ScoreCalculator.calculate(
			player.submitted_faces, player.locked_normal, player.locked_context,
			player.score_modifiers
		)
		var manipulation_ids: Array = []
		for ability_id in player.completed_manipulation_ids:
			manipulation_ids.append(str(ability_id))
		var revealed_cards: Array = []
		for face in player.submitted_faces:
			revealed_cards.append({
				"card_id": str(face.card_id), "half_index": face.half_index,
				"rank": face.rank, "suit": face.suit,
			})
		events.append(DomainEvent.new(EventKinds.HAND_REVEALED, {
			"player_id": str(player_id), "cards": revealed_cards,
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
