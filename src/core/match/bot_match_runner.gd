extends RefCounted

const Solver := preload("res://src/core/scoring/guaranteed_hand_solver.gd")
const DIFFICULTIES := [&"easy", &"standard", &"hard"]
const DEADLINE_BUFFER_MSEC := 150
const MAX_WAIT_AFTER_SUBMIT_MSEC := 900
const SABOTAGE_WEIGHTS := [4, 2]
const DRAW_LOOKAHEAD_ROUNDS := 3
const DISCARD_ORDER := [
	AbilityDefinition.Timing.FIELD, AbilityDefinition.Timing.HAND_SHAPE,
	AbilityDefinition.Timing.SABOTAGE, AbilityDefinition.Timing.HAND_MANIPULATION,
]

var _jobs: Dictionary = {}
var _main_one_played: Dictionary = {}
var _hand_opened: Dictionary = {}
var _main_two_plays: Dictionary = {}
var _state: MatchState
var _round := -1
var _command_number := 0
var _rng := RandomSource.new(Time.get_ticks_usec())
var _events: Array[DomainEvent] = []
var _changed := false
var _human_wait_until_msec := -1


func poll(controller: MatchController, difficulties: Dictionary, now: int) -> Dictionary:
	var state := controller.state
	if state != _state or state.round_number != _round:
		close()
		_state = state
		_round = state.round_number
	_events = []
	_changed = false
	var phase := state.phase
	if phase != GameTypes.Phase.HAND_PLAY:
		_cancel_jobs()
		_human_wait_until_msec = -1
	elif not _all_humans_locked(state, difficulties):
		_human_wait_until_msec = -1
	elif _human_wait_until_msec < 0:
		_human_wait_until_msec = now + MAX_WAIT_AFTER_SUBMIT_MSEC
	if state.config.match_started and not state.frozen and not state.match_complete:
		for id: StringName in difficulties:
			var player: PlayerState = state.players.get(id)
			if player != null and player.active and not player.pending:
				_play(controller, player, int(difficulties[id]), now)
			if state.phase != phase:
				break
	return {"changed": _changed, "events": _events}


func close() -> void:
	_cancel_jobs()
	_main_one_played.clear()
	_hand_opened.clear()
	_main_two_plays.clear()
	_state = null
	_human_wait_until_msec = -1


func _all_humans_locked(state: MatchState, difficulties: Dictionary) -> bool:
	for id in state.seat_order:
		var player: PlayerState = state.players[id]
		if not difficulties.has(id) and player.active and not player.pending and not player.hand_locked:
			return false
	return true


func _play(controller: MatchController, player: PlayerState, difficulty: int, now: int) -> void:
	var id := player.player_id
	var phase := controller.state.phase
	match phase:
		GameTypes.Phase.START:
			if not player.ready:
				var request := _draw_request(controller.state, player.replenishment_needed * 2)
				if not request.is_empty():
					_submit(controller, id, CommandKinds.SET_REPLENISHMENT_REQUEST, {"request": request}, now)
				if controller.state.phase == phase:
					_submit(controller, id, CommandKinds.SET_READY, {"ready": true}, now)
		GameTypes.Phase.MAIN_1:
			_play_main_one(controller, player, now)
			if controller.state.phase == phase and not player.ready:
				_submit(controller, id, CommandKinds.SET_READY, {"ready": true}, now)
		GameTypes.Phase.HAND_PLAY:
			if not player.hand_locked:
				_try_opening_manipulation(controller, player, now)
				_play_hand(controller, player, difficulty, now)
		GameTypes.Phase.MAIN_2:
			_play_main_two(controller, player, now)
			if controller.state.phase == phase and not player.ready:
				_submit(controller, id, CommandKinds.SET_READY, {"ready": true}, now)
		GameTypes.Phase.END:
			if not player.end_discard_complete:
				var ids := _discard_ids(player, controller.state.ability_deck.end_hand_limit)
				_submit(controller, id, CommandKinds.CHOOSE_ABILITY_DISCARDS, {"copy_ids": ids}, now)


