class_name GuaranteedHandSolver
extends RefCounted

const DETERMINISTIC_OPERATIONS := [
	&"context_exchange", &"context_convergence", &"set_context", &"shift_context",
	&"suit_imprint", &"suit_exchange", &"shift_suit", &"mirror_rank",
]
const MAX_CANDIDATES := 10
# Base 13 keeps counts of up to twelve submitted halves in separate digits.
const CONTEXT_WEIGHTS := [1, 13, 169]

enum Stop { NONE, KEEP_CANDIDATES, DISCARD_CANDIDATES }

var _player_id: StringName
var _hand: Array[FullCardState] = []
var _locked_card_ids: Array[StringName]
var _pending_manipulation: bool
var _active_context: int
var _context_direction: int
var _normal_definitions: Array[NormalHandDefinition]
var _context_definitions: Array[ContextHandDefinition]
var _fields: Array[FieldState] = []
var _contexts: PackedInt32Array
var _manipulations: Array[AbilityState] = []
var _modifiers: Array[ScoringTypes.FactorModifier] = []
var _all_modifiers: Array[ScoringTypes.FactorModifier] = []
var _buffs: Array[ScoringTypes.FactorModifier] = []
var _collect_candidates := false
var _best_only := false
var _best_candidate_score := -1
var _plans_by_score := {}
var _stop := Stop.NONE
var _remaining_work := -1
var _cancel_mutex := Mutex.new()
var _visited := {}
var _scored_hands := {}
var _scores := {}
var _normal_results := {}
var _context_results := {}
var _joker_ranks := {}
var _ability_choices := {}
var _best := {"score": 0, "submission": [], "hand_play": [], "main_2": []}
var _best_hand: Array[FullCardState] = []


## Computes the best finishing score from an unlocked Hand Play state, without changing it.
## Hand Play records contain a copy ID and commit choices. Main 2 records are public-play payloads.
static func find_best(state: MatchState, player_id: StringName) -> Dictionary:
	var solver := capture(state, player_id)
	if solver == null:
		return {}
	solver._search(solver._hand, solver._manipulations, [])
	solver._add_main_two_plays()
	return solver._best


## Captures one player's search inputs on the main thread. The snapshot can run on a worker.
static func capture(state: MatchState, player_id: StringName) -> GuaranteedHandSolver:
	if state == null or state.phase != GameTypes.Phase.HAND_PLAY or state.frozen:
		return null
	var player: PlayerState = state.players.get(player_id)
	if player == null or not player.active or player.pending or player.hand_locked:
		return null
	var solver := GuaranteedHandSolver.new()
	solver._capture_inputs(state, player)
	return solver


## Runs on one worker. A positive budget counts search checkpoints for reproducible offline play.
## The caller can also request cancellation from another thread.
func solve_candidates(work_budget := 0) -> Array[Dictionary]:
	_remaining_work = work_budget if work_budget > 0 else -1
	_collect_candidates = true
	if _manipulations.size() > 1:
		# Seed the ranked options across every single play before exploring long chains.
		_search(_hand, _manipulations, [], "", 1)
		_visited.clear()
	_search(_hand, _manipulations, [])
	var stop := _stop_status()
	if stop == Stop.DISCARD_CANDIDATES:
		return []
	if _plans_by_score.is_empty():
		if stop == Stop.NONE and _remaining_work != 0:
			return [_best]
		return []
	return _representative_plans()


## Computes one best guaranteed plan and the final faces for the Practice companion.
func solve_best_candidate() -> Dictionary:
	_best_only = true
	var plans := solve_candidates()
	if plans.is_empty() or _stop_status() == Stop.DISCARD_CANDIDATES:
		return {}
	var plan: Dictionary = plans[0]
	var hand := _hand.duplicate()
	for play: Dictionary in plan.hand_play:
		for ability in _manipulations:
			if ability.copy_id == play.copy_id:
				hand = _copy_targets(hand, play.choices)
				ManipulationResolver.apply(ability.definition, hand, play.choices, null, _context_direction)
				break
	var result := SubmissionEvaluator.evaluate(
		hand, plan.submission, _active_context, _normal_definitions, _context_definitions, _modifiers, _fields
	)
	if result.is_valid:
		plan["faces"] = result.resolved_cards
		plan["hand_type"] = str(result.normal_result.category_id)
		plan["context_type"] = str(result.context_result.category_id)
	return plan


