extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")
const ContextHandDefinition = preload("res://src/core/scoring/context_hand_definition.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")
const NormalHandEvaluator = preload("res://src/core/scoring/normal_hand_evaluator.gd")
const ContextHandEvaluator = preload("res://src/core/scoring/context_hand_evaluator.gd")
const ScoreCalculator = preload("res://src/core/scoring/score_calculator.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const EventKinds = preload("res://src/core/events/event_kinds.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")


func test_main_two_allows_only_hand_shape_effects_and_does_not_reclassify() -> void:
	var state := _main_two_state(51)
	_set_ability(state, &"one", 0, _ability(&"buff", AbilityDefinition.Timing.HAND_SHAPE, &"factor_modifier"))
	_set_ability(state, &"two", 0, _field(&"weather"))
	var original_normal: StringName = state.players[&"one"].locked_normal.category_id
	var original_context: StringName = state.players[&"one"].locked_context.category_id
	var original_score: int = state.players[&"one"].provisional_score.final_score
	var controller := MatchController.new(state)
	controller.tick(0)

	var buff := controller.submit(_play(
		&"buff", &"one", state.players[&"one"].ability_hand[0].copy_id, &"one",
		{"operation": &"add", "numerator": 1, "denominator": 1}
	), 100)
	var field := controller.submit(_play(
		&"field", &"two", state.players[&"two"].ability_hand[0].copy_id
	), 101)

	assert_true(buff.accepted)
	assert_eq(field.error_code, &"ability_timing_not_allowed")
	assert_eq(state.players[&"one"].locked_normal.category_id, original_normal)
	assert_eq(state.players[&"one"].locked_context.category_id, original_context)
	assert_true(state.players[&"one"].provisional_score.final_score > original_score)
	controller.submit(_ready(&"r1", &"one"), 110)
	controller.submit(_ready(&"r2", &"two"), 120)
	assert_eq(state.phase, GameTypes.Phase.MAIN_2)
	controller.tick(1100)
	assert_true(state.phase == GameTypes.Phase.END or state.phase == GameTypes.Phase.START)


func test_end_rounds_once_cleans_played_cards_preserves_kept_overrides_and_ticks_fields() -> void:
	var state := _main_two_state(52)
	var played = state.players[&"one"].submitted_cards[0]
	var kept = _different_card(state.players[&"one"].hand, played.card_id)
	kept.first.apply_overrides(
		kept.first.effective_context(), 10, kept.first.effective_suit()
	)
	var played_half_ids := [played.first.copy_id, played.second.copy_id]
	_set_ability(state, &"two", 0, _field(&"lasting"))
	var field_card = state.players[&"two"].ability_hand[0]
	state.players[&"two"].ability_hand.erase(field_card)
	var field = state.ability_deck.play_field(field_card, &"two").field
	var controller := MatchController.new(state)

	var result: Variant = _ready_both(controller, 10)

	assert_eq(state.last_round_winner_id, &"one")
	assert_true(state.players[&"one"].finalized_score > state.players[&"two"].finalized_score)
	assert_false(state.players[&"one"].hand.has(played))
	assert_eq(kept.first.effective_rank(), 10)
	assert_eq(field.remaining_rounds, 1)
	assert_eq(state.round_number, 2)
	assert_eq(state.phase, GameTypes.Phase.START)
	for half_id in played_half_ids:
		var returned = _used_half(state, half_id)
		assert_true(returned != null)
		assert_eq(returned.effective_rank(), returned.base_rank)
	assert_true(_first_event(result.events, EventKinds.ROUND_FINALIZED) != null)


func test_end_uses_one_final_ceiling_factor_floor_and_nil_tie() -> void:
	var rounded := _main_two_state(53)
	_set_face_rank(rounded.players[&"one"], 1)
	_recalculate_locked(rounded, &"one")
	rounded.players[&"one"].factor_modifiers.assign([
		ScoringTypes.FactorModifier.new(&"card_hand", &"high_card", Rational.new(1, 2), &"fraction", &"fraction"),
		ScoringTypes.FactorModifier.new(&"card_hand", &"high_card", Rational.new(-1, 3), &"scale", &"scale"),
	])
	var rounded_controller := MatchController.new(rounded)
	_ready_both(rounded_controller, 10)
	assert_eq(rounded.players[&"one"].finalized_score, 2)

	var floored := _main_two_state(54)
	floored.players[&"one"].factor_modifiers.assign([
		ScoringTypes.FactorModifier.new(&"card_hand", &"high_card", Rational.new(-100, 1), &"penalty", &"penalty"),
	])
	var floor_controller := MatchController.new(floored)
	_ready_both(floor_controller, 10)
	assert_eq(floored.players[&"one"].finalized_score, 2)

	var tied := _main_two_state(55)
	_set_face_rank(tied.players[&"one"], 1)
	_set_face_rank(tied.players[&"two"], 1)
	_recalculate_locked(tied, &"one")
	_recalculate_locked(tied, &"two")
	var tie_controller := MatchController.new(tied)
	_ready_both(tie_controller, 10)
	assert_eq(tied.last_round_winner_id, &"")
	assert_eq(tied.players[&"one"].match_score, 0)
	assert_eq(tied.players[&"two"].match_score, 0)


func test_end_awards_both_victory_modes_and_unlocks_then_resets_rematch() -> void:
	var score_state := _main_two_state(56, GameTypes.VictoryMode.SCORE_RACE, 1)
	var score_controller := MatchController.new(score_state)
	_ready_both(score_controller, 10)
	assert_true(score_state.match_complete)
	assert_eq(score_state.winner_id, &"one")
	assert_false(score_state.config.match_started)

	var wins_state := _main_two_state(57, GameTypes.VictoryMode.ROUND_WIN_RACE, 1)
	var wins_controller := MatchController.new(wins_state)
	_ready_both(wins_controller, 10)
	assert_eq(wins_state.players[&"one"].round_wins, 1)
	assert_eq(wins_state.winner_id, &"one")

	var occupants := wins_state.players.keys()
	wins_controller.reset_for_rematch(99)
	assert_eq(wins_controller.state.players.keys(), occupants)
	assert_eq(wins_controller.state.active_context, GameTypes.Context.RISE)
	assert_eq(wins_controller.state.ability_deck.active_fields().size(), 0)
	assert_eq(wins_controller.state.players[&"one"].match_score, 0)
	assert_eq(wins_controller.state.players[&"one"].round_wins, 0)
	assert_false(wins_controller.state.config.match_started)


func test_confirmed_and_timeout_discards_reach_three_with_visibility_rules() -> void:
	var public_state := _main_two_state(58)
	_give_extra_abilities(public_state, &"one", 3)
	var public_controller := MatchController.new(public_state)
	_ready_both(public_controller, 10)
	assert_eq(public_state.phase, GameTypes.Phase.END)
	var discard_ids := [
		public_state.players[&"one"].ability_hand[0].copy_id,
		public_state.players[&"one"].ability_hand[1].copy_id,
	]
	var confirmed := public_controller.submit(GameCommand.new(
		&"discard", &"one", CommandKinds.CHOOSE_ABILITY_DISCARDS,
		{"copy_ids": discard_ids}
	), 20)
	assert_eq(public_state.players[&"one"].ability_hand.size(), 3)
	var public_discard = _first_event(confirmed.events, EventKinds.ABILITIES_DISCARDED)
	assert_true(public_discard.payload.has("ability_ids"))

	var private_state := _main_two_state(59, GameTypes.VictoryMode.SCORE_RACE, 100, GameTypes.InformationVisibility.PRIVATE)
	_give_extra_abilities(private_state, &"one", 3)
	var private_controller := MatchController.new(private_state)
	_ready_both(private_controller, 10)
	var timeout_events := private_controller.tick(private_state.phase_deadline_msec)
	assert_eq(private_state.players[&"one"].ability_hand.size(), 3)
	var public_count = _audience_event(timeout_events, EventKinds.ABILITIES_DISCARDED, &"public")
	var owner_detail = _recipient_event(timeout_events, EventKinds.ABILITIES_DISCARDED, &"one")
	assert_false(public_count.payload.has("ability_ids"))
	assert_true(owner_detail.payload.has("ability_ids"))


func test_disconnect_noticed_inside_end_is_applied_after_committed_award() -> void:
	var state := _main_two_state(60, GameTypes.VictoryMode.SCORE_RACE, 1)
	var controller := MatchController.new(state)
	controller.end_transaction_probe = func() -> void:
		controller.notify_player_disconnected(&"one")

	_ready_both(controller, 10)

	assert_eq(state.winner_id, &"")
	assert_true(state.players[&"one"].match_score >= 1)
	assert_false(state.players[&"one"].connected)


func _main_two_state(
	seed_value: int,
	mode: int = GameTypes.VictoryMode.SCORE_RACE,
	target: int = 100,
	visibility: int = GameTypes.InformationVisibility.PUBLIC
) -> MatchState:
	var abilities: Array[AbilityDefinition] = []
	for index in range(20): abilities.append(_ability(
		StringName("base-%d" % index), AbilityDefinition.Timing.HAND_SHAPE, &"noop"
	))
	var normals: Array[NormalHandDefinition] = [
		NormalHandDefinition.new(&"high_card", 10, 1, &"high_card", Rational.new(1, 1)),
	]
	var contexts: Array[ContextHandDefinition] = []
	var config := MatchConfig.new(
		[&"one", &"two"], [], mode, target, visibility,
		{GameTypes.Phase.START: 5000, GameTypes.Phase.MAIN_1: 5000,
		GameTypes.Phase.HAND_PLAY: 5000, GameTypes.Phase.MAIN_2: 5000,
		GameTypes.Phase.END: 2000}, 1000, 5000, 30000, abilities, normals, contexts
	)
	var state := MatchState.create(config, seed_value)
	state.phase = GameTypes.Phase.MAIN_2
	state.phase_started_msec = -1
	state.phase_deadline_msec = -1
	_stage_one_card(state, &"one", 2)
	_stage_one_card(state, &"two", 1)
	return state


func _stage_one_card(state: MatchState, player_id: StringName, rank: int) -> void:
	var player = state.players[player_id]
	var card = null
	var half = null
	var half_index := -1
	for candidate in player.hand:
		for candidate_index in range(2):
			var candidate_half = candidate.half_at(candidate_index)
			if not candidate_half.is_joker():
				card = candidate
				half = candidate_half
				half_index = candidate_index
				break
		if card != null:
			break
	assert(card != null, "fixture needs one non-Joker half")
	half.apply_overrides(state.active_context, rank, half.effective_suit())
	player.submitted_cards.assign([card])
	player.submitted_faces.assign([
		ScoringTypes.SelectedCardFace.new(card.card_id, half_index, rank, half.effective_suit())
	])
	_recalculate_locked(state, player_id)


func _recalculate_locked(state: MatchState, player_id: StringName) -> void:
	var player = state.players[player_id]
	player.locked_normal = NormalHandEvaluator.evaluate(player.submitted_faces, state.config.normal_definitions)
	player.locked_context = ContextHandEvaluator.evaluate(player.submitted_cards, state.config.context_definitions)
	player.provisional_score = ScoreCalculator.calculate(
		player.submitted_faces, player.locked_normal, player.locked_context, player.factor_modifiers
	)


func _set_face_rank(player, rank: int) -> void:
	player.submitted_faces[0].rank = rank


func _ready_both(controller: MatchController, now_msec: int):
	controller.tick(0)
	controller.submit(_ready(&"ready-one", &"one"), now_msec)
	return controller.submit(_ready(&"ready-two", &"two"), now_msec)


func _give_extra_abilities(state: MatchState, player_id: StringName, count: int) -> void:
	state.players[player_id].ability_hand.append_array(
		state.ability_deck.draw(player_id, count, state.rng)
	)


func _different_card(hand: Array, excluded_id: StringName):
	for card in hand:
		if card.card_id != excluded_id: return card
	return null


func _used_half(state: MatchState, half_id: StringName):
	for pile in state.piles.values():
		for half in pile.snapshot_used_cards():
			if half.copy_id == half_id: return half
	return null


func _ability(id: StringName, timing: int, effect_id: StringName) -> AbilityDefinition:
	var parameters := {}
	if effect_id == &"factor_modifier":
		parameters = {"factor_id": &"card_hand", "category_id": &"high_card", "numerator": 1, "denominator": 1}
	return AbilityDefinition.new(id, timing, [], effect_id, 0, &"", parameters)


func _field(id: StringName) -> AbilityDefinition:
	return AbilityDefinition.new(id, AbilityDefinition.Timing.FIELD, [], &"noop", 2)


func _set_ability(state: MatchState, player_id: StringName, index: int, definition: AbilityDefinition) -> void:
	state.players[player_id].ability_hand[index].definition = definition


func _ready(id: StringName, player_id: StringName) -> GameCommand:
	return GameCommand.new(id, player_id, CommandKinds.SET_READY, {"ready": true})


func _play(id: StringName, player_id: StringName, copy_id: StringName, target: StringName = &"", _effect: Dictionary = {}) -> GameCommand:
	return GameCommand.new(id, player_id, CommandKinds.PLAY_PUBLIC_ABILITY, {
		"copy_id": copy_id, "target_player_id": target,
	})


func _first_event(events: Array, kind: StringName):
	for event in events:
		if event.kind == kind: return event
	return null


func _audience_event(events: Array, kind: StringName, audience: StringName):
	for event in events:
		if event.kind == kind and event.audience == audience: return event
	return null


func _recipient_event(events: Array, kind: StringName, recipient: StringName):
	for event in events:
		if event.kind == kind and event.recipient_id == recipient: return event
	return null
