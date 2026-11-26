class_name DomainEvent
extends RefCounted

const GameTypes := preload("res://src/core/common/game_types.gd")
const EventKinds := preload("res://src/core/events/event_kinds.gd")
const SpectatorView := preload("res://src/core/match/spectator_view.gd")

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


static func for_recipient(events: Array, player_id: StringName, role: int, watch_actions := false) -> Array:
	var projected: Array = []
	for event in events:
		if not event is DomainEvent:
			continue
		if event.audience == &"public" or (
			event.audience == &"player" and role == GameTypes.RecipientRole.ACTIVE_PLAYER
			and event.recipient_id == player_id
		):
			projected.append({"kind": str(event.kind), "payload": event.payload.duplicate(true)})
		elif watch_actions and role == GameTypes.RecipientRole.SPECTATOR and event.audience == &"player" and (
			event.kind in [EventKinds.MANIPULATION_RESOLVED, EventKinds.SABOTAGE_RESOLVED]
		):
			projected.append({
				"kind": str(event.kind), "observed_player_id": str(event.recipient_id),
				"payload": SpectatorView.action_payload(event.payload),
			})
	return projected
