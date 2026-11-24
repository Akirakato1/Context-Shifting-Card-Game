class_name ManipulationResolver
extends RefCounted

const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const GameTypes = preload("res://src/core/common/game_types.gd")
const RandomSource = preload("res://src/core/common/random_source.gd")


static func validate(
	definition: AbilityDefinition,
	hand: Array,
	choices: Dictionary
) -> StringName:
	var schema := definition.choice_schema
	var steps: Variant = schema.get("steps", [])
	if not steps is Array or steps.is_empty():
		return &"invalid_choice_schema"
	var expected_keys := {}
	for raw_step in steps:
		if not raw_step is Dictionary:
			return &"invalid_choice_schema"
		var key := str(raw_step.get("key", ""))
		if key.is_empty() or expected_keys.has(key):
			return &"invalid_choice_schema"
		expected_keys[key] = true
	var actual_keys := {}
	for raw_key in choices:
		actual_keys[str(raw_key)] = true
	if actual_keys.size() != expected_keys.size():
		return &"manipulation_choice_keys_mismatch"
	for key in expected_keys:
		if not actual_keys.has(key):
			return &"manipulation_choice_keys_mismatch"

	var cards_by_id := _cards_by_id(hand)
	for raw_step in steps:
		var step: Dictionary = raw_step
		var key := str(step.key)
		var selected: Variant = choices.get(key)
		if not selected is Array:
			return &"malformed_manipulation_choice"
		var count_error := _validate_count(step, selected.size())
		if not count_error.is_empty():
			return count_error
		var value_error := _validate_values(step, selected, cards_by_id)
		if not value_error.is_empty():
			return value_error
	return &""


static func apply(
	definition: AbilityDefinition,
	hand: Array,
	choices: Dictionary,
	rng: RandomSource,
	context_direction: int
) -> void:
	var cards_by_id := _cards_by_id(hand)
	var operation := StringName(definition.effect_parameters.get("operation", &""))
	match operation:
		&"context_exchange":
			var card := _selected_card(cards_by_id, choices.cards[0])
			if card.first.is_joker() or card.second.is_joker():
				return
			var first_context := card.first.effective_context()
			var second_context := card.second.effective_context()
			card.first.apply_overrides(
				second_context, card.first.effective_rank(), card.first.effective_suit()
			)
			card.second.apply_overrides(
				first_context, card.second.effective_rank(), card.second.effective_suit()
			)
		&"context_convergence":
			var card := _selected_card(cards_by_id, choices.cards[0])
			if card.first.is_joker() or card.second.is_joker():
				return
			var target_index: int = choices.half_index[0]
			var target = card.half_at(target_index)
			var source = card.half_at(1 - target_index)
			target.apply_overrides(
				source.effective_context(), target.effective_rank(), target.effective_suit()
			)
		&"suit_imprint":
			var card := _selected_card(cards_by_id, choices.cards[0])
			var suit: int = choices.suit[0]
			for half in [card.first, card.second]:
				if not half.is_joker():
					_set_suit(half, suit)
		&"suit_exchange":
			var first := _selected_half(cards_by_id, choices.halves[0])
			var second := _selected_half(cards_by_id, choices.halves[1])
			var first_suit := first.effective_suit()
			_set_suit(first, second.effective_suit())
			_set_suit(second, first_suit)
		&"shift_suit", &"random_suit":
			var suit_count := GameTypes.Suit.SEA + 1
			for selection: Dictionary in choices.halves:
				var half := _selected_half(cards_by_id, selection)
				var step := 1 if operation == &"shift_suit" else 1 + rng.pick_index(suit_count - 1)
				_set_suit(half, posmod(half.effective_suit() + step, suit_count))
		&"set_context":
			var card := _selected_card(cards_by_id, choices.cards[0])
			var context: int = definition.effect_parameters.context
			for half in [card.first, card.second]:
				if not half.is_joker():
					half.apply_overrides(
						context, half.effective_rank(), half.effective_suit()
					)
		&"random_context":
			for selected_half in choices.halves:
				var card := _selected_card(cards_by_id, selected_half.card_id)
				var half = card.half_at(selected_half.half_index)
				if not half.is_joker():
					half.apply_overrides(
						rng.pick_index(3), half.effective_rank(), half.effective_suit()
					)
		&"random_card_contexts":
			for card_id in choices.cards:
				var card := _selected_card(cards_by_id, card_id)
				for half in [card.first, card.second]:
					if not half.is_joker():
						half.apply_overrides(
							rng.pick_index(3), half.effective_rank(), half.effective_suit()
						)
		&"random_rank":
			var ranks: Array = definition.effect_parameters.ranks
			for card_id in choices.cards:
				var card := _selected_card(cards_by_id, card_id)
				for half in [card.first, card.second]:
					if not half.is_joker():
						var rank: int = ranks[rng.pick_index(ranks.size())]
						half.apply_overrides(
							half.effective_context(), rank, half.effective_suit()
						)
		&"shift_context":
			var relative_direction: int = definition.effect_parameters.relative_direction
			for card_id in choices.cards:
				var card := _selected_card(cards_by_id, card_id)
				for half in [card.first, card.second]:
					if not half.is_joker():
						var shifted_context := posmod(
							half.effective_context()
							+ context_direction * relative_direction,
							3
						)
						half.apply_overrides(
							shifted_context, half.effective_rank(), half.effective_suit()
						)
		&"mirror_rank":
			var card := _selected_card(cards_by_id, choices.cards[0])
			for half in [card.first, card.second]:
				if not half.is_joker():
					half.apply_overrides(
						half.effective_context(), 11 - half.effective_rank(),
						half.effective_suit()
					)


