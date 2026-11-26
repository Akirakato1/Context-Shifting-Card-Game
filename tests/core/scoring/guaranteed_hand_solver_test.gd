extends "res://tests/test_case.gd"

const SOLVER_PATH := "res://src/core/scoring/guaranteed_hand_solver.gd"
const P1 := &"one"
const P2 := &"two"
const RISE := GameTypes.Context.RISE
const FLOURISH := GameTypes.Context.FLOURISH
const FALL := GameTypes.Context.FALL
const MOUNTAIN := GameTypes.Suit.MOUNTAIN
const CLOUD := GameTypes.Suit.CLOUD


func test_candidates_choose_distinct_evenly_spaced_scores() -> void:
	var state := _state()
	state.config = MatchConfig.new([P1, P2], [], GameTypes.VictoryMode.SCORE_RACE, 1000,
		GameTypes.InformationVisibility.PUBLIC, {}, 100, 30000, 30000, [],
		[NormalHandDefinition.new(&"high_card", 1, 1, &"high_card", Rational.new(1))])
	var player: PlayerState = state.players[P1]
	player.hand.clear()
	player.ability_hand.clear()
	for rank_value in range(1, 7):
		player.hand.append(_card(StringName("card-%d" % rank_value), RISE, rank_value, RISE, rank_value))
	var snapshot := _capture(state)
	if snapshot == null:
		return
	var candidates: Array = snapshot.call(&"solve_candidates")
	assert_eq(candidates.map(func(candidate: Dictionary): return candidate.score),
		[21, 19, 17, 14, 12, 10, 8, 5, 3, 1])


func test_all_ten_ranked_scores_have_replayable_moves() -> void:
	var state := MatchState.create(_state().config, 107)
	state.phase = GameTypes.Phase.HAND_PLAY
	var snapshot := _capture(state)
	if snapshot == null:
		return
	var candidates: Array = snapshot.call(&"solve_candidates")
	assert_eq(candidates.size(), 10)
	var previous := 0
	for index in candidates.size():
		var plan: Dictionary = candidates[index]
		if index > 0:
			assert_true(plan.score < previous)
		previous = plan.score
		_assert_plan_replay(MatchState.from_dict(state.to_dict()), plan)


func test_deterministic_search_budget_keeps_replayable_partial_candidates() -> void:
	var state := MatchState.create(_state().config, 107)
	state.phase = GameTypes.Phase.HAND_PLAY
	var full := _capture(state)
	var limited := _capture(state)
	var repeated := _capture(state)
	var methods := limited.get_method_list().filter(func(method: Dictionary):
		return method.name == &"solve_candidates" and method.args.size() == 1
	)
	assert_false(methods.is_empty(), "Candidate search accepts a deterministic work limit")
	if methods.is_empty():
		return
	var all_plans: Array = full.call(&"solve_candidates")
	var partial: Array = limited.call(&"solve_candidates", 40)
	assert_false(partial.is_empty())
	assert_ne(partial, all_plans)
	assert_eq(partial, repeated.call(&"solve_candidates", 40))
	var exhausted: Array[Dictionary] = _capture(state).call(&"solve_candidates", 1)
	assert_true(exhausted.is_empty())
	for plan in partial:
		_assert_plan_replay(MatchState.from_dict(state.to_dict()), plan)


func test_candidate_worker_uses_captured_state_and_optional_buff() -> void:
	var state := _state()
	var player: PlayerState = state.players[P1]
	player.hand.assign([_card(&"a", RISE, 4, FALL, 1), _card(&"b", RISE, 4, FALL, 2)])
	player.ability_hand.assign([_ability(&"family_buff")])
	var snapshot := _capture(state)
	if snapshot == null:
		return
	var hint: Dictionary = _capture(state).call(&"solve_best_candidate")
	assert_eq(hint.get("score"), 14)
	assert_eq(hint.get("hand_type"), "pair")
	assert_eq(hint.get("faces", []).size(), 2)
	assert_eq(hint.get("main_2", []).size(), 1)
	state.active_context = FALL
	player.hand[0].first.apply_overrides(FALL, 1, MOUNTAIN)
	player.ability_hand.clear()
	var worker := Thread.new()
	assert_eq(worker.start(Callable(snapshot, &"solve_candidates")), OK)
	var candidates: Array = worker.wait_to_finish()
	assert_eq(candidates.map(func(candidate: Dictionary): return candidate.score), [14, 10, 4])
	if candidates.size() == 3:
		assert_eq(candidates[0].main_2.size(), 1)
		assert_eq(candidates[0].main_2[0].copy_id, &"family_buff-copy")
		assert_true(candidates[1].main_2.is_empty())
		assert_true(candidates[2].main_2.is_empty())


