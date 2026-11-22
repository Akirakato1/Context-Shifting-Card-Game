extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const ContextPile = preload("res://src/core/cards/context_pile.gd")
const RandomSource = preload("res://src/core/common/random_source.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")


func test_joker_has_origin_identity_without_effective_override() -> void:
	var joker := HalfCardState.new(
		&"joker-a", GameTypes.Context.RISE, 0, HalfCardState.NO_SUIT,
		GameTypes.HalfKind.JOKER
	)

	assert_true(joker.is_joker())
	assert_eq(joker.base_context, GameTypes.Context.RISE)
	assert_eq(joker.base_rank, 0)
	assert_eq(joker.base_suit, HalfCardState.NO_SUIT)
	assert_eq(joker.effective_rank(), 0)
	assert_eq(joker.effective_suit(), HalfCardState.NO_SUIT)


func test_joker_is_eligible_in_every_context() -> void:
	var joker := HalfCardState.new(
		&"joker-b", GameTypes.Context.FLOURISH, 0, HalfCardState.NO_SUIT,
		GameTypes.HalfKind.JOKER
	)
	var normal := HalfCardState.new(
		&"normal-b", GameTypes.Context.FLOURISH, 4, GameTypes.Suit.CLOUD
	)
	var card := FullCardState.new(&"card-joker", joker, normal)

	assert_eq(card.half_at(0), joker)
	assert_eq(card.half_at(1), normal)
	assert_eq(card.eligible_half_indexes(GameTypes.Context.RISE), PackedInt32Array([0]))
	assert_eq(card.eligible_half_indexes(GameTypes.Context.FLOURISH), PackedInt32Array([0, 1]))
	assert_eq(card.eligible_half_indexes(GameTypes.Context.FALL), PackedInt32Array([0]))


func test_match_builds_ninety_one_halves_with_one_joker_per_pile() -> void:
	var state := MatchState.create(_config(), 456)
	_assert_complete_joker_distribution(state)

	var restored := MatchState.from_dict(state.to_dict())
	_assert_complete_joker_distribution(restored)
	assert_eq(restored.to_dict(), state.to_dict())


func test_joker_recycles_only_through_its_origin_pile() -> void:
	var joker := HalfCardState.new(
		&"joker-a", GameTypes.Context.RISE, 0, HalfCardState.NO_SUIT,
		GameTypes.HalfKind.JOKER
	)
	var normal := HalfCardState.new(
		&"normal-a", GameTypes.Context.RISE, 7, GameTypes.Suit.CLOUD
	)
	var pile := ContextPile.new(GameTypes.Context.RISE, [normal, joker])
	var rng := RandomSource.new(991)
	var exhausted := pile.draw(2, rng)
	assert_true(exhausted.has(joker))
	assert_eq(pile.draw_count(), 0)

	pile.discard(joker)
	var recycled := pile.draw(1, rng)
	assert_eq(recycled, [joker])
	assert_eq(recycled[0].base_context, GameTypes.Context.RISE)
	assert_true(recycled[0].is_joker())


func _assert_complete_joker_distribution(state: MatchState) -> void:
	var halves: Array = []
	for context in range(GameTypes.Context.RISE, GameTypes.Context.FALL + 1):
		halves.append_array(state.piles[context].snapshot_draw_cards())
		halves.append_array(state.piles[context].snapshot_used_cards())
	for player_id in state.seat_order:
		for card in state.players[player_id].hand:
			halves.append(card.first)
			halves.append(card.second)

	for context in range(GameTypes.Context.RISE, GameTypes.Context.FALL + 1):
		var origin_count := 0
		var joker_count := 0
		for half in halves:
			if half.base_context != context:
				continue
			origin_count += 1
			if half.is_joker():
				joker_count += 1
		assert_eq(origin_count, 91)
		assert_eq(joker_count, 1)


func _config() -> MatchConfig:
	var abilities: Array[AbilityDefinition] = []
	for index in range(12):
		abilities.append(AbilityDefinition.new(
			StringName("ability-%d" % index), AbilityDefinition.Timing.HAND_SHAPE,
			[], &"noop"
		))
	return MatchConfig.new(
		[&"one", &"two"], [], GameTypes.VictoryMode.SCORE_RACE, 100,
		GameTypes.InformationVisibility.PUBLIC,
		{
			GameTypes.Phase.START: 5000,
			GameTypes.Phase.MAIN_1: 5000,
			GameTypes.Phase.HAND_PLAY: 5000,
			GameTypes.Phase.MAIN_2: 5000,
			GameTypes.Phase.END: 2000,
		},
		1000, 5000, 30000, abilities
	)
