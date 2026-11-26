extends "res://tests/test_case.gd"

const Runner := preload("res://src/core/match/bot_match_runner.gd")
const HOST := &"host"
const BOT := &"bot"
const SECOND := &"second"
const LOW := &"low"
const RISE := GameTypes.Context.RISE
const FLOURISH := GameTypes.Context.FLOURISH
const FALL := GameTypes.Context.FALL


class Rolls extends RandomSource:
	var values: Array
	var sizes: Array[int] = []

	func _init(scripted: Array) -> void:
		super(1)
		values = scripted.duplicate()

	func pick_index(size: int) -> int:
		sizes.append(size)
		return int(values.pop_front()) if not values.is_empty() else 0


class OpeningOnly extends Runner:
	func _play_hand(_controller: MatchController, _player: PlayerState, _difficulty: int, _now: int) -> void:
		pass


func test_bot_rolls_once_for_one_random_manipulation_before_solving() -> void:
	for roll in [0, 1]:
		var state := _state()
		state.phase = GameTypes.Phase.HAND_PLAY
		var bot: PlayerState = state.players[BOT]
		bot.ability_hand.assign([_ability(&"suit_imprint"), _ability(&"high_roll"), _ability(&"low_roll")])
		var controller := MatchController.new(state)
		var runner := OpeningOnly.new()
		var rolls := Rolls.new([roll, 1, 0])
		runner._rng = rolls
		runner.poll(controller, {BOT: 1}, 10)
		assert_eq(bot.completed_manipulation_ids, [&"low_roll"] if roll == 0 else [])
		assert_eq(bot.ability_hand.size(), 2 if roll == 0 else 3)
		var rolls_after_first_poll := rolls.sizes.size()
		runner.poll(controller, {BOT: 1}, 11)
		assert_eq(rolls.sizes.size(), rolls_after_first_poll)
		runner.close()


func test_overflow_discards_random_manipulations_before_deterministic_ones() -> void:
	var state := _state()
	state.phase = GameTypes.Phase.END
	var bot: PlayerState = state.players[BOT]
	bot.ability_hand.assign([_ability(&"suit_imprint"), _ability(&"mirror_rank"),
		_ability(&"high_roll"), _ability(&"low_roll"), _ability(&"mountain_favor")])
	var runner := Runner.new()
	runner.poll(MatchController.new(state), {BOT: 1}, 10)
	assert_eq(bot.end_discard_copy_ids, [&"mountain_favor", &"high_roll", &"low_roll"])
	runner.close()


func test_main_one_weights_sabotage_by_standings_and_rolls_each_field_once() -> void:
	var state := _state([HOST, BOT, SECOND, LOW], GameTypes.VictoryMode.ROUND_WIN_RACE)
	state.phase = GameTypes.Phase.MAIN_1
	var bot: PlayerState = state.players[BOT]
	state.players[HOST].round_wins = 9
	state.players[SECOND].round_wins = 5
	state.players[LOW].round_wins = 2
	state.players[LOW].match_score = 1000
	bot.ability_hand.assign([
		_ability(&"rank_scramble"), _ability(&"context_nudge"),
		_ability(&"mountain_favor"), _ability(&"sea_favor"), _ability(&"family_buff"),
	])
	var controller := MatchController.new(state)
	var runner := Runner.new()
	var rolls := Rolls.new([5, 0, 0, 3])
	runner._rng = rolls
	var actions := _ability_plays(runner.poll(controller, {BOT: 1}, 10).events)
	assert_eq(actions.map(func(action): return action.target_player_id), [str(SECOND), str(HOST), ""])
	assert_eq(rolls.sizes, [6, 6, 4, 4])
	assert_eq(bot.ability_hand.map(func(card): return card.definition.id), [&"sea_favor", &"family_buff"])
	bot.ready = false
	assert_true(_ability_plays(runner.poll(controller, {BOT: 1}, 11).events).is_empty())
	assert_eq(rolls.sizes, [6, 6, 4, 4])
	runner.close()


func test_top_ranked_bot_targets_the_second_rank_in_a_duel_or_three_player_game() -> void:
	for ids in [[BOT, HOST], [BOT, HOST, LOW]]:
		var state := _state(ids)
		state.phase = GameTypes.Phase.MAIN_1
		var bot: PlayerState = state.players[BOT]
		bot.match_score = 90
		state.players[HOST].match_score = 40
		bot.ability_hand.assign([_ability(&"rank_scramble")])
		var runner := Runner.new()
		var rolls := Rolls.new([1])
		runner._rng = rolls
		var actions := _ability_plays(runner.poll(MatchController.new(state), {BOT: 1}, 10).events)
		assert_eq(actions.map(func(action): return action.target_player_id), [str(HOST)])
		assert_eq(rolls.sizes, [2])
		runner.close()


