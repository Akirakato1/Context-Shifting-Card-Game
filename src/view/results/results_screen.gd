class_name ResultsScreen
extends Control

signal rematch_requested(payload: Dictionary)
signal return_to_lobby_requested(payload: Dictionary)
signal menu_requested

var _model: Dictionary = {}
var _action_pending := false

@onready var _title: Label = $Layout/Title
@onready var _summary: Label = $Layout/Summary
@onready var _nil_note: Label = $Layout/NilNote
@onready var _standings: VBoxContainer = $Layout/Standings
@onready var _room: Label = $Layout/Room
@onready var _waiting: Label = $Layout/Waiting
@onready var _rematch: Button = $Layout/Actions/RematchButton
@onready var _lobby: Button = $Layout/Actions/LobbyButton
@onready var _menu: Button = $Layout/Actions/MenuButton


func render(model: Dictionary) -> void:
	_model = model.duplicate(true)
	_action_pending = false
	var reason := str(_model.get("end_reason", "victory_target"))
	var winner_id := str(_model.get("winner_id", ""))
	var winner := _player_by_id(winner_id)
	_title.text = "%s WINS" % str(winner.get("name", winner_id)).to_upper() if not winner_id.is_empty() else "MATCH ENDED"
	_summary.text = _summary_text(reason)
	_nil_note.visible = bool(_model.get("last_round_nil", false))
	_nil_note.text = "The previous round was nil; no progress was awarded." if _nil_note.visible else ""
	_render_standings()
	var room_code := str(_model.get("room_code", "------"))
	_room.text = "ROOM %s  ·  occupants stay together for a rematch" % room_code
	var host := bool(_model.get("is_host", false))
	var host_loss := reason == "host_disconnect"
	_rematch.visible = host and not host_loss
	_lobby.visible = host and not host_loss
	_menu.visible = host_loss
	_waiting.visible = not host and not host_loss
	_waiting.text = "Waiting for the host to return everyone to the lobby…" if _waiting.visible else ""


func _render_standings() -> void:
	for child in _standings.get_children():
		_standings.remove_child(child)
		child.queue_free()
	var players: Array = []
	for player in _model.get("players", []):
		if player is Dictionary and not bool(player.get("spectator", false)):
			players.append(player)
	var mode := int(_model.get("victory_mode", 0))
	players.sort_custom(func(a: Dictionary, b: Dictionary):
		var left := int(a.get("round_wins", 0)) if mode == 1 else int(a.get("match_score", 0))
		var right := int(b.get("round_wins", 0)) if mode == 1 else int(b.get("match_score", 0))
		return left > right
	)
	for index in players.size():
		var player: Dictionary = players[index]
		var row := Label.new()
		row.text = "%d   %s   ·   %d score   ·   %d round wins" % [
			index + 1, str(player.get("name", player.get("player_id", "Player"))),
			int(player.get("match_score", 0)), int(player.get("round_wins", 0)),
		]
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_standings.add_child(row)


func _summary_text(reason: String) -> String:
	match reason:
		"last_player_standing":
			return "Won as the last player standing after the other players left."
		"host_disconnect":
			return "The host disconnected, so the match could not continue."
		"forfeit":
			return "The match ended by forfeit."
	var mode := int(_model.get("victory_mode", 0))
	var target := int(_model.get("victory_target", 0))
	return "Won the round-win race to %d." % target if mode == 1 else "Won the score race to %d." % target


func _player_by_id(player_id: String) -> Dictionary:
	for player in _model.get("players", []):
		if player is Dictionary and str(player.get("player_id", "")) == player_id:
			return player
	return {}


func _transition_payload() -> Dictionary:
	var occupant_ids: Array = []
	for player in _model.get("players", []):
		if player is Dictionary:
			occupant_ids.append(str(player.get("player_id", "")))
	return {
		"room_code": str(_model.get("room_code", "")),
		"occupant_ids": occupant_ids,
		"host_settings_unlocked": true,
		"reset_values": {"round_number": 1, "match_scores": 0, "round_wins": 0},
	}


func _on_rematch_pressed() -> void:
	if _action_pending or not _rematch.visible:
		return
	_action_pending = true
	_rematch.disabled = true
	rematch_requested.emit(_transition_payload())


func _on_lobby_pressed() -> void:
	if _action_pending or not _lobby.visible:
		return
	_action_pending = true
	_lobby.disabled = true
	return_to_lobby_requested.emit(_transition_payload())


func _on_menu_pressed() -> void:
	if _action_pending:
		return
	_action_pending = true
	menu_requested.emit()