func _draw_request(state: MatchState, remaining: int) -> Dictionary:
	var request := {}
	if remaining <= 0:
		return request
	var active_fields := state.ability_deck.active_fields()
	var counts := [0, 0, 0]
	var first_seen := [DRAW_LOOKAHEAD_ROUNDS, DRAW_LOOKAHEAD_ROUNDS, DRAW_LOOKAHEAD_ROUNDS]
	var clock_order: Array[int] = []
	# Start has already advanced the clock to the first hand these cards can be played in.
	for offset in DRAW_LOOKAHEAD_ROUNDS:
		var context := posmod(state.active_context + offset * state.context_direction, 3)
		clock_order.append(context)
		var fields := active_fields.filter(func(field: FieldState) -> bool:
			return field.is_persistent() or field.remaining_rounds > offset
		)
		for active in FieldEffectResolver.active_contexts(context, fields):
			counts[active] += 1
			first_seen[active] = mini(first_seen[active], offset)
	var priority := clock_order.duplicate()
	priority.sort_custom(func(a: int, b: int) -> bool:
		if counts[a] != counts[b]:
			return counts[a] > counts[b]
		if first_seen[a] != first_seen[b]:
			return first_seen[a] < first_seen[b]
		return clock_order.find(a) < clock_order.find(b)
	)
	for context in priority:
		var pile: ContextPile = state.piles[context]
		var quantity := mini(remaining, mini(CardFactory.CONTEXT_DRAW_CAP, pile.draw_count() + pile.used_count()))
		if quantity > 0:
			request[context] = quantity
			remaining -= quantity
		if remaining == 0:
			break
	return request


func _play_main_one(controller: MatchController, player: PlayerState, now: int) -> void:
	var id := player.player_id
	if _main_one_played.has(id) or player.abilities_disabled:
		return
	_main_one_played[id] = true
	for ability in player.ability_hand.duplicate():
		if controller.state.phase != GameTypes.Phase.MAIN_1:
			return
		match ability.definition.timing:
			AbilityDefinition.Timing.SABOTAGE:
				_play_sabotage(controller, player, ability, now)
			AbilityDefinition.Timing.FIELD:
				if _rng.pick_index(4) < 3:
					_play_public_ability(controller, id, ability.copy_id, now)


func _play_sabotage(controller: MatchController, player: PlayerState, ability: AbilityState, now: int) -> void:
	var standings := _ranked_players(controller.state)
	var tickets: Array[StringName] = []
	for rank in mini(SABOTAGE_WEIGHTS.size(), standings.size()):
		var target := standings[rank].player_id
		if target != player.player_id:
			for _ticket in SABOTAGE_WEIGHTS[rank]:
				tickets.append(target)
	while not tickets.is_empty():
		var target := tickets[_rng.pick_index(tickets.size())]
		if _play_public_ability(controller, player.player_id, ability.copy_id, now, target):
			return
		# The controller also checks card-specific restrictions, such as an existing ability lock.
		tickets = tickets.filter(func(candidate: StringName) -> bool: return candidate != target)


func _play_main_two(controller: MatchController, player: PlayerState, now: int) -> void:
	var id := player.player_id
	var plays: Array = _main_two_plays.get(id, [])
	_main_two_plays.erase(id)
	if player.abilities_disabled:
		return
	for play: Dictionary in plays:
		if controller.state.phase != GameTypes.Phase.MAIN_2:
			return
		_submit(controller, id, CommandKinds.PLAY_PUBLIC_ABILITY, play, now)
	var standings := _ranked_players(controller.state)
	for ability: AbilityState in player.ability_hand.duplicate():
		if controller.state.phase != GameTypes.Phase.MAIN_2:
			return
		if ability.definition.timing != AbilityDefinition.Timing.HAND_SHAPE or &"nerf" not in ability.definition.tags:
			continue
		var effect := ability.definition.effect_parameters
		var modifier := ScoringTypes.FactorModifier.new(
			effect.factor_id, effect.category_id, Rational.new(effect.numerator, effect.denominator),
			ability.copy_id, ability.definition.id
		)
		for opponent in standings:
			if opponent.player_id == id or not opponent.submission_revealed or opponent.provisional_score == null:
				continue
			var before: ScoringTypes.ScoreBreakdown = opponent.provisional_score
			var modifiers := opponent.factor_modifiers.duplicate()
			modifiers.append(modifier)
			var after := ScoreCalculator.calculate(
				opponent.submitted_faces, opponent.locked_normal, opponent.locked_context,
				modifiers, before.field_components
			)
			if after.final_score < before.final_score and _play_public_ability(
				controller, id, ability.copy_id, now, opponent.player_id
			):
				break


