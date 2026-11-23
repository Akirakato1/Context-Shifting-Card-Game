class_name EffectRegistry
extends RefCounted

const DomainEvent = preload("res://src/core/events/domain_event.gd")
const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const CardFactory = preload("res://src/core/cards/card_factory.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")
const ScoringCategories = preload("res://src/core/scoring/scoring_categories.gd")
const EventKinds = preload("res://src/core/events/event_kinds.gd")
const FieldEffectResolver = preload("res://src/core/abilities/field_effect_resolver.gd")
const SabotageResolver = preload("res://src/core/abilities/sabotage_resolver.gd")

var _handlers: Dictionary = {}


class NoopHandler extends RefCounted:
	func validate(_context: Dictionary) -> StringName:
		return &""

	func apply(_context: Dictionary) -> Array[DomainEvent]:
		return []


class FieldRuleHandler extends RefCounted:
	func validate(context: Dictionary) -> StringName:
		if not context.get("effect") is Dictionary:
			return &"invalid_effect_payload"
		return FieldEffectResolver.validate_rule(context.effect)

	func apply(_context: Dictionary) -> Array[DomainEvent]:
		return []


class ContextJumpHandler extends RefCounted:
	func validate(context: Dictionary) -> StringName:
		var effect: Dictionary = context.effect
		if not effect.has("context") or not effect.context is int:
			return &"invalid_effect_payload"
		if effect.context < GameTypes.Context.RISE or effect.context > GameTypes.Context.FALL:
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


class FactorModifierHandler extends RefCounted:
	func validate(context: Dictionary) -> StringName:
		if not context.state.players.has(context.target_player_id):
			return &"unknown_target"
		var target = context.state.players[context.target_player_id]
		if not target.active or target.pending or target.spectator:
			return &"invalid_target"
		var effect: Dictionary = context.effect
		if not effect.get("factor_id") is StringName and not effect.get("factor_id") is String:
			return &"invalid_effect_payload"
		if not effect.get("category_id") is StringName and not effect.get("category_id") is String:
			return &"invalid_effect_payload"
		var factor_id := StringName(effect.factor_id)
		var category_id := StringName(effect.category_id)
		if not ScoringCategories.category_allowed(factor_id, category_id):
			return &"invalid_factor_category"
		if not effect.get("numerator") is int or not effect.get("denominator") is int:
			return &"invalid_effect_payload"
		if effect.denominator == 0:
			return &"zero_denominator"
		if effect.numerator == 0:
			return &"zero_modifier_delta"
		return &""

	func apply(context: Dictionary) -> Array[DomainEvent]:
		var modifier := ScoringTypes.FactorModifier.new(
			StringName(context.effect.factor_id), StringName(context.effect.category_id),
			Rational.new(context.effect.numerator, context.effect.denominator),
			context.ability.copy_id, context.ability.definition.id
		)
		context.state.players[context.target_player_id].factor_modifiers.append(modifier)
		return [DomainEvent.new(
			EventKinds.FACTOR_MODIFIER_APPLIED,
			{"target_player_id": str(context.target_player_id),
			"source_player_id": str(context.source_player_id),
			"factor_id": str(modifier.factor_id), "category_id": str(modifier.category_id),
			"numerator": modifier.delta.numerator, "denominator": modifier.delta.denominator,
			"source_definition_id": str(modifier.source_definition_id)},
			&"public"
		)]


