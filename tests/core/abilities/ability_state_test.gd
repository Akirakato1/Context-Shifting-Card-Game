extends "res://tests/test_case.gd"

const GameTypes = preload("res://src/core/common/game_types.gd")
const RandomSource = preload("res://src/core/common/random_source.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const AbilityState = preload("res://src/core/abilities/ability_state.gd")
const AbilityDeckState = preload("res://src/core/abilities/ability_deck_state.gd")
const FieldState = preload("res://src/core/abilities/field_state.gd")
const EffectRegistry = preload("res://src/core/abilities/effect_registry.gd")
const EventKinds = preload("res://src/core/events/event_kinds.gd")
const DomainEvent = preload("res://src/core/events/domain_event.gd")


class FixtureEffectHandler extends RefCounted:
	func validate(context: Dictionary) -> StringName:
		return &"" if context.get("allowed", false) else &"fixture_denied"

	func apply(context: Dictionary) -> Array[DomainEvent]:
		return [DomainEvent.new(
			EventKinds.ABILITY_EFFECT_APPLIED,
			{"value": context.get("value", 0)},
			&"public"
		)]


func test_four_timing_categories_allow_only_their_legal_phases() -> void:
	var manipulation := _definition(&"manipulation", AbilityDefinition.Timing.HAND_MANIPULATION)
	var field := _definition(&"field", AbilityDefinition.Timing.FIELD, 2)
	var hand_shape := _definition(&"hand_shape", AbilityDefinition.Timing.HAND_SHAPE)
	var sabotage := _definition(&"sabotage", AbilityDefinition.Timing.SABOTAGE)

	assert_true(manipulation.allows_phase(GameTypes.Phase.HAND_PLAY))
	assert_false(manipulation.allows_phase(GameTypes.Phase.MAIN_1))
	assert_true(field.allows_phase(GameTypes.Phase.MAIN_1))
	assert_false(field.allows_phase(GameTypes.Phase.MAIN_2))
	assert_true(hand_shape.allows_phase(GameTypes.Phase.MAIN_1))
	assert_true(hand_shape.allows_phase(GameTypes.Phase.MAIN_2))
	assert_true(sabotage.allows_phase(GameTypes.Phase.MAIN_1))
	assert_false(sabotage.allows_phase(GameTypes.Phase.HAND_PLAY))


func test_field_definition_accepts_instant_timed_and_persistent_modes() -> void:
	var instant := _definition(
		&"instant", AbilityDefinition.Timing.FIELD,
		AbilityDefinition.FIELD_DURATION_INSTANT
	)
	var one_round := _definition(&"one-round", AbilityDefinition.Timing.FIELD, 1)
	var three_rounds := _definition(&"three-rounds", AbilityDefinition.Timing.FIELD, 3)
	var persistent := _definition(
		&"persistent", AbilityDefinition.Timing.FIELD,
		AbilityDefinition.FIELD_DURATION_PERSISTENT
	)

	assert_true(instant.is_instant_field())
	assert_false(instant.is_persistent_field())
	assert_false(one_round.is_instant_field())
	assert_false(one_round.is_persistent_field())
	assert_false(three_rounds.is_instant_field())
	assert_false(three_rounds.is_persistent_field())
	assert_false(persistent.is_instant_field())
	assert_true(persistent.is_persistent_field())


func test_persistent_field_never_ticks_and_round_trips() -> void:
	var definition := _definition(
		&"persistent", AbilityDefinition.Timing.FIELD,
		AbilityDefinition.FIELD_DURATION_PERSISTENT
	)
	var card := AbilityState.new(&"persistent-copy", definition)
	var deck := AbilityDeckState.new([card])
	var drawn: Array[AbilityState] = deck.draw(&"owner", 1, RandomSource.new(1))
	var played: FieldState = deck.play_field(drawn[0], &"owner").field

	for _round in range(5):
		assert_eq(deck.tick_fields_end(), [])
		assert_eq(played.remaining_rounds, AbilityDefinition.FIELD_DURATION_PERSISTENT)
	assert_true(played.is_persistent())
	assert_eq(deck.active_fields().size(), 1)
	assert_eq(deck.used_count(), 0)

	var restored := AbilityDeckState.new([])
	restored.load_dict(deck.to_dict())
	var restored_field: FieldState = restored.active_fields()[0]
	assert_true(restored_field.is_persistent())
	assert_eq(
		restored_field.remaining_rounds,
		AbilityDefinition.FIELD_DURATION_PERSISTENT
	)
	assert_eq(restored.tick_fields_end(), [])


func test_shared_deck_recycles_used_cards_and_short_draws_held_cards() -> void:
	var cards: Array[AbilityState] = [
		_state(&"copy-1"), _state(&"copy-2"), _state(&"copy-3"),
	]
	var deck := AbilityDeckState.new(cards)
	var rng := RandomSource.new(55)

	var first_draw: Array[AbilityState] = deck.draw(&"player-1", 2, rng)
	deck.discard(first_draw[0])
	var second_draw: Array[AbilityState] = deck.draw(&"player-2", 2, rng)
	var short_draw: Array[AbilityState] = deck.draw(&"player-3", 1, rng)

	assert_eq(first_draw.size(), 2)
	assert_eq(second_draw.size(), 2, "one draw card plus one recycled card should complete")
	assert_eq(short_draw.size(), 0, "held cards must never be fabricated or recycled")
	assert_eq(deck.draw_count(), 0)
	assert_eq(deck.used_count(), 0)
	assert_eq(deck.held_count(), 3)


func test_deck_exposes_setup_draw_and_end_hand_limit_data() -> void:
	var deck := AbilityDeckState.new([])
	assert_eq(deck.starting_hand_size, 2)
	assert_eq(deck.start_draw_count, 2)
	assert_eq(deck.end_hand_limit, 3)
	var restored := AbilityDeckState.new([])
	restored.load_dict(deck.to_dict())
	assert_eq(restored.starting_hand_size, 2)
	assert_eq(restored.start_draw_count, 2)
	assert_eq(restored.end_hand_limit, 3)


func test_effective_card_change_persists_until_the_full_card_leaves_hand() -> void:
	var first := HalfCardState.new(&"first", GameTypes.Context.RISE, 1, GameTypes.Suit.MOUNTAIN)
	var second := HalfCardState.new(&"second", GameTypes.Context.FLOURISH, 2, GameTypes.Suit.CLOUD)
	var card := FullCardState.new(&"full", first, second)

	first.apply_overrides(GameTypes.Context.FALL, 10, GameTypes.Suit.SEA)
	# Advancing rounds performs no reset; the persistent hand object keeps its effective values.
	assert_eq(first.effective_context(), GameTypes.Context.FALL)
	assert_eq(first.effective_rank(), 10)

	card.leave_hand()
	assert_eq(first.effective_context(), GameTypes.Context.RISE)
	assert_eq(first.effective_rank(), 1)


func test_active_fields_are_not_recycled_until_they_expire() -> void:
	var field_card := AbilityState.new(
		&"field-copy", _definition(&"weather", AbilityDefinition.Timing.FIELD, 2)
	)
	var ordinary := _state(&"ordinary-copy")
	var deck := AbilityDeckState.new([field_card, ordinary])
	var rng := RandomSource.new(4)
	var drawn: Array[AbilityState] = deck.draw(&"owner", 2, rng)
	var selected_field: AbilityState = drawn[0] if drawn[0].copy_id == &"field-copy" else drawn[1]
	var selected_ordinary: AbilityState = drawn[0] if drawn[0].copy_id == &"ordinary-copy" else drawn[1]

	deck.play_field(selected_field, &"owner")
	deck.discard(selected_ordinary)
	var recycled: Array[AbilityState] = deck.draw(&"other", 2, rng)

	assert_eq(recycled.size(), 1)
	assert_eq(recycled[0].copy_id, &"ordinary-copy")
	assert_eq(deck.active_fields().size(), 1)
	assert_eq(deck.used_count(), 0)


func test_unrelated_fields_coexist_and_newest_conflict_replaces_to_used() -> void:
	var rain := AbilityState.new(
		&"rain-copy", _definition(&"rain", AbilityDefinition.Timing.FIELD, 2, &"weather")
	)
	var sun := AbilityState.new(
		&"sun-copy", _definition(&"sun", AbilityDefinition.Timing.FIELD, 3, &"weather")
	)
	var gravity := AbilityState.new(
		&"gravity-copy", _definition(&"gravity", AbilityDefinition.Timing.FIELD, 2, &"gravity")
	)
	var deck := AbilityDeckState.new([rain, sun, gravity])
	var drawn: Array[AbilityState] = deck.draw(&"owner", 3, RandomSource.new(1))
	var by_id := _by_copy_id(drawn)

	deck.play_field(by_id[&"rain-copy"], &"owner")
	deck.play_field(by_id[&"gravity-copy"], &"owner")
	var replacement := deck.play_field(by_id[&"sun-copy"], &"owner")

	assert_eq(deck.active_fields().size(), 2)
	assert_eq(replacement.replaced.ability.copy_id, &"rain-copy")
	assert_eq(replacement.field.ability.copy_id, &"sun-copy")
	assert_eq(replacement.field.remaining_rounds, 3)
	assert_eq(deck.used_count(), 1)
	assert_eq(by_id[&"rain-copy"].zone, AbilityState.Zone.USED)


func test_field_duration_counts_played_round_and_survives_source_removal() -> void:
	var card := AbilityState.new(
		&"persistent-copy", _definition(&"persistent", AbilityDefinition.Timing.FIELD, 2)
	)
	var deck := AbilityDeckState.new([card])
	var drawn: Array[AbilityState] = deck.draw(&"departing", 1, RandomSource.new(1))
	var played: FieldState = deck.play_field(drawn[0], &"departing").field

	deck.handle_source_player_removed(&"departing")
	assert_eq(deck.active_fields().size(), 1)
	assert_eq(played.remaining_rounds, 2)

	var first_expiry: Array = deck.tick_fields_end()
	assert_eq(first_expiry.size(), 0)
	assert_eq(played.remaining_rounds, 1)
	assert_eq(deck.active_fields().size(), 1)

	var second_expiry: Array = deck.tick_fields_end()
	assert_eq(second_expiry.size(), 1)
	assert_eq(deck.active_fields().size(), 0)
	assert_eq(deck.used_count(), 1)
	assert_eq(card.zone, AbilityState.Zone.USED)


func test_effect_registry_validates_and_returns_domain_events() -> void:
	var registry := EffectRegistry.new()
	registry.register(&"fixture", FixtureEffectHandler.new())

	assert_eq(registry.validate(&"missing", {}), &"unknown_effect")
	assert_eq(registry.validate(&"fixture", {"allowed": false}), &"fixture_denied")
	assert_eq(registry.validate(&"fixture", {"allowed": true}), &"")
	var events: Array[DomainEvent] = registry.apply(
		&"fixture", {"allowed": true, "value": 7}
	)
	assert_eq(events.size(), 1)
	assert_eq(events[0].kind, EventKinds.ABILITY_EFFECT_APPLIED)
	assert_eq(events[0].payload.value, 7)
	assert_eq(events[0].audience, &"public")
	assert_eq(
		registry.validate(&"field_rule", {"effect": {
			"field_rule": &"per_selected_suit", "suit": GameTypes.Suit.MOUNTAIN,
			"numerator": 1, "denominator": 10,
		}}),
		&""
	)
	assert_eq(
		registry.apply(&"field_rule", {"effect": {
			"field_rule": &"per_selected_suit", "suit": GameTypes.Suit.MOUNTAIN,
			"numerator": 1, "denominator": 10,
		}}),
		[]
	)
	assert_eq(
		registry.validate(&"field_rule", {"effect": {
			"field_rule": &"per_selected_rank_set", "ranks": [2, 2],
			"numerator": 1, "denominator": 10,
		}}),
		&"invalid_field_ranks"
	)


func _definition(
	id: StringName,
	timing: int,
	duration: int = 0,
	conflict_group: StringName = &""
) -> AbilityDefinition:
	return AbilityDefinition.new(
		id, timing, [&"fixture"], StringName("%s-effect" % id), duration, conflict_group
	)


func _state(copy_id: StringName) -> AbilityState:
	return AbilityState.new(
		copy_id, _definition(&"ordinary", AbilityDefinition.Timing.HAND_SHAPE)
	)


func _by_copy_id(cards: Array[AbilityState]) -> Dictionary:
	var result := {}
	for card in cards:
		result[card.copy_id] = card
	return result