func _ranked_players(state: MatchState) -> Array[PlayerState]:
	var standings: Array[PlayerState] = []
	for id in state.seat_order:
		var player: PlayerState = state.players[id]
		if player.active and player.connected and not player.pending and not player.spectator:
			standings.append(player)
	var round_wins := state.config.victory_mode == GameTypes.VictoryMode.ROUND_WIN_RACE
	standings.sort_custom(func(a: PlayerState, b: PlayerState) -> bool:
		var a_score := a.round_wins if round_wins else a.match_score
		var b_score := b.round_wins if round_wins else b.match_score
		return a.seat_index < b.seat_index if a_score == b_score else a_score > b_score
	)
	return standings


func _discard_ids(player: PlayerState, limit: int) -> Array:
	var ids := []
	var excess := player.ability_hand.size() - limit
	for timing in DISCARD_ORDER:
		if timing == AbilityDefinition.Timing.HAND_MANIPULATION:
			for ability in player.ability_hand:
				if ids.size() >= excess:
					return ids
				if ManipulationResolver.uses_randomness(ability.definition):
					ids.append(str(ability.copy_id))
		for ability in player.ability_hand:
			if ids.size() >= excess:
				return ids
			if ability.definition.timing == timing and not ManipulationResolver.uses_randomness(ability.definition):
				ids.append(str(ability.copy_id))
	return ids


func _try_opening_manipulation(controller: MatchController, player: PlayerState, now: int) -> void:
	var id := player.player_id
	if _hand_opened.has(id):
		return
	_hand_opened[id] = true
	if player.abilities_disabled or not player.pending_manipulation.is_empty():
		return
	var targets := player.hand.filter(func(card: FullCardState) -> bool:
		return card.card_id not in player.submission_locked_card_ids and (
			not card.first.is_joker() or not card.second.is_joker()
		)
	)
	var playable: Array[Dictionary] = []
	for ability in player.ability_hand:
		if not ManipulationResolver.uses_randomness(ability.definition):
			continue
		if not ability.definition.allows_phase(GameTypes.Phase.HAND_PLAY):
			continue
		var choices := Solver.valid_manipulation_choices(ability.definition, targets)
		if not choices.is_empty():
			playable.append({"copy_id": ability.copy_id, "choices": choices})
	if playable.is_empty() or _rng.pick_index(2) != 0:
		return
	var play: Dictionary = playable[_rng.pick_index(playable.size())]
	var choices: Array = play.choices
	if _submit(controller, id, CommandKinds.STAGE_MANIPULATION, {"copy_id": play.copy_id}, now):
		if not _submit(controller, id, CommandKinds.COMMIT_MANIPULATION,
			{"choices": choices[_rng.pick_index(choices.size())]}, now):
			_submit(controller, id, CommandKinds.CANCEL_MANIPULATION, {}, now)


func _play_public_ability(
	controller: MatchController, id: StringName, copy_id: StringName, now: int, target := &""
) -> bool:
	var choices := {} if target.is_empty() else {"target_player_id": [target]}
	return _submit(controller, id, CommandKinds.PLAY_PUBLIC_ABILITY, {
		"copy_id": copy_id, "target_player_id": target, "choices": choices,
	}, now)


