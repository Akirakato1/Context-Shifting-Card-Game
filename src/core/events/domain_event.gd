class_name DomainEvent
extends RefCounted

var kind: StringName
var payload: Dictionary
var audience: StringName
var recipient_id: StringName


func _init(
	event_kind: StringName,
	event_payload: Dictionary = {},
	event_audience: StringName = &"public",
	event_recipient_id: StringName = &""
) -> void:
	kind = event_kind
	payload = event_payload.duplicate(true)
	audience = event_audience
	recipient_id = event_recipient_id