func test_candidate_joker_ranks_preserve_intermediate_scores() -> void:
	var state := _state()
	state.config = MatchConfig.new([P1, P2], [], GameTypes.VictoryMode.SCORE_RACE, 1000,
		GameTypes.InformationVisibility.PUBLIC, {}, 100, 30000, 30000, [],
		NormalHandCatalog.definitions(),
		[ContextHandDefinition.new(&"flourish_bonus", 1, {FLOURISH: 1}, Rational.new(2))])
	var player: PlayerState = state.players[P1]
	var joker := _card(&"joker", RISE, 1, FALL, 1)
	joker.first.make_joker()
	player.hand.assign([_card(&"a", RISE, 4, FALL, 1), joker])
	player.ability_hand.clear()
	var snapshot := _capture(state)
	if snapshot == null:
		return
	var candidates: Array = snapshot.call(&"solve_candidates")
	assert_eq(candidates.map(func(candidate: Dictionary): return candidate.score), [5, 4])
	state.ability_deck.play_field(_ability(&"flourish_resonance"), P1)
	candidates = _capture(state).call(&"solve_candidates")
	assert_eq(candidates.map(func(candidate: Dictionary): return candidate.score), [10, 8, 5, 4])


func test_cancelled_snapshot_returns_no_candidates() -> void:
	var snapshot := _capture(_state())
	if snapshot == null:
		return
	snapshot.call(&"cancel")
	assert_eq(snapshot.call(&"solve_candidates"), [])


func test_early_finish_preserves_candidates_the_worker_already_found() -> void:
	var state := _state()
	var player: PlayerState = state.players[P1]
	player.hand.assign([_card(&"a", RISE, 4, FALL, 1)])
	player.ability_hand.clear()
	var snapshot := _capture(state)
	if snapshot == null:
		return
	var cancel_methods := snapshot.get_method_list().filter(func(method: Dictionary):
		return method.name == &"cancel" and method.args.size() == 1)
	if cancel_methods.is_empty():
		assert_true(false, "Cancellation can keep plans the worker has already found")
		return
	assert_eq(snapshot.call(&"solve_candidates").size(), 1)
	snapshot.call(&"cancel", true)
	var candidates: Array = snapshot.call(&"solve_candidates")
	assert_eq(candidates.map(func(candidate: Dictionary): return candidate.score), [4])
	snapshot.call(&"cancel")
	assert_eq(snapshot.call(&"solve_candidates"), [])


func test_difficulty_picks_only_its_rank_range() -> void:
	var solver := load(SOLVER_PATH) as GDScript
	if not solver.has_method(&"pick_candidate"):
		assert_true(false, "The solver can pick a candidate for a difficulty")
		return
	var ranks: Array[Dictionary] = []
	for index in range(1, 11):
		ranks.append({"rank": index})
	var rng := RandomSource.new(871)
	for band in [[&"easy", 6, 10], [&"standard", 3, 8], [&"hard", 1, 5]]:
		var seen := {}
		for attempt in 100:
			var picked: Dictionary = solver.call(&"pick_candidate", ranks, band[0], rng)
			seen[picked.rank] = true
		var picked_ranks := seen.keys()
		picked_ranks.sort()
		assert_eq(picked_ranks, range(band[1], band[2] + 1))
	var short_list: Array[Dictionary] = ranks.slice(0, 2)
	var standard_ranks := {}
	for attempt in 100:
		assert_eq(solver.call(&"pick_candidate", short_list, &"easy", rng).rank, 2)
		assert_eq(solver.call(&"pick_candidate", short_list, &"hard", rng).rank, 1)
		standard_ranks[solver.call(&"pick_candidate", short_list, &"standard", rng).rank] = true
	assert_eq(standard_ranks.size(), 2)