func test_draws_favor_the_clock_and_contexts_expected_to_appear_more_often() -> void:
	for extra_context in [false, true]:
		var state := _state()
		state.phase = GameTypes.Phase.START
		state.round_number = 2
		state.active_context = FLOURISH
		state.context_direction = GameTypes.ContextDirection.REVERSE
		var bot: PlayerState = state.players[BOT]
		bot.hand.resize(2)
		state.players[HOST].hand.resize(5)
		if extra_context:
			state.ability_deck.play_field(_ability(&"flourish_resonance", HOST), HOST)
		var controller := MatchController.new(state)
		assert_eq(state.active_context, RISE)
		var runner := Runner.new()
		runner.poll(controller, {BOT: 1}, 10)
		var expected := {FLOURISH: 5, RISE: 3} if extra_context else {RISE: 5, FALL: 3}
		assert_eq(state.start_requests.get(BOT, {}), expected)
		assert_true(bot.ready)
		runner.close()


func test_end_discards_fields_then_shape_modifiers_before_manipulation() -> void:
	var state := _state()
	state.phase = GameTypes.Phase.END
	var bot: PlayerState = state.players[BOT]
	bot.ability_hand.assign([
		_ability(&"suit_imprint"), _ability(&"rank_scramble"), _ability(&"mountain_favor"),
		_ability(&"family_buff"), _ability(&"flush_nerf"),
	])
	var runner := Runner.new()
	runner.poll(MatchController.new(state), {BOT: 1}, 10)
	assert_true(bot.end_discard_complete)
	assert_eq(bot.end_discard_copy_ids, [&"mountain_favor", &"family_buff", &"flush_nerf"])
	runner.close()


func test_main_two_nerfs_the_highest_ranked_opponent_whose_revealed_score_drops() -> void:
	var state := _state([HOST, BOT, SECOND, LOW])
	state.phase = GameTypes.Phase.HAND_PLAY
	state.players[HOST].match_score = 250
	state.players[SECOND].match_score = 150
	state.players[LOW].match_score = 80
	var bot: PlayerState = state.players[BOT]
	bot.ability_hand.assign([_ability(&"family_nerf"), _ability(&"high_card_nerf")])
	var controller := MatchController.new(state)
	for id: StringName in state.seat_order:
		var cards := []
		for index in (0 if id == BOT else (1 if id == HOST else 2)):
			var card: FullCardState = state.players[id].hand[index]
			card.first = HalfCardState.new(StringName("%s-face-%d" % [id, index]), RISE, 8, GameTypes.Suit.MOUNTAIN)
			card.second = HalfCardState.new(StringName("%s-back-%d" % [id, index]), FALL, 3, GameTypes.Suit.CLOUD)
			cards.append({"card_id": card.card_id, "half_index": 0, "joker_choices": []})
		assert_true(controller.submit(GameCommand.new(&"stage", id, CommandKinds.STAGE_HAND, {"cards": cards}), 10).accepted)
		assert_true(controller.submit(GameCommand.new(&"lock", id, CommandKinds.LOCK_HAND), 10).accepted)
	assert_eq(state.phase, GameTypes.Phase.MAIN_2)
	var before: int = state.players[SECOND].provisional_score.final_score
	var runner := Runner.new()
	var actions := _ability_plays(runner.poll(controller, {BOT: 1}, 11).events)
	assert_eq(actions.map(func(action): return action.target_player_id), [str(SECOND)])
	assert_eq(before, 20)
	assert_eq(state.players[SECOND].provisional_score.final_score, 16)
	assert_eq(state.players[LOW].provisional_score.final_score, 20)
	assert_eq(bot.ability_hand.map(func(card): return card.definition.id), [&"high_card_nerf"])
	runner.close()


func _state(ids: Array = [HOST, BOT], mode := GameTypes.VictoryMode.SCORE_RACE) -> MatchState:
	var config := MatchConfig.new(ids, [], mode, 1000, GameTypes.InformationVisibility.PUBLIC, {
		GameTypes.Phase.START: 1000, GameTypes.Phase.MAIN_1: 1000,
		GameTypes.Phase.HAND_PLAY: 1000, GameTypes.Phase.MAIN_2: 1000, GameTypes.Phase.END: 1000,
	}, 100, 30000, 30000, AbilityCatalog.build_deck(AbilityCatalog.provisional_deck_recipe()),
		NormalHandCatalog.definitions(), ContextHandCatalog.definitions(), true)
	return MatchState.create(config, 81)


func _ability(id: StringName, owner := BOT) -> AbilityState:
	for definition in AbilityCatalog.all_designs():
		if definition.id == id:
			var card := AbilityState.new(id, definition)
			card.move_to(AbilityState.Zone.HAND, owner)
			return card
	return null


func _ability_plays(events: Array) -> Array:
	return events.filter(func(event): return event.kind == EventKinds.PUBLIC_ABILITY_PLAYED
	).map(func(event): return event.payload)