static func _validate_count(step: Dictionary, selected_count: int) -> StringName:
	if step.has("count"):
		if not step.count is int or step.count <= 0:
			return &"invalid_choice_schema"
		return &"" if selected_count == step.count else &"manipulation_choice_count"
	if (
		not step.has("min_count") or not step.min_count is int
		or not step.has("max_count") or not step.max_count is int
		or step.min_count < 0 or step.max_count < step.min_count
	):
		return &"invalid_choice_schema"
	if selected_count < step.min_count or selected_count > step.max_count:
		return &"manipulation_choice_count"
	return &""


static func _validate_values(
	step: Dictionary,
	selected: Array,
	cards_by_id: Dictionary
) -> StringName:
	var kind := str(step.get("kind", ""))
	var seen := {}
	for value in selected:
		match kind:
			"full_card":
				if not _is_identifier(value):
					return &"malformed_manipulation_choice"
				var card_key := str(value)
				if seen.has(card_key):
					return &"duplicate_manipulation_target"
				seen[card_key] = true
				if not cards_by_id.has(card_key):
					return &"card_not_in_hand"
			"half_card":
				if not value is Dictionary or not _has_exact_half_keys(value):
					return &"malformed_manipulation_choice"
				if not _is_identifier(value.card_id):
					return &"malformed_manipulation_choice"
				if not value.half_index is int:
					return &"malformed_manipulation_choice"
				if value.half_index < 0 or value.half_index > 1:
					return &"invalid_half_index"
				var card_key := str(value.card_id)
				var half_key := "%s:%d" % [card_key, value.half_index]
				if seen.has(half_key):
					return &"duplicate_manipulation_target"
				seen[half_key] = true
				if not cards_by_id.has(card_key):
					return &"card_not_in_hand"
				if bool(step.get("ordinary_only", false)) and _selected_half(cards_by_id, value).is_joker():
					return &"invalid_manipulation_choice"
			"half_index":
				if not value is int:
					return &"malformed_manipulation_choice"
				if value < 0 or value > 1:
					return &"invalid_half_index"
				if seen.has(value):
					return &"duplicate_manipulation_target"
				seen[value] = true
			"suit", "context", "rank":
				if not value is int:
					return &"malformed_manipulation_choice"
				if seen.has(value):
					return &"duplicate_manipulation_target"
				seen[value] = true
			_:
				return &"invalid_choice_schema"
		var eligible: Variant = step.get("eligible", [])
		if not eligible is Array:
			return &"invalid_choice_schema"
		if not eligible.is_empty() and value not in eligible:
			return &"invalid_manipulation_choice"
	return &""


static func _has_exact_half_keys(value: Dictionary) -> bool:
	if value.size() != 2:
		return false
	var keys := {}
	for raw_key in value:
		keys[str(raw_key)] = true
	return keys.has("card_id") and keys.has("half_index")


static func _cards_by_id(hand: Array) -> Dictionary:
	var result := {}
	for card in hand:
		result[str(card.card_id)] = card
	return result


static func _selected_card(cards_by_id: Dictionary, card_id: Variant) -> FullCardState:
	return cards_by_id[str(card_id)]


static func _selected_half(cards_by_id: Dictionary, selection: Dictionary) -> HalfCardState:
	return _selected_card(cards_by_id, selection.card_id).half_at(selection.half_index)


static func _set_suit(half: HalfCardState, suit: int) -> void:
	half.apply_overrides(half.effective_context(), half.effective_rank(), suit)


static func _is_identifier(value: Variant) -> bool:
	return value is String or value is StringName
