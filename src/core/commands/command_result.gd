class_name CommandResult
extends RefCounted

const DomainEvent = preload("res://src/core/events/domain_event.gd")

var accepted: bool
var error_code: StringName
var events: Array[DomainEvent]


func _init(
	was_accepted: bool,
	error: StringName = &"",
	result_events: Array[DomainEvent] = []
) -> void:
	accepted = was_accepted
	error_code = error
	events = result_events.duplicate()
