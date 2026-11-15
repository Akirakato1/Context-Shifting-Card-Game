class_name GameCommand
extends RefCounted

var command_id: StringName
var player_id: StringName
var kind: StringName
var payload: Dictionary


func _init(
	id: StringName,
	sender_player_id: StringName,
	command_kind: StringName,
	command_payload: Dictionary = {}
) -> void:
	command_id = id
	player_id = sender_player_id
	kind = command_kind
	payload = command_payload.duplicate(true)
