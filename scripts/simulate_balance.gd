extends SceneTree

const ScoringReference := preload("res://src/view/app/scoring_reference.gd")
const SEATS := [&"bot-1", &"bot-2", &"bot-3", &"bot-4"]
const DIFFICULTIES := {&"bot-1": 1, &"bot-2": 1, &"bot-3": 1, &"bot-4": 1}
const MAX_ROUNDS := 300


class SimulationBots extends "res://src/core/match/bot_match_runner.gd":
	var work_budget: int

	func _init(seed_value: int, budget: int) -> void:
		_rng = RandomSource.new(seed_value)
		work_budget = budget

	func _play_hand(controller: MatchController, player: PlayerState, difficulty: int, now: int) -> void:
		var solver := Solver.capture(controller.state, player.player_id)
		var plans := solver.solve_candidates(work_budget)
		var plan := Solver.pick_candidate(plans, DIFFICULTIES[difficulty], _rng)
		_submit_hand_plan(controller, player, plan, now)


var _output: FileAccess
var _rounds := 0


func _initialize() -> void:
	_simulate.call_deferred()


func _simulate() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or not args[0].is_valid_int() or not args[1].is_valid_int() or int(args[1]) <= 0:
		_fail("Expected a seed, a positive search budget, and an output file.")
		return
	var seed_value := int(args[0])
	_output = FileAccess.open(args[2], FileAccess.WRITE)
	if _output == null:
		_fail("Could not open the lobby result file.")
		return
	var config := MatchConfig.new(
		SEATS, [], GameTypes.VictoryMode.SCORE_RACE, 1000, GameTypes.InformationVisibility.PUBLIC,
		{GameTypes.Phase.START: 20000, GameTypes.Phase.MAIN_1: 30000,
		 GameTypes.Phase.HAND_PLAY: 45000, GameTypes.Phase.MAIN_2: 30000, GameTypes.Phase.END: 10000},
		2000, 30000, 30000, AbilityCatalog.build_deck(AbilityCatalog.provisional_deck_recipe()),
		ScoringReference.normal_definitions(), ContextHandCatalog.definitions(), true
	)
	var state := MatchState.create(config, seed_value)
	var controller := MatchController.new(state)
	var bots := SimulationBots.new(seed_value ^ 0x4b21d3a7, int(args[1]))
	var now := 1
	var phase_polls := 0
	controller.begin_match(now)
	while state.phase != GameTypes.Phase.COMPLETE and state.round_number <= MAX_ROUNDS:
		var previous := state.phase
		if previous == GameTypes.Phase.MAIN_2:
			controller.end_transaction_probe = _record_round.bind(state)
		bots.poll(controller, DIFFICULTIES, now)
		controller.tick(now)
		phase_polls = phase_polls + 1 if state.phase == previous else 0
		if phase_polls > 20:
			_fail("Seed %d stalled in %s on round %d." % [seed_value, GameTypes.Phase.keys()[state.phase], state.round_number])
			return
		# The offline clock clears presentation and reaction waits while retaining command and readiness checks.
		now += 12500

	bots.close()
	if state.phase != GameTypes.Phase.COMPLETE or not state.match_complete:
		_fail("Seed %d did not finish within %d rounds." % [seed_value, MAX_ROUNDS])
		return
	_output.store_line(JSON.stringify({
		"seed": seed_value, "rounds": _rounds, "winner_seat": SEATS.find(state.last_round_winner_id) + 1,
		"multipliers": _configured_multipliers(config),
	}))
	_output.close()
	quit()


func _record_round(state: MatchState) -> void:
	_rounds += 1
	for id in state.seat_order:
		var player: PlayerState = state.players[id]
		var score: ScoringTypes.ScoreBreakdown = player.provisional_score
		var normal: ScoringTypes.NormalHandResult = player.locked_normal
		var context: ScoringTypes.ContextHandResult = player.locked_context
		_output.store_line(JSON.stringify({
			"round": state.round_number, "seat": player.seat_index + 1, "score": score.final_score,
			"cards": player.submitted_faces.size(), "round_winner": id == state.last_round_winner_id,
			"hand_type": str(normal.category_id) if normal != null else "",
			"hand_components": score.card_hand_components.map(func(part): return str(part.source_definition_id)),
			"context_type": str(context.category_id) if context != null else "",
			"context_group": str(context.broad_category_id) if context != null else "",
			"context_counts": context.counts if context != null else {},
			"base": score.base_value, "hand_multi": _ratio(score.card_hand_factor),
			"context_multi": _ratio(score.context_hand_factor), "field_multi": _ratio(score.field_factor),
		}))


func _ratio(value: Rational) -> float:
	return float(value.numerator) / value.denominator


func _configured_multipliers(config: MatchConfig) -> Dictionary:
	var result := {"hand": {}, "flush": {}, "context": {}}
	for definition in config.normal_definitions:
		var group := "flush" if definition.component_group == &"suit" else "hand"
		result[group][str(definition.id)] = _ratio(definition.multiplier)
	for definition in config.context_definitions:
		result.context[str(definition.id)] = _ratio(definition.multiplier)
	return result


func _fail(reason: String) -> void:
	push_error(reason)
	if _output != null:
		_output.close()
	quit(1)