## At a phase deadline the caller can keep the plans that were scored before cancellation.
func cancel(keep_candidates := false) -> void:
	_cancel_mutex.lock()
	if _stop != Stop.DISCARD_CANDIDATES:
		_stop = Stop.KEEP_CANDIDATES if keep_candidates else Stop.DISCARD_CANDIDATES
	_cancel_mutex.unlock()


## Ranks are one-based. Scale the range to the available ranks for shorter lists.
static func pick_candidate(candidates: Array, difficulty: StringName, rng: RandomSource) -> Dictionary:
	if candidates.is_empty():
		return {}
	var band := Vector2i(3, 8)
	match difficulty:
		&"easy": band = Vector2i(6, 10)
		&"hard": band = Vector2i(1, 5)
	var scale := float(candidates.size() - 1) / (MAX_CANDIDATES - 1)
	var first := roundi((band.x - 1) * scale)
	var last := roundi((band.y - 1) * scale)
	return candidates[first + rng.pick_index(last - first + 1)]


func _capture_inputs(state: MatchState, player: PlayerState) -> void:
	_player_id = player.player_id
	_locked_card_ids.assign(player.submission_locked_card_ids)
	_pending_manipulation = not player.pending_manipulation.is_empty()
	_best["cancel_pending_manipulation"] = _pending_manipulation
	_active_context = state.active_context
	_context_direction = state.context_direction
	for card in player.hand:
		_hand.append(FullCardState.new(card.card_id, _copy_half(card.first), _copy_half(card.second)))
	for definition in state.config.normal_definitions:
		_normal_definitions.append(NormalHandDefinition.new(
			definition.id, definition.priority, definition.subset_size, definition.rule_id,
			_copy_rational(definition.multiplier), definition.broad_category_id,
			definition.component_group, definition.rule_parameters))
	for definition in state.config.context_definitions:
		_context_definitions.append(ContextHandDefinition.new(
			definition.id, definition.priority, definition.minimums,
			_copy_rational(definition.multiplier), definition.broad_category_id))
	for field in state.ability_deck.active_fields():
		_fields.append(FieldState.new(_copy_ability(field.ability), field.source_player_id))
	_contexts = FieldEffectResolver.active_contexts(_active_context, _fields)
	for modifier in player.factor_modifiers:
		_modifiers.append(ScoringTypes.FactorModifier.new(modifier.factor_id, modifier.category_id,
			_copy_rational(modifier.delta), modifier.source_copy_id, modifier.source_definition_id))
	if not player.abilities_disabled:
		for ability in player.ability_hand:
			var definition := ability.definition
			var parameters := definition.effect_parameters
			if definition.timing == AbilityDefinition.Timing.HAND_MANIPULATION:
				if StringName(parameters.get("operation", "")) in DETERMINISTIC_OPERATIONS:
					_manipulations.append(_copy_ability(ability))
			elif definition.allows_phase(GameTypes.Phase.MAIN_2) and definition.effect_id == &"factor_modifier":
				var delta := Rational.new(parameters.numerator, parameters.denominator)
				if delta.numerator > 0:
					_buffs.append(ScoringTypes.FactorModifier.new(parameters.factor_id,
						parameters.category_id, delta, ability.copy_id, definition.id))
	_all_modifiers = _modifiers.duplicate()
	_all_modifiers.append_array(_buffs)


func _copy_ability(ability: AbilityState) -> AbilityState:
	var definition := ability.definition
	return AbilityState.new(ability.copy_id, AbilityDefinition.new(
		definition.id, definition.timing, definition.tags, definition.effect_id,
		definition.field_duration, definition.conflict_group,
		definition.effect_parameters, definition.choice_schema))


func _copy_rational(value: Rational) -> Rational:
	return Rational.new(value.numerator, value.denominator)


func _is_cancelled() -> bool:
	if _remaining_work == 0:
		return true
	if _remaining_work > 0:
		_remaining_work -= 1
	return _stop_status() != Stop.NONE


