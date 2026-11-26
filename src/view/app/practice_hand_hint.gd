extends RefCounted

const Solver := preload("res://src/core/scoring/guaranteed_hand_solver.gd")

var view: Dictionary = {}
var _key: Array = []
var _generation := 0
var _worker_generation := -1
var _thread: Thread
var _solver: GuaranteedHandSolver


func refresh(state: MatchState, player_id: StringName) -> bool:
	var player: PlayerState = state.players.get(player_id)
	var key := _inputs(state, player)
	var changed := key != _key
	if changed:
		_key = key
		_generation += 1
		view = {} if key.is_empty() else {"status": "calculating"}
		if _solver != null:
			_solver.cancel()

	if _thread != null and not _thread.is_alive():
		var plan: Dictionary = _thread.wait_to_finish()
		_thread = null
		_solver = null
		if _worker_generation == _generation:
			view = {"status": "ready", "plan": plan} if not plan.is_empty() else {"status": "unavailable"}
			changed = true

	if _thread == null and view.get("status", "") == "calculating":
		_solver = Solver.capture(state, player_id)
		_worker_generation = _generation
		_thread = Thread.new()
		if _solver == null or _thread.start(_solver.solve_best_candidate) != OK:
			_thread = null
			_solver = null
			view = {"status": "unavailable"}
			changed = true
	return changed


func close() -> void:
	if _thread != null:
		_solver.cancel()
		_thread.wait_to_finish()
	_thread = null
	_solver = null
	_key.clear()
	view.clear()


func _inputs(state: MatchState, player: PlayerState) -> Array:
	if state.phase != GameTypes.Phase.HAND_PLAY or state.frozen or state.match_complete:
		return []
	if player == null or not player.active or player.pending or player.hand_locked:
		return []
	var hand := player.hand.map(func(card: FullCardState): return [card.card_id, card.face_snapshot()])
	var abilities := player.ability_hand.map(func(ability: AbilityState): return ability.copy_id)
	var fields := state.ability_deck.active_fields().map(func(field: FieldState): return field.ability.copy_id)
	var modifiers := player.factor_modifiers.map(func(modifier: ScoringTypes.FactorModifier):
		return [modifier.source_copy_id, modifier.factor_id, modifier.category_id,
			modifier.delta.numerator, modifier.delta.denominator]
	)
	return [state.round_number, state.active_context, state.context_direction, hand, abilities, fields, modifiers,
		player.abilities_disabled, player.pending_manipulation.get("copy_id", &""),
		player.submission_locked_card_ids.duplicate()]
