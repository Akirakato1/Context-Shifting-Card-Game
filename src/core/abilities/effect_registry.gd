class_name EffectRegistry
extends RefCounted

const DomainEvent = preload("res://src/core/events/domain_event.gd")

var _handlers: Dictionary = {}


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