func _stop_status() -> Stop:
	_cancel_mutex.lock()
	var stop := _stop
	_cancel_mutex.unlock()
	return stop


func _search(
	hand: Array[FullCardState], remaining: Array[AbilityState], plays: Array,
	hand_key := "", depth_left := -1
) -> void:
	if _collect_candidates and _is_cancelled():
		return
	var remaining_ids := remaining.map(func(ability: AbilityState): return ability.copy_id)
	if hand_key.is_empty():
		hand_key = _hand_key(hand)
	var key := str([hand_key, remaining_ids])
	if _visited.has(key):
		return
	_visited[key] = true
	_score_hand(hand, plays)
	if depth_left == 0:
		return
	var next_depth := depth_left - 1 if depth_left > 0 else -1
	var tried_definitions := {}
	for index in remaining.size():
		if _collect_candidates and _is_cancelled():
			return
		var ability := remaining[index]
		if tried_definitions.has(ability.definition.id):
			continue
		tried_definitions[ability.definition.id] = true
		var next_remaining := remaining.duplicate()
		next_remaining.remove_at(index)
		for choices: Dictionary in _legal_choices(ability.definition, hand):
			if _collect_candidates and _is_cancelled():
				return
			var next_hand := _copy_targets(hand, choices)
			ManipulationResolver.apply(ability.definition, next_hand, choices, null, _context_direction)
			var next_key := _hand_key(next_hand)
			if next_key == hand_key:
				continue
			plays.append({"copy_id": ability.copy_id, "choices": choices})
			_search(next_hand, next_remaining, plays, next_key, next_depth)
			plays.pop_back()


func _hand_key(hand: Array[FullCardState]) -> String:
	var values := PackedByteArray()
	for card in hand:
		for half: HalfCardState in [card.first, card.second]:
			# Copies and positions are fixed throughout a search. Joker choices can be freely reset.
			var value := 0 if half.is_joker() else (
				1 + half.effective_context() * 30 + (half.effective_rank() - 1) * 3 + half.effective_suit()
			)
			values.append(value)
	return values.hex_encode()


func _legal_choices(definition: AbilityDefinition, hand: Array[FullCardState]) -> Array:
	# Manipulations cannot change card IDs or which halves are Jokers. Those are
	# the hand properties that the choice schema validates.
	if not _ability_choices.has(definition.id):
		_ability_choices[definition.id] = valid_manipulation_choices(definition, hand)
	return _ability_choices[definition.id]


static func valid_manipulation_choices(definition: AbilityDefinition, hand: Array[FullCardState]) -> Array[Dictionary]:
	return _choices(definition.choice_schema.steps, hand).filter(
		func(choice: Dictionary): return ManipulationResolver.validate(definition, hand, choice).is_empty()
	)


static func _choices(steps: Array, hand: Array[FullCardState]) -> Array[Dictionary]:
	var combinations: Array[Dictionary] = [{}]
	for step: Dictionary in steps:
		var options: Array = step.get("eligible", []).duplicate()
		match step.kind:
			"full_card":
				for card in hand:
					options.append(card.card_id)
			"half_card":
				for card in hand:
					for index in 2:
						if not step.get("ordinary_only", false) or not card.half_at(index).is_joker():
							options.append({"card_id": card.card_id, "half_index": index})
		var minimum := int(step.get("count", step.get("min_count", 0)))
		var maximum := mini(options.size(), int(step.get("count", step.get("max_count", 0))))
		var expanded: Array[Dictionary] = []
		for size in range(minimum, maximum + 1):
			for selection: Array in _combinations(options, size):
				for prefix in combinations:
					var choice := prefix.duplicate()
					choice[str(step.key)] = selection
					expanded.append(choice)
		combinations = expanded
	return combinations


func _copy_targets(hand: Array[FullCardState], choices: Dictionary) -> Array[FullCardState]:
	var targets: Array = choices.get("cards", []).duplicate()
	for half: Dictionary in choices.get("halves", []):
		targets.append(half.card_id)
	var copy := hand.duplicate()
	for index in hand.size():
		var card := hand[index]
		if card.card_id in targets:
			copy[index] = FullCardState.new(card.card_id, _copy_half(card.first), _copy_half(card.second))
	return copy


