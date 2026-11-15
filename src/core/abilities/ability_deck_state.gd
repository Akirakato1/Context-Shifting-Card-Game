class_name AbilityDeckState
extends RefCounted

const RandomSource = preload("res://src/core/common/random_source.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const AbilityState = preload("res://src/core/abilities/ability_state.gd")
const FieldState = preload("res://src/core/abilities/field_state.gd")

var starting_hand_size := 2
var start_draw_count := 1
var end_hand_limit := 3

var _draw_cards: Array[AbilityState] = []
var _used_cards: Array[AbilityState] = []
var _active_fields: Array[FieldState] = []
var _all_cards: Dictionary = {}


func _init(initial_cards: Array) -> void:
	for value in initial_cards:
		var card: AbilityState = value
		assert(not _all_cards.has(card.copy_id), "duplicate ability copy ID")
		card.move_to(AbilityState.Zone.DRAW)
		_draw_cards.append(card)
		_all_cards[card.copy_id] = card


func draw(player_id: StringName, count: int, rng: RandomSource) -> Array[AbilityState]:
	assert(count >= 0, "ability draw count cannot be negative")
	var result: Array[AbilityState] = []
	while result.size() < count:
		if _draw_cards.is_empty():
			if _used_cards.is_empty():
				break
			_draw_cards.assign(rng.shuffle(_used_cards))
			_used_cards.clear()
			for recycled in _draw_cards:
				recycled.move_to(AbilityState.Zone.DRAW)
		var card: AbilityState = _draw_cards.pop_back()
		card.move_to(AbilityState.Zone.HAND, player_id)
		result.append(card)
	return result


func discard(card: AbilityState) -> void:
	assert(
		card.zone == AbilityState.Zone.HAND or card.zone == AbilityState.Zone.ACTIVE_FIELD,
		"only held or active ability cards can enter the used pile"
	)
	card.move_to(AbilityState.Zone.USED)
	_used_cards.append(card)


func play_field(card: AbilityState, source_player_id: StringName) -> Dictionary:
	assert(card.zone == AbilityState.Zone.HAND, "field ability must be in a player hand")
	assert(card.owner_id == source_player_id, "only the owner can play a field ability")
	assert(card.definition.timing == AbilityDefinition.Timing.FIELD)
	var replaced: FieldState = null
	if not card.definition.conflict_group.is_empty():
		for index in range(_active_fields.size() - 1, -1, -1):
			var candidate := _active_fields[index]
			if candidate.conflict_group == card.definition.conflict_group:
				replaced = candidate
				_active_fields.remove_at(index)
				discard(candidate.ability)
				break

	card.move_to(AbilityState.Zone.ACTIVE_FIELD, source_player_id)
	var field := FieldState.new(card, source_player_id)
	_active_fields.append(field)
	return {"field": field, "replaced": replaced}


func tick_fields_end() -> Array[FieldState]:
	var expired: Array[FieldState] = []
	for index in range(_active_fields.size() - 1, -1, -1):
		var field := _active_fields[index]
		if field.tick_end():
			_active_fields.remove_at(index)
			discard(field.ability)
			expired.push_front(field)
	return expired


func handle_source_player_removed(_player_id: StringName) -> void:
	# Fields are global state and deliberately remain until normal expiration.
	pass


func active_fields() -> Array[FieldState]:
	return _active_fields.duplicate()


func draw_count() -> int:
	return _draw_cards.size()


func used_count() -> int:
	return _used_cards.size()


func held_count() -> int:
	var count := 0
	for card: AbilityState in _all_cards.values():
		if card.zone == AbilityState.Zone.HAND:
			count += 1
	return count


func card_by_id(copy_id: StringName) -> AbilityState:
	return _all_cards.get(copy_id)


func to_dict() -> Dictionary:
	var copy_ids: Array = _all_cards.keys()
	copy_ids.sort()
	var cards: Array = []
	for copy_id in copy_ids:
		var card: AbilityState = _all_cards[copy_id]
		cards.append(_serialize_card(card))
	var active: Array = []
	for field in _active_fields:
		active.append({
			"copy_id": str(field.ability.copy_id),
			"source_player_id": str(field.source_player_id),
			"remaining_rounds": field.remaining_rounds,
		})
	return {
		"starting_hand_size": starting_hand_size,
		"start_draw_count": start_draw_count,
		"end_hand_limit": end_hand_limit,
		"cards": cards,
		"draw_order": _copy_ids(_draw_cards),
		"used_order": _copy_ids(_used_cards),
		"active_fields": active,
	}


func load_dict(data: Dictionary) -> void:
	starting_hand_size = data.starting_hand_size
	start_draw_count = data.start_draw_count
	end_hand_limit = data.end_hand_limit
	_draw_cards.clear()
	_used_cards.clear()
	_active_fields.clear()
	_all_cards.clear()
	for card_data: Dictionary in data.cards:
		var definition_data: Dictionary = card_data.definition
		var definition := AbilityDefinition.new(
			StringName(definition_data.id),
			definition_data.timing,
			definition_data.tags.map(func(tag: String) -> StringName: return StringName(tag)),
			StringName(definition_data.effect_id),
			definition_data.field_duration,
			StringName(definition_data.conflict_group)
		)
		var card := AbilityState.new(StringName(card_data.copy_id), definition)
		card.move_to(card_data.zone, StringName(card_data.owner_id))
		_all_cards[card.copy_id] = card
	for copy_id: String in data.draw_order:
		_draw_cards.append(_all_cards[StringName(copy_id)])
	for copy_id: String in data.used_order:
		_used_cards.append(_all_cards[StringName(copy_id)])
	for field_data: Dictionary in data.active_fields:
		var card: AbilityState = _all_cards[StringName(field_data.copy_id)]
		var field := FieldState.new(card, StringName(field_data.source_player_id))
		field.remaining_rounds = field_data.remaining_rounds
		_active_fields.append(field)


func _serialize_card(card: AbilityState) -> Dictionary:
	var serialized_tags: Array = []
	for tag in card.definition.tags:
		serialized_tags.append(str(tag))
	return {
		"copy_id": str(card.copy_id),
		"zone": card.zone,
		"owner_id": str(card.owner_id),
		"definition": {
			"id": str(card.definition.id),
			"timing": card.definition.timing,
			"tags": serialized_tags,
			"effect_id": str(card.definition.effect_id),
			"field_duration": card.definition.field_duration,
			"conflict_group": str(card.definition.conflict_group),
		},
	}


func _copy_ids(cards: Array) -> Array:
	var result: Array = []
	for card: AbilityState in cards:
		result.append(str(card.copy_id))
	return result
