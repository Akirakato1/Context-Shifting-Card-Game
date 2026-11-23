class_name DomainEvent
extends RefCounted

const GameTypes := preload("res://src/core/common/game_types.gd")

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


static func for_recipient(events: Array, player_id: StringName, role: int) -> Array:
	var projected: Array = []
	for event in events:
		if not event is DomainEvent:
			continue
		if event.audience == &"public" or (
			event.audience == &"player" and role == GameTypes.RecipientRole.ACTIVE_PLAYER
			and event.recipient_id == player_id
		):
			projected.append({"kind": str(event.kind), "payload": event.payload.duplicate(true)})
	return projected