func _copy_half(half: HalfCardState) -> HalfCardState:
	var copy := HalfCardState.new(half.copy_id, half.base_context, half.base_rank, half.base_suit, half.kind)
	if half.joker_override:
		copy.make_joker()
	elif not half.is_joker():
		copy.apply_overrides(half.effective_context(), half.effective_rank(), half.effective_suit())
	return copy


func _score_hand(hand: Array[FullCardState], plays: Array) -> void:
	var signature := PackedByteArray()
	var eligible_halves: Array[PackedInt32Array] = []
	var has_jokers := false
	for card in hand:
		var eligible := PackedInt32Array() if card.card_id in _locked_card_ids else (
			card.eligible_half_indexes_for_contexts(_contexts))
		eligible_halves.append(eligible)
		for index in 2:
			var half := card.half_at(index)
			var context := half.effective_context()
			if eligible.is_empty():
				signature.append(0)
			elif half.is_joker():
				has_jokers = true
				signature.append(1)
			elif index in eligible:
				signature.append(2 + 3 * ((half.effective_rank() - 1) * 3 + half.effective_suit()) + context)
			else:
				# An unplayable half still contributes its context when the card is submitted.
				signature.append(92 + context)
	var key := signature.hex_encode()
	if plays.size() >= _scored_hands.get(key, INF):
		return
	_scored_hands[key] = plays.size()
	if has_jokers:
		_submit_combinations(hand, eligible_halves, 0, [], plays)
		return
	var options: Array = []
	for index in hand.size():
		var card := hand[index]
		if eligible_halves[index].is_empty():
			continue
		var context_key: int = CONTEXT_WEIGHTS[card.first.effective_context()] + CONTEXT_WEIGHTS[card.second.effective_context()]
		var choices: Array = []
		for orientation in eligible_halves[index]:
			var half := card.half_at(orientation)
			var face := ScoringTypes.SelectedCardFace.new(card.card_id, orientation,
				half.effective_rank(), half.effective_suit())
			var selection := {"card_id": card.card_id, "half_index": orientation, "joker_choices": []}
			choices.append({"face": face, "selection": selection})
		options.append({"choices": choices, "context": context_key})
	var faces: Array[ScoringTypes.SelectedCardFace] = []
	_submit_ordinary(hand, options, 0, [], faces, 0, plays)


func _submit_ordinary(
	hand: Array[FullCardState], options: Array, index: int, selections: Array,
	faces: Array[ScoringTypes.SelectedCardFace], context_key: int, plays: Array
) -> void:
	if _collect_candidates and _is_cancelled():
		return
	if index == options.size() or selections.size() == SubmissionEvaluator.MAX_SUBMITTED_CARDS:
		if not faces.is_empty():
			_record_scores(_score_faces(faces, context_key), hand, selections, plays)
		return
	_submit_ordinary(hand, options, index + 1, selections, faces, context_key, plays)
	var card_options: Dictionary = options[index]
	for option: Dictionary in card_options.choices:
		selections.append(option.selection)
		faces.append(option.face)
		_submit_ordinary(hand, options, index + 1, selections, faces,
			context_key + int(card_options.context), plays)
		faces.pop_back()
		selections.pop_back()


func _submit_combinations(
	hand: Array[FullCardState], eligible_halves: Array[PackedInt32Array], index: int, selections: Array,
	plays: Array
) -> void:
	if _collect_candidates and _is_cancelled():
		return
	if index == hand.size() or selections.size() == SubmissionEvaluator.MAX_SUBMITTED_CARDS:
		if not selections.is_empty():
			_score_submission(hand, selections, plays)
		return
	_submit_combinations(hand, eligible_halves, index + 1, selections, plays)
	var card := hand[index]
	var eligible := eligible_halves[index]
	if eligible.size() == 2 and card.first.is_joker() and card.second.is_joker():
		eligible = PackedInt32Array([0])
	for half_index in eligible:
		selections.append({"card_id": card.card_id, "half_index": half_index, "joker_choices": []})
		_submit_combinations(hand, eligible_halves, index + 1, selections, plays)
		selections.pop_back()