func test_plan_replays_both_phases_without_reading_or_advancing_live_rng() -> void:
	var state := _state()
	state.context_direction = GameTypes.ContextDirection.REVERSE
	var player: PlayerState = state.players[P1]
	player.hand.assign([
		_card(&"a", RISE, 10, FALL, 1),
		_card(&"b", FALL, 1, FALL, 2),
	])
	player.ability_hand.assign([
		_ability(&"mirror_rank"), _ability(&"against_the_cycle"),
		_ability(&"high_roll"), _ability(&"family_buff"), _ability(&"family_nerf"),
	])
	state.ability_deck.play_field(_ability(&"mountain_favor", P2), P2)
	var before := state.to_dict()
	var rng_before := state.rng.state_token()
	var plan := _solve(state)
	if plan.is_empty():
		return
	var snapshot := _capture(state)
	if snapshot == null:
		return
	var candidates: Array = snapshot.call(&"solve_candidates")
	assert_false(candidates.is_empty())
	if candidates.is_empty():
		return
	assert_eq(candidates[0], plan)
	plan = candidates[0]
	assert_eq(state.to_dict(), before)
	assert_eq(state.rng.state_token(), rng_before)
	assert_eq(plan.score, 42)
	assert_eq(plan.hand_play.size(), 2)
	assert_eq(plan.main_2.size(), 1)
	assert_eq(plan.main_2[0].copy_id, &"family_buff-copy")
	_assert_plan_replay(state, plan)


func _assert_plan_replay(state: MatchState, plan: Dictionary) -> void:
	var controller := MatchController.new(state)
	for index in plan.hand_play.size():
		var play: Dictionary = plan.hand_play[index]
		assert_true(controller.submit(GameCommand.new(StringName("stage-%d" % index), P1,
			CommandKinds.STAGE_MANIPULATION, {"copy_id": play.copy_id}), 10).accepted)
		assert_true(controller.submit(GameCommand.new(StringName("commit-%d" % index), P1,
			CommandKinds.COMMIT_MANIPULATION, {"choices": play.choices}), 10).accepted)
	assert_true(controller.submit(GameCommand.new(&"submit", P1, CommandKinds.STAGE_HAND,
		{"cards": plan.submission}), 10).accepted)
	assert_true(controller.submit(GameCommand.new(&"lock-one", P1, CommandKinds.LOCK_HAND), 10).accepted)
	assert_true(controller.submit(GameCommand.new(&"lock-two", P2, CommandKinds.LOCK_HAND), 10).accepted)
	for index in plan.main_2.size():
		assert_true(controller.submit(GameCommand.new(StringName("buff-%d" % index), P1,
			CommandKinds.PLAY_PUBLIC_ABILITY, plan.main_2[index]), 10).accepted)
	var player: PlayerState = state.players[P1]
	assert_eq(player.provisional_score.final_score if player.provisional_score != null else -1, plan.score)


func test_joker_contexts_and_suits_use_both_halves_and_active_fields() -> void:
	var state := _state()
	var player: PlayerState = state.players[P1]
	var normal := _card(&"normal", FLOURISH, 10, FALL, 1)
	var joker := _card(&"joker", RISE, 1, FALL, 1)
	joker.first.make_joker()
	joker.second.make_joker()
	player.hand.assign([normal, joker])
	player.ability_hand.clear()
	state.ability_deck.play_field(_ability(&"flourish_resonance"), P1)
	state.ability_deck.play_field(_ability(&"flourish_ascendancy", P2), P2)
	state.ability_deck.play_field(_ability(&"mountain_favor", P2), P2)
	var plan := _solve(state)
	if plan.is_empty():
		return
	var evaluated := SubmissionEvaluator.evaluate(player.hand, plan.submission, state.active_context,
		state.config.normal_definitions, state.config.context_definitions, player.factor_modifiers,
		state.ability_deck.active_fields())
	assert_true(evaluated.is_valid)
	assert_eq(evaluated.score_breakdown.final_score, plan.score)
	assert_eq(evaluated.score_breakdown.base_value, 10)
	assert_eq(evaluated.normal_result.category_id, &"pair")
	assert_eq(evaluated.context_result.counts[FLOURISH], 2)
	assert_eq(evaluated.selected_faces[1].rank, 10)
	assert_eq(evaluated.selected_faces[1].suit, MOUNTAIN)


func test_ability_seal_and_submission_lock_are_in_force() -> void:
	var state := _state()
	var player: PlayerState = state.players[P1]
	player.hand.assign([_card(&"usable", RISE, 1, FALL, 1), _card(&"locked", RISE, 10, RISE, 10)])
	player.submission_locked_card_ids.assign([&"locked"])
	player.abilities_disabled = true
	player.ability_hand.assign([_ability(&"mirror_rank"), _ability(&"high_card_buff")])
	var plan := _solve(state)
	if plan.is_empty():
		return
	assert_true(plan.hand_play.is_empty())
	assert_true(plan.main_2.is_empty())
	assert_eq(plan.submission.size(), 1)
	assert_eq(plan.submission[0].card_id, &"usable")
	assert_eq(plan.score, 1)


