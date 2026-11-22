class_name SabotageResolver
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")

const OPERATIONS := [
	&"exchange_contexts", &"randomize_suit", &"randomize_rank",
	&"randomize_context", &"nudge_rank", &"nudge_context",
	&"swap_halves", &"lock_card",
]


static func validate(definition, player) -> StringName:
	var effect: Dictionary = definition.effect_parameters
	var operation := StringName(str(effect.get("operation", "")))
	if operation not in OPERATIONS:
		return &"unknown_sabotage_operation"
	if player.hand.is_empty():
		return &"invalid_target"
	if operation in [&"exchange_contexts", &"swap_halves"] and player.hand.size() < 2:
		return &"insufficient_target_cards"
	return &""


static func apply(
	definition,
	player,
	rng,
	context_direction: int
) -> Dictionary:
	var effect: Dictionary = definition.effect_parameters
	var operation := StringName(str(effect.operation))
	match operation:
		&"exchange_contexts":
			return _exchange_contexts(player, rng)
		&"randomize_suit", &"randomize_rank", &"randomize_context":
			return _randomize_half(player, rng, operation, effect)
		&"nudge_rank":
			return _nudge_rank(player, rng, effect)
		&"nudge_context":
			return _nudge_context(player, rng, context_direction)
		&"swap_halves":
			return _swap_halves(player, rng)
		&"lock_card":
			return _lock_card(player, rng)
	return {"changed": false}


static func _exchange_contexts(player, rng) -> Dictionary:
	var cards := _pick_distinct_cards(player.hand, 2, rng)
	var changed := false
	for card in cards:
		if card.first.is_joker() or card.second.is_joker():
			continue
		var first_context: int = card.first.effective_context()
		var second_context: int = card.second.effective_context()
		card.first.apply_overrides(
			second_context, card.first.effective_rank(), card.first.effective_suit()
		)
		card.second.apply_overrides(
			first_context, card.second.effective_rank(), card.second.effective_suit()
		)
		changed = changed or first_context != second_context
	return {"changed": changed, "card_ids": cards.map(func(card): return str(card.card_id))}


static func _randomize_half(player, rng, operation: StringName, effect: Dictionary) -> Dictionary:
	var picked := _pick_normal_half(player.hand, rng)
	if picked.is_empty():
		return {"changed": false, "no_eligible_half": true}
	var half = picked.half
	var old_context: int = half.effective_context()
	var old_rank: int = half.effective_rank()
	var old_suit: int = half.effective_suit()
	var context := old_context
	var rank := old_rank
	var suit := old_suit
	if operation == &"randomize_suit":
		suit = GameTypes.Suit.ONE + rng.pick_index(3)
	elif operation == &"randomize_rank":
		var ranks: Array = effect.ranks
		rank = int(ranks[rng.pick_index(ranks.size())])
	else:
		var contexts: Array = effect.contexts
		context = int(contexts[rng.pick_index(contexts.size())])
	half.apply_overrides(context, rank, suit)
	return _half_result(picked, [old_context, old_rank, old_suit] != [context, rank, suit])


static func _nudge_rank(player, rng, effect: Dictionary) -> Dictionary:
	var picked := _pick_normal_half(player.hand, rng)
	if picked.is_empty():
		return {"changed": false, "no_eligible_half": true}
	var half = picked.half
	var old_rank: int = half.effective_rank()
	var direction := -1 if rng.pick_index(2) == 0 else 1
	var minimum := int(effect.get("wrap_min", 1))
	var maximum := int(effect.get("wrap_max", 10))
	var rank := minimum + posmod(old_rank - minimum + direction, maximum - minimum + 1)
	half.apply_overrides(half.effective_context(), rank, half.effective_suit())
	return _half_result(picked, rank != old_rank)


static func _nudge_context(player, rng, context_direction: int) -> Dictionary:
	var picked := _pick_normal_half(player.hand, rng)
	if picked.is_empty():
		return {"changed": false, "no_eligible_half": true}
	var half = picked.half
	var relative := -1 if rng.pick_index(2) == 0 else 1
	var context := posmod(half.effective_context() + context_direction * relative, 3)
	half.apply_overrides(context, half.effective_rank(), half.effective_suit())
	return _half_result(picked, true)


static func _swap_halves(player, rng) -> Dictionary:
	var cards := _pick_distinct_cards(player.hand, 2, rng)
	var first_index: int = rng.pick_index(2)
	var second_index: int = rng.pick_index(2)
	var first_half = cards[0].half_at(first_index)
	var second_half = cards[1].half_at(second_index)
	if first_index == 0: cards[0].first = second_half
	else: cards[0].second = second_half
	if second_index == 0: cards[1].first = first_half
	else: cards[1].second = first_half
	return {"changed": true, "card_ids": cards.map(func(card): return str(card.card_id)),
		"half_indexes": [first_index, second_index]}


static func _lock_card(player, rng) -> Dictionary:
	var card = player.hand[rng.pick_index(player.hand.size())]
	var changed: bool = not player.submission_locked_card_ids.has(card.card_id)
	if changed:
		player.submission_locked_card_ids.append(card.card_id)
	return {"changed": changed, "card_ids": [str(card.card_id)], "locked": true}


static func _pick_distinct_cards(hand: Array, count: int, rng) -> Array:
	var remaining := hand.duplicate()
	var result: Array = []
	for _index in range(count):
		result.append(remaining.pop_at(rng.pick_index(remaining.size())))
	return result


static func _pick_normal_half(hand: Array, rng) -> Dictionary:
	var eligible: Array = []
	for card in hand:
		for half_index in range(2):
			var half = card.half_at(half_index)
			if not half.is_joker():
				eligible.append({"card": card, "card_id": card.card_id,
					"half_index": half_index, "half": half})
	if eligible.is_empty():
		return {}
	return eligible[rng.pick_index(eligible.size())]


static func _half_result(picked: Dictionary, changed: bool) -> Dictionary:
	return {"changed": changed, "card_ids": [str(picked.card_id)],
		"half_indexes": [picked.half_index],
		"effective_context": picked.half.effective_context(),
		"effective_rank": picked.half.effective_rank(),
		"effective_suit": picked.half.effective_suit()}