func _score_submission(hand: Array[FullCardState], selections: Array, plays: Array) -> void:
	var ordinary: Array[ScoringTypes.SelectedCardFace] = []
	var selected_jokers: Array[Dictionary] = []
	var all_jokers: Array[Dictionary] = []
	var known_context_key := 0
	var by_id := {}
	for card in hand:
		by_id[card.card_id] = card
	for selection: Dictionary in selections:
		var card: FullCardState = by_id[selection.card_id]
		selection.joker_choices = []
		for index in 2:
			var half := card.half_at(index)
			var selected: bool = index == selection.half_index
			if half.is_joker():
				var choice := {"half_index": index, "rank": 0, "suit": 0, "context": 0}
				selection.joker_choices.append(choice)
				all_jokers.append(choice)
				if selected:
					selected_jokers.append(choice)
			else:
				known_context_key += int(CONTEXT_WEIGHTS[half.effective_context()])
				if selected:
					ordinary.append(ScoringTypes.SelectedCardFace.new(card.card_id, index,
						half.effective_rank(), half.effective_suit()))
	# An all-Joker hand can never beat the zero-point pass.
	if ordinary.is_empty():
		return
	var context_options := _combinations(Array(_contexts), all_jokers.size(), true)
	for suits: Array in _suit_options(ordinary, selected_jokers.size()):
		if _collect_candidates and _is_cancelled():
			return
		for index in selected_jokers.size():
			selected_jokers[index].suit = suits[index]
		for ranks: Array in _rank_options(ordinary, suits):
			var selected_faces := ordinary.duplicate()
			for index in selected_jokers.size():
				selected_jokers[index].rank = ranks[index]
				selected_faces.append(ScoringTypes.SelectedCardFace.new(&"joker", 0, ranks[index], suits[index], true))
			for contexts: Array in context_options:
				if _collect_candidates and _is_cancelled():
					return
				var context_key := known_context_key
				for index in contexts.size():
					all_jokers[index].context = contexts[index]
					context_key += int(CONTEXT_WEIGHTS[contexts[index]])
				_record_scores(_score_faces(selected_faces, context_key), hand, selections, plays)


func _record_scores(variants: Dictionary, hand: Array[FullCardState], selections: Array, plays: Array) -> void:
	for score: int in variants:
		if _collect_candidates:
			_remember_plan(score, selections, plays, variants[score])
		elif score > _best.score or (score == _best.score and plays.size() < _best.hand_play.size()):
			_best.score = score
			_best.submission = selections.duplicate(true)
			_best.hand_play = plays.duplicate()
			_best_hand = hand


func _remember_plan(score: int, selections: Array, plays: Array, buffs: Array) -> void:
	if _best_only:
		if score < _best_candidate_score:
			return
		if score > _best_candidate_score:
			_best_candidate_score = score
			_plans_by_score.clear()
	var prior: Dictionary = _plans_by_score.get(score, {})
	if not prior.is_empty():
		if prior.hand_play.size() < plays.size():
			return
		if prior.hand_play.size() == plays.size() and prior.main_2.size() <= buffs.size():
			return
	_plans_by_score[score] = {
		"score": score,
		"submission": selections.duplicate(true),
		"hand_play": plays.duplicate(),
		"main_2": buffs.map(_main_two_play),
		"cancel_pending_manipulation": _pending_manipulation,
	}


func _main_two_play(buff: ScoringTypes.FactorModifier) -> Dictionary:
	return {"copy_id": buff.source_copy_id, "target_player_id": _player_id,
		"choices": {"target_player_id": [_player_id]}}


