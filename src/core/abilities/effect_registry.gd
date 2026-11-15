class_name EffectRegistry
extends RefCounted

const DomainEvent = preload("res://src/core/events/domain_event.gd")
const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const CardFactory = preload("res://src/core/cards/card_factory.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")
const EventKinds = preload("res://src/core/events/event_kinds.gd")

var _handlers: Dictionary = {}


class NoopHandler extends RefCounted:
	func validate(_context: Dictionary) -> StringName:
		return &""

	func apply(_context: Dictionary) -> Array[DomainEvent]:
		return []


class ContextJumpHandler extends RefCounted:
	func validate(context: Dictionary) -> StringName:
		var effect: Dictionary = context.effect
		if not effect.has("context") or not effect.context is int:
			return &"invalid_effect_payload"
		if effect.context < GameTypes.Context.A or effect.context > GameTypes.Context.C:
			return &"invalid_context"
		return &""

	func apply(context: Dictionary) -> Array[DomainEvent]:
		context.state.active_context = context.effect.context
		return [DomainEvent.new(
			EventKinds.CONTEXT_CHANGED, {"context": context.effect.context}, &"public"
		)]


class ReverseDirectionHandler extends RefCounted:
	func validate(_context: Dictionary) -> StringName:
		return &""

	func apply(context: Dictionary) -> Array[DomainEvent]:
		context.state.context_direction *= -1
		return [DomainEvent.new(
			EventKinds.CONTEXT_DIRECTION_CHANGED,
			{"direction": context.state.context_direction}, &"public"
		)]


class ScoreModifierHandler extends RefCounted:
	func validate(context: Dictionary) -> StringName:
		if not context.state.players.has(context.target_player_id):
			return &"unknown_target"
		var target = context.state.players[context.target_player_id]
		if not target.active:
			return &"invalid_target"
		var effect: Dictionary = context.effect
		if not effect.has("operation") or effect.operation not in [&"add", &"multiply"]:
			return &"invalid_modifier_operation"
		if not effect.get("numerator") is int or not effect.get("denominator") is int:
			return &"invalid_effect_payload"
		if effect.denominator == 0:
			return &"zero_denominator"
		return &""

	func apply(context: Dictionary) -> Array[DomainEvent]:
		var modifier := ScoringTypes.ScoreModifier.new(
			context.effect.operation,
			Rational.new(context.effect.numerator, context.effect.denominator),
			context.ability.copy_id
		)
		context.state.players[context.target_player_id].score_modifiers.append(modifier)
		return [DomainEvent.new(
			EventKinds.SCORE_MODIFIER_APPLIED,
			{"target_player_id": str(context.target_player_id), "operation": str(modifier.operation),
			"numerator": modifier.value.numerator, "denominator": modifier.value.denominator},
			&"public"
		)]


class ForceRedrawHandler extends RefCounted:
	func validate(context: Dictionary) -> StringName:
		if not context.state.players.has(context.target_player_id):
			return &"unknown_target"
		if context.target_player_id == context.source_player_id:
			return &"target_must_be_opponent"
		var target = context.state.players[context.target_player_id]
		if not target.active or target.hand.is_empty():
			return &"invalid_target"
		return &""

	func apply(context: Dictionary) -> Array[DomainEvent]:
		var state = context.state
		var target = state.players[context.target_player_id]
		var removed_index: int = state.rng.pick_index(target.hand.size())
		var removed: FullCardState = target.hand.pop_at(removed_index)
		removed.leave_hand()
		state.piles[removed.first.base_context].discard(removed.first)
		state.piles[removed.second.base_context].discard(removed.second)
		var completion := CardFactory.complete_request({}, 2, state.rng)
		var replacement: Array[FullCardState] = CardFactory.draw_replenishment(
			state.piles, completion.request, state.rng, state.allocate_card_id
		)
		target.hand.append_array(replacement)
		var common_payload := {
			"ability_id": str(context.ability.definition.id),
			"target_player_id": str(context.target_player_id),
		}
		return [
			DomainEvent.new(EventKinds.SABOTAGE_RESOLVED, common_payload, &"public"),
			DomainEvent.new(EventKinds.SABOTAGE_RESOLVED, {
				"ability_id": common_payload.ability_id,
				"removed_card_id": str(removed.card_id),
				"replacement_card_ids": replacement.map(func(card: FullCardState): return str(card.card_id)),
			}, &"player", context.target_player_id),
			DomainEvent.new(EventKinds.SABOTAGE_RESOLVED, {
				"ability_id": common_payload.ability_id, "target_player_id": common_payload.target_player_id,
				"success": true,
			}, &"player", context.source_player_id),
		]


func _init() -> void:
	register(&"noop", NoopHandler.new())
	register(&"context_jump", ContextJumpHandler.new())
	register(&"reverse_direction", ReverseDirectionHandler.new())
	register(&"score_modifier", ScoreModifierHandler.new())
	register(&"force_redraw", ForceRedrawHandler.new())


func register(effect_id: StringName, handler: RefCounted) -> void:
	assert(not effect_id.is_empty(), "effect ID cannot be empty")
	assert(not _handlers.has(effect_id), "effect ID is already registered")
	assert(handler.has_method("validate") and handler.has_method("apply"))
	_handlers[effect_id] = handler


func validate(effect_id: StringName, context: Dictionary) -> StringName:
	if not _handlers.has(effect_id):
		return &"unknown_effect"
	var handler: RefCounted = _handlers[effect_id]
	var result: StringName = handler.call("validate", context)
	return result


func apply(effect_id: StringName, context: Dictionary) -> Array[DomainEvent]:
	if not _handlers.has(effect_id):
		return []
	var handler: RefCounted = _handlers[effect_id]
	var raw_result: Variant = handler.call("apply", context)
	var result: Array[DomainEvent] = []
	result.assign(raw_result)
	return result
