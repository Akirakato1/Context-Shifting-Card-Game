extends "res://tests/test_case.gd"

const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const SabotageResolver = preload("res://src/core/abilities/sabotage_resolver.gd")
const GameTypes = preload("res://src/core/common/game_types.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const PlayerState = preload("res://src/core/match/player_state.gd")


class FakeRng extends RefCounted:
	var values: Array[int] = []
	var cursor := 0

	func _init(sequence: Array) -> void:
		for value in sequence: values.append(int(value))

	func pick_index(size: int) -> int:
		assert(size > 0)
		var result := values[cursor] % size
		cursor += 1
		return result


func test_crossed_wires_changes_context_only_and_skips_joker_card() -> void:
	var player := _player()
	player.hand[1].first = HalfCardState.new(
		&"joker", GameTypes.Context.FLOURISH, 0, HalfCardState.NO_SUIT,
		GameTypes.HalfKind.JOKER
	)
	var first = player.hand[0]
	var before := [first.first.effective_rank(), first.first.effective_suit(),
		first.second.effective_rank(), first.second.effective_suit()]
	var result := SabotageResolver.apply(
		_definition(&"crossed_wires"), player, FakeRng.new([0, 0]),
		GameTypes.ContextDirection.FORWARD
	)
	assert_eq(first.first.effective_context(), GameTypes.Context.FLOURISH)
	assert_eq(first.second.effective_context(), GameTypes.Context.RISE)
	assert_eq(before, [first.first.effective_rank(), first.first.effective_suit(),
		first.second.effective_rank(), first.second.effective_suit()])
	assert_eq(result.card_ids.size(), 2)


func test_scrambles_and_nudges_modify_only_selected_effective_property() -> void:
	var cases := [
		[&"suit_scramble", [0, 2], "suit", GameTypes.Suit.SEA],
		[&"rank_scramble", [0, 9], "rank", 10],
		[&"context_scramble", [0, 2], "context", GameTypes.Context.FALL],
	]
	for item in cases:
		var player := _player()
		var half = player.hand[0].first
		var original := [half.effective_context(), half.effective_rank(), half.effective_suit()]
		SabotageResolver.apply(_definition(item[0]), player, FakeRng.new(item[1]), 1)
		if item[2] == "suit": assert_eq(half.effective_suit(), item[3])
		if item[2] == "rank": assert_eq(half.effective_rank(), item[3])
		if item[2] == "context": assert_eq(half.effective_context(), item[3])
		if item[2] != "context": assert_eq(half.effective_context(), original[0])
		if item[2] != "rank": assert_eq(half.effective_rank(), original[1])
		if item[2] != "suit": assert_eq(half.effective_suit(), original[2])

	var nudged := _player()
	nudged.hand[0].first.apply_overrides(GameTypes.Context.RISE, 10, GameTypes.Suit.MOUNTAIN)
	SabotageResolver.apply(_definition(&"rank_nudge"), nudged, FakeRng.new([0, 1]), 1)
	assert_eq(nudged.hand[0].first.effective_rank(), 1)
	SabotageResolver.apply(_definition(&"context_nudge"), nudged, FakeRng.new([0, 0]), -1)
	assert_eq(nudged.hand[0].first.effective_context(), GameTypes.Context.FLOURISH)


func test_loose_pairing_moves_complete_halves_and_lock_is_idempotent() -> void:
	var player := _player()
	var first_half = player.hand[0].first
	var second_half = player.hand[1].second
	first_half.apply_overrides(GameTypes.Context.FALL, 9, GameTypes.Suit.SEA)
	SabotageResolver.apply(
		_definition(&"loose_pairing"), player, FakeRng.new([0, 0, 0, 1]), 1
	)
	assert_true(player.hand[0].first == second_half)
	assert_true(player.hand[1].second == first_half)
	assert_eq(player.hand[1].second.effective_rank(), 9)

	var locked := SabotageResolver.apply(
		_definition(&"momentary_lock"), player, FakeRng.new([0]), 1
	)
	var repeated := SabotageResolver.apply(
		_definition(&"momentary_lock"), player, FakeRng.new([0]), 1
	)
	assert_eq(player.submission_locked_card_ids.size(), 1)
	assert_true(locked.changed)
	assert_false(repeated.changed)


func test_rank_blackout_rerolls_both_halves_of_every_card() -> void:
	var player := _player()
	var result := SabotageResolver.apply(
		_definition(&"rank_blackout"), player, FakeRng.new([9, 8, 7, 6]), 1
	)
	assert_true(result.changed)
	assert_eq(result.card_ids, ["card-a", "card-b"])
	assert_eq(player.hand[0].first.effective_rank(), 10)
	assert_eq(player.hand[0].second.effective_rank(), 9)
	assert_eq(player.hand[1].first.effective_rank(), 8)
	assert_eq(player.hand[1].second.effective_rank(), 7)
	assert_eq(player.hand[1].first.effective_suit(), GameTypes.Suit.SEA)


func _definition(id: StringName):
	for definition in AbilityCatalog.sabotage_designs():
		if definition.id == id: return definition
	assert(false, "missing sabotage definition")
	return null


func _player() -> PlayerState:
	var player := PlayerState.new(&"target", 1)
	player.hand.assign([
		FullCardState.new(&"card-a",
			HalfCardState.new(&"a1", GameTypes.Context.RISE, 1, GameTypes.Suit.MOUNTAIN),
			HalfCardState.new(&"a2", GameTypes.Context.FLOURISH, 2, GameTypes.Suit.CLOUD)),
		FullCardState.new(&"card-b",
			HalfCardState.new(&"b1", GameTypes.Context.FALL, 3, GameTypes.Suit.SEA),
			HalfCardState.new(&"b2", GameTypes.Context.RISE, 4, GameTypes.Suit.MOUNTAIN)),
	])
	return player