func _representative_plans() -> Array[Dictionary]:
	var scores := _plans_by_score.keys()
	scores.sort()
	scores.reverse()
	if scores.size() <= MAX_CANDIDATES:
		var all_plans: Array[Dictionary] = []
		for score: int in scores:
			all_plans.append(_plans_by_score[score])
		return all_plans

	# Choose distinct ordered scores near equally spaced targets. For each position,
	# scan left to right to find the best compatible prefix for every possible score.
	var predecessors: Array[PackedInt32Array] = []
	var costs := PackedFloat64Array()
	costs.resize(scores.size())
	costs.fill(INF)
	costs[0] = 0
	for rank_index in range(1, MAX_CANDIDATES):
		if _stop_status() == Stop.DISCARD_CANDIDATES:
			return []
		var target := lerpf(scores.front(), scores.back(), float(rank_index) / (MAX_CANDIDATES - 1))
		var row := PackedInt32Array()
		row.resize(scores.size())
		var row_costs := PackedFloat64Array()
		row_costs.resize(scores.size())
		row_costs.fill(INF)
		var best_prefix := 0
		for index in range(1, scores.size()):
			if costs[index - 1] < costs[best_prefix]:
				best_prefix = index - 1
			var error := float(scores[index]) - target
			row[index] = best_prefix
			row_costs[index] = costs[best_prefix] + error * error
		predecessors.append(row)
		costs = row_costs
	var result: Array[Dictionary] = []
	result.resize(MAX_CANDIDATES)
	var index := scores.size() - 1
	for rank_index in range(MAX_CANDIDATES - 1, 0, -1):
		result[rank_index] = _plans_by_score[scores[index]]
		index = predecessors[rank_index - 1][index]
	result[0] = _plans_by_score[scores.front()]
	return result


func _suit_options(ordinary: Array[ScoringTypes.SelectedCardFace], count: int) -> Array:
	if count == 0:
		return [[]]
	var best := {}
	for suits: Array in _combinations([0, 1, 2], count, true):
		var faces := ordinary.duplicate()
		for suit: int in suits:
			faces.append(ScoringTypes.SelectedCardFace.new(&"joker", 0, 0, suit, true))
		var components := FieldEffectResolver.score_components(faces, {}, _fields)
		var total := Rational.new(0)
		for component in components:
			total = total.added(component.value)
		# The rank/flush evaluator only depends on whether all selected suits match.
		# Preserve whether a field component is present as existing field modifiers can depend on it.
		var uniform := _is_uniform(ordinary, suits)
		var key: Variant = (
			[uniform, components.is_empty(), total.numerator, total.denominator]
			if _collect_candidates else Vector2i(uniform, not components.is_empty())
		)
		if not best.has(key) or total.compare_to(best[key].total) > 0:
			best[key] = {"suits": suits, "total": total}
	return best.values().map(func(option: Dictionary): return option.suits)


func _rank_options(ordinary: Array[ScoringTypes.SelectedCardFace], suits: Array) -> Array:
	if suits.is_empty():
		return [[]]
	var fixed_ranks := ordinary.map(func(face: ScoringTypes.SelectedCardFace): return face.rank)
	fixed_ranks.sort()
	var key := str([fixed_ranks, suits.size(), _is_uniform(ordinary, suits)])
	if _joker_ranks.has(key):
		return _joker_ranks[key]
	var best_value: Rational
	var best_ranks: Array = []
	var by_components := {}
	var faces := ordinary.duplicate()
	for suit: int in suits:
		faces.append(ScoringTypes.SelectedCardFace.new(&"joker", 0, 0, suit, true))
	# Joker ranks affect only the card-hand components and can share one representative
	# assignment when those components match.
	for ranks: Array in _combinations(range(11), suits.size(), true):
		if _collect_candidates and _is_cancelled():
			return []
		for index in ranks.size():
			faces[ordinary.size() + index].rank = ranks[index]
		var normal := _normal_result(faces)
		if not normal.is_valid:
			continue
		if _collect_candidates:
			var components := normal.components.map(func(component: ScoringTypes.MultiplierComponent):
				return [component.category_id, component.value.numerator, component.value.denominator])
			if not by_components.has(components):
				by_components[components] = ranks
		else:
			var value := ScoreCalculator.calculate(faces, normal, null, _all_modifiers).card_hand_unclamped
			if best_value == null or value.compare_to(best_value) > 0:
				best_value = value
				best_ranks = ranks
	# If a custom catalog has no valid rank shape, leave submission validation to the evaluator.
	if best_ranks.is_empty():
		best_ranks.resize(suits.size())
		best_ranks.fill(0)
	var options := by_components.values() if _collect_candidates else [best_ranks]
	_joker_ranks[key] = options
	return options