func test_reduced_joker_choices_match_exhaustive_scoring() -> void:
	var state := _state()
	var player: PlayerState = state.players[P1]
	var joker := _card(&"joker", RISE, 1, FALL, 1)
	joker.first.make_joker()
	player.hand.assign([_card(&"a", RISE, 9, FALL, 1), _card(&"b", FALL, 1, RISE, 9), joker])
	player.ability_hand.clear()
	state.ability_deck.play_field(_ability(&"mountain_favor"), P1)
	state.ability_deck.play_field(_ability(&"rise_ascendancy"), P1)
	var normal := state.config.normal_definitions
	var context := state.config.context_definitions
	var fields := state.ability_deck.active_fields()
	var exhaustive_score := 0
	for mask in 4:
		var selected: Array = []
		if mask & 1:
			selected.append({"card_id": &"a", "half_index": 0, "joker_choices": []})
		if mask & 2:
			selected.append({"card_id": &"b", "half_index": 1, "joker_choices": []})
		var without_joker := SubmissionEvaluator.evaluate(player.hand, selected, RISE,
			normal, context, player.factor_modifiers, fields)
		exhaustive_score = maxi(exhaustive_score, without_joker.score_breakdown.final_score)
		var joker_choice := {"half_index": 0, "context": 0, "rank": 0, "suit": 0}
		selected.append({"card_id": &"joker", "half_index": 0, "joker_choices": [joker_choice]})
		for chosen_context in 3:
			joker_choice.context = chosen_context
			for suit in 3:
				joker_choice.suit = suit
				for rank in 11:
					joker_choice.rank = rank
					var candidate := SubmissionEvaluator.evaluate(player.hand, selected, RISE,
						normal, context, player.factor_modifiers, fields)
					if candidate.is_valid:
						exhaustive_score = maxi(exhaustive_score, candidate.score_breakdown.final_score)
	var plan := _solve(state)
	if not plan.is_empty():
		assert_eq(plan.score, exhaustive_score)


func _capture(state: MatchState) -> RefCounted:
	var solver := load(SOLVER_PATH) as GDScript
	if not solver.has_method(&"capture"):
		assert_true(false, "The solver can capture an unlocked player's hand")
		return null
	var snapshot: RefCounted = solver.call(&"capture", state, P1)
	assert_true(snapshot != null)
	return snapshot


func _solve(state: MatchState) -> Dictionary:
	var solver := load(SOLVER_PATH) as GDScript if ResourceLoader.exists(SOLVER_PATH) else null
	if solver == null or not solver.can_instantiate():
		assert_true(false, "The guaranteed hand solver is available")
		return {}
	var result: Dictionary = solver.call(&"find_best", state, P1)
	assert_false(result.is_empty(), "A valid Hand Play state produces a plan")
	return result


func _state() -> MatchState:
	var config := MatchConfig.new([P1, P2], [], GameTypes.VictoryMode.SCORE_RACE, 1000,
		GameTypes.InformationVisibility.PUBLIC, {
			GameTypes.Phase.START: 1000, GameTypes.Phase.MAIN_1: 1000,
			GameTypes.Phase.HAND_PLAY: 1000, GameTypes.Phase.MAIN_2: 1000, GameTypes.Phase.END: 1000,
		}, 100, 30000, 30000,
		AbilityCatalog.build_deck(AbilityCatalog.provisional_deck_recipe()),
		NormalHandCatalog.definitions(), ContextHandCatalog.definitions(), true)
	var state := MatchState.create(config, 1)
	state.phase = GameTypes.Phase.HAND_PLAY
	return state


func _card(id: StringName, a: int, rank_a: int, b: int, rank_b: int) -> FullCardState:
	return FullCardState.new(id,
		HalfCardState.new(StringName("%s-a" % id), a, rank_a, MOUNTAIN),
		HalfCardState.new(StringName("%s-b" % id), b, rank_b, CLOUD))


func _ability(id: StringName, owner: StringName = P1) -> AbilityState:
	for definition in AbilityCatalog.all_designs():
		if definition.id == id:
			var copy := AbilityState.new(StringName("%s-copy" % id), definition)
			copy.move_to(AbilityState.Zone.HAND, owner)
			return copy
	return null
