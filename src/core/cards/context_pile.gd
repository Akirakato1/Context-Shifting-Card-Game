class_name ContextPile
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const RandomSource = preload("res://src/core/common/random_source.gd")

var context: int
var _draw_cards: Array[HalfCardState] = []
var _used_cards: Array[HalfCardState] = []
var _contained_ids: Dictionary = {}


func _init(pile_context: int, draw_cards: Array) -> void:
	assert(pile_context >= GameTypes.Context.RISE and pile_context <= GameTypes.Context.FALL)
	context = pile_context
	for value in draw_cards:
		var card: HalfCardState = value
		assert(card.base_context == context, "half-card belongs to a different context pile")
		assert(not _contained_ids.has(card.copy_id), "duplicate half-card copy ID")
		_draw_cards.append(card)
		_contained_ids[card.copy_id] = true


func draw(count: int, rng: RandomSource) -> Array[HalfCardState]:
	assert(count >= 0, "draw count cannot be negative")
	var result: Array[HalfCardState] = []
	while result.size() < count:
		if _draw_cards.is_empty():
			if _used_cards.is_empty():
				break
			_draw_cards.assign(rng.shuffle(_used_cards))
			_used_cards.clear()
		var card: HalfCardState = _draw_cards.pop_back()
		_contained_ids.erase(card.copy_id)
		result.append(card)
	return result


func discard(card: HalfCardState) -> void:
	assert(card.base_context == context, "half-card belongs to a different context pile")
	assert(not _contained_ids.has(card.copy_id), "half-card is already in this pile")
	_used_cards.append(card)
	_contained_ids[card.copy_id] = true


func draw_count() -> int:
	return _draw_cards.size()


func used_count() -> int:
	return _used_cards.size()


func snapshot_draw_cards() -> Array[HalfCardState]:
	return _draw_cards.duplicate()


func snapshot_used_cards() -> Array[HalfCardState]:
	return _used_cards.duplicate()