func _is_uniform(ordinary: Array[ScoringTypes.SelectedCardFace], suits: Array) -> bool:
	var suit := ordinary[0].suit
	return ordinary.all(func(face: ScoringTypes.SelectedCardFace): return face.suit == suit) and (
		suits.all(func(joker_suit: int): return joker_suit == suit)
	)


func _normal_result(faces: Array[ScoringTypes.SelectedCardFace]) -> ScoringTypes.NormalHandResult:
	var ranks := faces.map(func(face: ScoringTypes.SelectedCardFace): return face.rank)
	ranks.sort()
	var uniform := faces.all(func(face: ScoringTypes.SelectedCardFace): return face.suit == faces[0].suit)
	var key := str([ranks, uniform])
	if not _normal_results.has(key):
		_normal_results[key] = NormalHandEvaluator.evaluate(faces, _normal_definitions)
	return _normal_results[key]


func _score_faces(faces: Array[ScoringTypes.SelectedCardFace], context_key: int) -> Dictionary:
	var face_values := PackedByteArray()
	for face in faces:
		face_values.append(face.rank * 3 + face.suit + (40 if face.is_joker else 0))
	face_values.sort()
	var face_key := 0
	for value in face_values:
		face_key = (face_key << 7) | value
	# Up to six nonzero face codes followed by three base-13 context digits.
	var key := (face_key << 12) | context_key
	if not _scores.has(key):
		var normal := _normal_result(faces)
		var variants := {}
		if normal.is_valid:
			if not _context_results.has(context_key):
				var contexts := PackedInt32Array()
				var digits := context_key
				for context in 3:
					for _count in digits % 13:
						contexts.append(context)
					digits = floori(digits / 13.0)
				_context_results[context_key] = ContextHandEvaluator.evaluate_contexts(contexts, _context_definitions)
			var context: ScoringTypes.ContextHandResult = _context_results[context_key]
			var fields := FieldEffectResolver.score_components(faces, context.counts, _fields)
			var all := ScoreCalculator.calculate(faces, normal, context, _all_modifiers, fields)
			if _collect_candidates and not _buffs.is_empty():
				var matched := _buffs.filter(func(buff: ScoringTypes.FactorModifier):
					return buff in all.applied_modifiers)
				if _best_only:
					variants[all.final_score] = matched
				else:
					for count in range(matched.size() + 1):
						for subset: Array in _combinations(matched, count):
							var modifiers := _modifiers.duplicate()
							modifiers.append_array(subset)
							var score := ScoreCalculator.calculate(faces, normal, context, modifiers, fields).final_score
							if not variants.has(score):
								variants[score] = subset
			else:
				variants[all.final_score] = []
		_scores[key] = variants
	return _scores[key]


func _add_main_two_plays() -> void:
	if _best.submission.is_empty():
		return
	var evaluation := SubmissionEvaluator.evaluate(_best_hand, _best.submission, _active_context,
		_normal_definitions, _context_definitions, _all_modifiers, _fields)
	var matched: Array = _buffs.filter(func(buff: ScoringTypes.FactorModifier):
		return buff in evaluation.score_breakdown.applied_modifiers)
	for count in range(matched.size() + 1):
		for subset: Array in _combinations(matched, count):
			var modifiers := _modifiers.duplicate()
			modifiers.append_array(subset)
			var score := ScoreCalculator.calculate(evaluation.selected_faces,
				evaluation.normal_result, evaluation.context_result, modifiers,
				evaluation.score_breakdown.field_components)
			if score.final_score == _best.score:
				for buff: ScoringTypes.FactorModifier in subset:
					_best.main_2.append(_main_two_play(buff))
				return


static func _combinations(items: Array, count: int, allow_repeat := false) -> Array:
	var result: Array = []
	_collect_combinations(items, count, 0, allow_repeat, [], result)
	return result


static func _collect_combinations(
	items: Array, count: int, start: int, allow_repeat: bool, picked: Array, result: Array
) -> void:
	if count == 0:
		result.append(picked.duplicate())
		return
	var end := items.size() if allow_repeat else items.size() - count + 1
	for index in range(start, end):
		picked.append(items[index])
		_collect_combinations(items, count - 1, index if allow_repeat else index + 1,
			allow_repeat, picked, result)
		picked.pop_back()
