class_name CardFactory
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const RandomSource = preload("res://src/core/common/random_source.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const ContextPile = preload("res://src/core/cards/context_pile.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")

const CONTEXT_DRAW_CAP := 5


static func build_opening_hand(
	piles: Dictionary,
	rng: RandomSource,
	card_id_provider: Callable = Callable()
) -> Array[FullCardState]:
	if not _has_all_piles(piles):
		return []
	var by_context := {}
	for context in range(GameTypes.Context.A, GameTypes.Context.C + 1):
		var pile: ContextPile = piles[context]
		var drawn: Array[HalfCardState] = pile.draw(4, rng)
		if drawn.size() != 4:
			return []
		by_context[context] = rng.shuffle(drawn)

	var cards: Array[FullCardState] = []
	for index in range(2):
		cards.append(_pair(by_context[GameTypes.Context.A][index], by_context[GameTypes.Context.B][index], _card_id(card_id_provider, cards.size())))
		cards.append(_pair(by_context[GameTypes.Context.A][index + 2], by_context[GameTypes.Context.C][index], _card_id(card_id_provider, cards.size())))
		cards.append(_pair(by_context[GameTypes.Context.B][index + 2], by_context[GameTypes.Context.C][index + 2], _card_id(card_id_provider, cards.size())))
	var shuffled_cards: Array[FullCardState] = []
	shuffled_cards.assign(rng.shuffle(cards))
	return shuffled_cards


static func draw_replenishment(
	piles: Dictionary,
	request: Dictionary,
	rng: RandomSource,
	card_id_provider: Callable = Callable()
) -> Array[FullCardState]:
	if not _has_all_piles(piles) or not _validate_request_values(request).is_empty():
		return []
	var total := _request_total(request)
	if total <= 0 or total % 2 != 0:
		return []

	var halves: Array[HalfCardState] = []
	for context in range(GameTypes.Context.A, GameTypes.Context.C + 1):
		var count: int = request.get(context, 0)
		var pile: ContextPile = piles[context]
		var drawn: Array[HalfCardState] = pile.draw(count, rng)
		if drawn.size() != count:
			return []
		halves.append_array(drawn)

	var shuffled_halves: Array[HalfCardState] = []
	shuffled_halves.assign(rng.shuffle(halves))
	var cards: Array[FullCardState] = []
	for index in range(0, shuffled_halves.size(), 2):
		cards.append(_pair(
			shuffled_halves[index], shuffled_halves[index + 1],
			_card_id(card_id_provider, cards.size())
		))
	return cards


static func complete_request(
	partial: Dictionary,
	needed_halves: int,
	rng: RandomSource
) -> Dictionary:
	if needed_halves < 0:
		return _request_error(&"negative_needed_half_count")
	if needed_halves % 2 != 0:
		return _request_error(&"odd_needed_half_count")
	var validation_error := _validate_request_values(partial)
	if not validation_error.is_empty():
		return _request_error(validation_error)

	var completed := {
		GameTypes.Context.A: 0,
		GameTypes.Context.B: 0,
		GameTypes.Context.C: 0,
	}
	for context in partial:
		completed[context] = partial[context]
	var total := _request_total(completed)
	if total > needed_halves:
		return _request_error(&"request_exceeds_needed_halves")
	if needed_halves > CONTEXT_DRAW_CAP * 3:
		return _request_error(&"request_exceeds_total_cap")

	while total < needed_halves:
		var candidates: Array[int] = []
		for context in range(GameTypes.Context.A, GameTypes.Context.C + 1):
			if not partial.has(context) and completed[context] < CONTEXT_DRAW_CAP:
				candidates.append(context)
		if candidates.is_empty():
			for context in range(GameTypes.Context.A, GameTypes.Context.C + 1):
				if completed[context] < CONTEXT_DRAW_CAP:
					candidates.append(context)
		if candidates.is_empty():
			return _request_error(&"request_exceeds_total_cap")
		var selected := candidates[rng.pick_index(candidates.size())]
		completed[selected] += 1
		total += 1

	return {"ok": true, "error": &"", "request": completed}


static func _pair(
	first: HalfCardState,
	second: HalfCardState,
	card_id: StringName
) -> FullCardState:
	return FullCardState.new(card_id, first, second)


static func _card_id(provider: Callable, local_index: int) -> StringName:
	if provider.is_valid():
		var provided: Variant = provider.call()
		assert(provided is StringName or provided is String)
		return StringName(provided)
	return StringName("card-%03d" % local_index)


static func _has_all_piles(piles: Dictionary) -> bool:
	for context in range(GameTypes.Context.A, GameTypes.Context.C + 1):
		if not piles.has(context) or not piles[context] is ContextPile:
			return false
	return true


static func _validate_request_values(request: Dictionary) -> StringName:
	for context in request:
		if not context is int or context < GameTypes.Context.A or context > GameTypes.Context.C:
			return &"unknown_context"
		var count: Variant = request[context]
		if not count is int:
			return &"invalid_context_count"
		if count < 0:
			return &"negative_context_count"
		if count > CONTEXT_DRAW_CAP:
			return &"context_count_exceeds_cap"
	return &""


static func _request_total(request: Dictionary) -> int:
	var total := 0
	for count: int in request.values():
		total += count
	return total


static func _request_error(error: StringName) -> Dictionary:
	return {"ok": false, "error": error, "request": {}}