class ForceRedrawHandler extends RefCounted:
	func validate(context: Dictionary) -> StringName:
		var error := EffectRegistry.validate_sabotage_target(context)
		if not error.is_empty(): return error
		return &"invalid_target" if context.state.players[context.target_player_id].hand.is_empty() else &""

	func apply(context: Dictionary) -> Array[DomainEvent]:
		var state = context.state
		var target = state.players[context.target_player_id]
		var removed_index: int = state.rng.pick_index(target.hand.size())
		var removed: FullCardState = target.hand.pop_at(removed_index)
		var before := removed.face_snapshot()
		target.submission_locked_card_ids.erase(removed.card_id)
		removed.leave_hand()
		state.piles[removed.first.base_context].discard(removed.first)
		state.piles[removed.second.base_context].discard(removed.second)
		var first_context: int = state.rng.pick_index(3)
		var second_context: int = state.rng.pick_index(3)
		var request := {first_context: 1}
		request[second_context] = int(request.get(second_context, 0)) + 1
		var completion := CardFactory.complete_request(request, 2, state.rng)
		var replacement: Array[FullCardState] = CardFactory.draw_replenishment(
			state.piles, completion.request, state.rng, state.allocate_card_id
		)
		target.hand.append_array(replacement)
		var common_payload := {
			"ability_id": str(context.ability.definition.id),
			"source_player_id": str(context.source_player_id),
			"target_player_id": str(context.target_player_id),
		}
		if state.config.information_visibility == GameTypes.InformationVisibility.PUBLIC:
			var public_counts := {}
			for draw_context in completion.request:
				public_counts[str(draw_context)] = completion.request[draw_context]
			common_payload["draw_context_counts"] = public_counts
		return [
			DomainEvent.new(EventKinds.SABOTAGE_RESOLVED, common_payload, &"public"),
			DomainEvent.new(EventKinds.SABOTAGE_RESOLVED, {
				"removed_card_id": str(removed.card_id),
				"replacement_card_ids": replacement.map(func(card: FullCardState): return str(card.card_id)),
				"card_changes": [{"before": before,
					"after": replacement[0].face_snapshot() if not replacement.is_empty() else {}}],
			}.merged(common_payload), &"player", context.target_player_id),
			DomainEvent.new(EventKinds.SABOTAGE_RESOLVED, {
				"ability_id": common_payload.ability_id,
				"source_player_id": common_payload.source_player_id,
				"target_player_id": common_payload.target_player_id, "success": true,
			}, &"player", context.source_player_id),
		]


class SabotageCardsHandler extends RefCounted:
	func validate(context: Dictionary) -> StringName:
		var error := EffectRegistry.validate_sabotage_target(context)
		if not error.is_empty(): return error
		return SabotageResolver.validate(
			context.ability.definition, context.state.players[context.target_player_id]
		)

	func apply(context: Dictionary) -> Array[DomainEvent]:
		var target = context.state.players[context.target_player_id]
		var before := {}
		for card: FullCardState in target.hand:
			before[str(card.card_id)] = card.face_snapshot()
		var detail := SabotageResolver.apply(
			context.ability.definition,
			target,
			context.state.rng,
			context.state.context_direction
		)
		var common := {
			"ability_id": str(context.ability.definition.id),
			"source_player_id": str(context.source_player_id),
			"target_player_id": str(context.target_player_id),
		}
		var target_payload := detail.merged(common)
		var changes: Array = []
		var affected: Array = detail.get("card_ids", [])
		var half_indexes: Array = detail.get("half_indexes", [])
		for card: FullCardState in target.hand:
			var id := str(card.card_id)
			var index := affected.find(id)
			if index >= 0:
				changes.append({"before": before[id], "after": card.face_snapshot(),
					"half_index": int(half_indexes[index]) if index < half_indexes.size() else -1})
		target_payload["card_changes"] = changes
		return [
			DomainEvent.new(EventKinds.SABOTAGE_RESOLVED, common, &"public"),
			DomainEvent.new(EventKinds.SABOTAGE_RESOLVED, target_payload, &"player", context.target_player_id),
			DomainEvent.new(EventKinds.SABOTAGE_RESOLVED, common.merged({"success": true}),
				&"player", context.source_player_id),
		]


func _init() -> void:
	register(&"noop", NoopHandler.new())
	register(&"field_rule", FieldRuleHandler.new())
	register(&"context_jump", ContextJumpHandler.new())
	register(&"reverse_direction", ReverseDirectionHandler.new())
	register(&"factor_modifier", FactorModifierHandler.new())
	register(&"force_redraw", ForceRedrawHandler.new())
	register(&"sabotage_cards", SabotageCardsHandler.new())


static func validate_sabotage_target(context: Dictionary) -> StringName:
	if not context.state.players.has(context.target_player_id):
		return &"unknown_target"
	if context.target_player_id == context.source_player_id:
		return &"target_must_be_opponent"
	var target = context.state.players[context.target_player_id]
	if not target.active or target.pending or target.spectator or not target.connected:
		return &"invalid_target"
	return &""


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