func _play_hand(controller: MatchController, player: PlayerState, difficulty: int, now: int) -> void:
	var id := player.player_id
	var state := controller.state
	if not player.pending_manipulation.is_empty():
		_submit(controller, id, CommandKinds.CANCEL_MANIPULATION, {}, now)
	var deadline := state.phase_deadline_msec
	var phase_deadline_close := deadline >= 0 and deadline - now <= DEADLINE_BUFFER_MSEC
	var human_wait_expired := _human_wait_until_msec >= 0 and now >= _human_wait_until_msec
	var stop_search := phase_deadline_close or human_wait_expired
	if not _jobs.has(id) and not stop_search:
		# Capture only on the authority thread. The worker receives its own hand and scoring inputs.
		var solver := Solver.capture(state, id)
		var thread := Thread.new()
		if solver != null and thread.start(Callable(solver, "solve_candidates")) == OK:
			_jobs[id] = {"solver": solver, "thread": thread}
			return
	var plan := {}
	if _jobs.has(id):
		var job: Dictionary = _jobs[id]
		var thread: Thread = job.thread
		if thread.is_alive():
			if not stop_search:
				return
			job.solver.cancel(true)
			# Let every bot wind down together while the authority keeps polling.
			if not phase_deadline_close:
				return
		var candidates: Array = thread.wait_to_finish()
		_jobs.erase(id)
		plan = Solver.pick_candidate(candidates, DIFFICULTIES[difficulty], _rng)
	_submit_hand_plan(controller, player, plan, now)


func _submit_hand_plan(controller: MatchController, player: PlayerState, plan: Dictionary, now: int) -> void:
	var id := player.player_id
	if not plan.is_empty() and _commit_hand_plan(controller, id, plan, now):
		_main_two_plays[id] = plan.main_2
		return
	var fallback := _fallback_submission(controller.state, player)
	_submit(controller, id, CommandKinds.STAGE_HAND, {"cards": fallback}, now)
	_submit(controller, id, CommandKinds.LOCK_HAND, {}, now)


func _commit_hand_plan(controller: MatchController, id: StringName, plan: Dictionary, now: int) -> bool:
	for play: Dictionary in plan.hand_play:
		if not _submit(controller, id, CommandKinds.STAGE_MANIPULATION, {"copy_id": play.copy_id}, now):
			return false
		if not _submit(controller, id, CommandKinds.COMMIT_MANIPULATION, {"choices": play.choices}, now):
			_submit(controller, id, CommandKinds.CANCEL_MANIPULATION, {}, now)
			return false
	return _submit(controller, id, CommandKinds.STAGE_HAND, {"cards": plan.submission}, now) and (
		_submit(controller, id, CommandKinds.LOCK_HAND, {}, now)
	)


func _fallback_submission(state: MatchState, player: PlayerState) -> Array:
	var cards := []
	var contexts := FieldEffectResolver.active_contexts(state.active_context, state.ability_deck.active_fields())
	for card in player.hand:
		if card.card_id in player.submission_locked_card_ids:
			continue
		var best := -1
		var rank := -1
		for index in card.eligible_half_indexes_for_contexts(contexts):
			var half := card.half_at(index)
			var base := 0 if half.is_joker() else half.effective_rank()
			if base > rank:
				best = index
				rank = base
		if best < 0:
			continue
		var joker_choices := []
		for index in 2:
			if card.half_at(index).is_joker():
				joker_choices.append({"half_index": index, "context": state.active_context, "suit": 0, "rank": 0})
		cards.append({"card_id": card.card_id, "half_index": best, "joker_choices": joker_choices})
		if cards.size() == SubmissionEvaluator.MAX_SUBMITTED_CARDS:
			break
	return cards


func _submit(controller: MatchController, id: StringName, kind: StringName, payload: Dictionary, now: int) -> bool:
	_command_number += 1
	var command := GameCommand.new(StringName("bot-move-%d" % _command_number), id, kind, payload)
	var result := controller.submit(command, now)
	if result.accepted:
		_changed = true
		_events.append_array(result.events)
	return result.accepted


func _cancel_jobs() -> void:
	for job: Dictionary in _jobs.values():
		job.solver.cancel()
	for job: Dictionary in _jobs.values():
		var thread: Thread = job.thread
		thread.wait_to_finish()
	_jobs.clear()
