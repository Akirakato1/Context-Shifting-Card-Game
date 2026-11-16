class_name MatchScreen
extends Control

signal intent_requested(kind: StringName, payload: Dictionary)
signal connection_action_requested(action: StringName)

const CONTEXT_NAMES := ["A", "B", "C"]
const PHASE_NAMES := ["SETUP", "START", "MAIN 1", "HAND PLAY", "MAIN 2", "END", "COMPLETE"]

var _model: Dictionary = {}
var _active_ability: Dictionary = {}
var _active_copy_id: StringName = &""
var _connection_action: StringName = &""

@onready var _phase: Label = $Header/Phase
@onready var _round: Label = $Header/Round
@onready var _timer: Label = $Header/Timer
@onready var _progress: Label = $Header/Progress
@onready var _spectators: Label = $Header/Spectators
@onready var _top_seat = $TableLayer/TopSeat
@onready var _left_seat = $TableLayer/LeftSeat
@onready var _right_seat = $TableLayer/RightSeat
@onready var _bottom_seat = $TableLayer/BottomSeat
@onready var _clock_direction: Label = $Center/ContextClock/Direction
@onready var _clock_active: Label = $Center/ContextClock/Active
@onready var _field_rows: VBoxContainer = $Center/Fields/FieldRows
@onready var _round_result: Label = $Center/RoundResult
@onready var _phase_controls = $PhaseControls
@onready var _ability_panel = $AbilityPanel
@onready var _targeting_overlay = $TargetingOverlay
@onready var _ability_history: VBoxContainer = $AbilityHistory/Rows
@onready var _connection_overlay: Control = $ConnectionOverlay
@onready var _connection_message: Label = $ConnectionOverlay/Panel/Layout/Message
@onready var _connection_action_button: Button = $ConnectionOverlay/Panel/Layout/ActionButton


func _ready() -> void:
	_top_seat.seat_position = &"top"
	_left_seat.seat_position = &"left"
	_right_seat.seat_position = &"right"
	_bottom_seat.seat_position = &"bottom"
	if not _phase_controls.intent_requested.is_connected(_on_phase_intent_requested):
		_phase_controls.intent_requested.connect(_on_phase_intent_requested)
	_phase_controls.card_target_requested.connect(_targeting_overlay.select_value)
	_ability_panel.ability_activated.connect(_on_ability_activated)
	_targeting_overlay.commit_requested.connect(_on_targeting_commit_requested)
	_targeting_overlay.closed.connect(_on_targeting_closed)
	_targeting_overlay.selection_changed.connect(_on_targeting_selection_changed)


func render(model: Dictionary) -> void:
	_model = model.duplicate(true)
	_render_header()
	_render_context_and_piles()
	_render_fields()
	_render_seats()
	_render_phase_controls()
	_render_abilities()
	_render_connection_state()


func handle_command_result(
	kind: StringName,
	accepted: bool,
	error_code: StringName,
	authoritative_phase: int
) -> void:
	_phase_controls.handle_command_result(kind, accepted, error_code, authoritative_phase)
	if kind == &"stage_manipulation" and not accepted and _targeting_overlay.visible:
		_targeting_overlay.cancel(&"rejected")


func _render_header() -> void:
	var phase_index := int(_model.get("phase", 0))
	_phase.text = PHASE_NAMES[phase_index] if phase_index >= 0 and phase_index < PHASE_NAMES.size() else "UNKNOWN"
	_round.text = "ROUND %d" % int(_model.get("round_number", 0))
	var remaining: int = maxi(0, int(_model.get("phase_deadline_msec", 0)) - int(_model.get("now_msec", Time.get_ticks_msec())))
	_timer.text = "%.1fs" % (remaining / 1000.0)
	var spectator_count := 0
	for player in _model.get("players", []):
		if player is Dictionary and bool(player.get("spectator", false)):
			spectator_count += 1
	_spectators.text = "SPECTATORS  %d / 4" % spectator_count
	var progress_player := _progress_player()
	var victory_mode := int(_model.get("victory_mode", _lobby_setting("victory_mode", 0)))
	var target := int(_model.get("victory_target", _lobby_setting("victory_target", 10)))
	if victory_mode == 1:
		_progress.text = "ROUND-WIN RACE  ·  %d / %d" % [int(progress_player.get("round_wins", 0)), target]
	else:
		_progress.text = "SCORE RACE  ·  %d / %d" % [int(progress_player.get("match_score", 0)), target]


func _render_context_and_piles() -> void:
	var active_context := int(_model.get("active_context", 0))
	var direction := int(_model.get("context_direction", 1))
	_clock_direction.text = "A  →  B  →  C" if direction >= 0 else "C  ←  B  ←  A"
	_clock_active.text = "ACTIVE  %s" % _context_name(active_context)
	var counts: Dictionary = _model.get("pile_counts", {})
	for context in 3:
		var pile = get_node("Center/Piles/Pile%s" % _context_name(context))
		var count_label: Label = pile.get_node("Count")
		var data: Dictionary = counts.get(str(context), counts.get(context, {}))
		count_label.text = "%d left" % int(data.get("draw_count", 0)) if not data.is_empty() else "Hidden"
	_round_result.visible = bool(_model.get("last_round_nil", false))
	_round_result.text = "NIL ROUND  ·  no progress awarded" if _round_result.visible else ""


func _render_fields() -> void:
	for child in _field_rows.get_children():
		_field_rows.remove_child(child)
		child.queue_free()
	for field in _model.get("active_fields", []):
		if not field is Dictionary:
			continue
		var row := Label.new()
		row.text = "%s  ·  %d round%s  ·  by %s" % [
			str(field.get("ability_id", "field")).replace("_", " ").capitalize(),
			int(field.get("remaining_rounds", 0)),
			"" if int(field.get("remaining_rounds", 0)) == 1 else "s",
			str(field.get("source_player_id", "?")),
		]
		_field_rows.add_child(row)


func _render_seats() -> void:
	var active_players: Array = []
	for player in _model.get("players", []):
		if player is Dictionary and not bool(player.get("spectator", false)):
			active_players.append(player)
	active_players.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("seat_index", 0)) < int(b.get("seat_index", 0)))
	var private_id := str(_model.get("private_player_id", ""))
	var local_player: Dictionary = {}
	var opponents: Array = []
	for player in active_players:
		if not private_id.is_empty() and str(player.get("player_id", "")) == private_id:
			local_player = player
		else:
			opponents.append(player)
	if local_player.is_empty() and not active_players.is_empty():
		local_player = active_players[0]
		opponents = active_players.slice(1)
	var requests: Dictionary = _model.get("replacement_requests", {})
	_bottom_seat.render(
		local_player, _model.get("private_hand", []), int(_model.get("active_context", 0)),
		not private_id.is_empty() and str(local_player.get("player_id", "")) == private_id,
		_request_for(requests, local_player), not private_id.is_empty()
	)
	var opponent_seats := [_top_seat, _left_seat, _right_seat]
	for index in opponent_seats.size():
		var player: Dictionary = opponents[index] if index < opponents.size() else {}
		opponent_seats[index].render(
			player, [], int(_model.get("active_context", 0)), false,
			_request_for(requests, player)
		)


func _render_phase_controls() -> void:
	var has_private_player := not str(_model.get("private_player_id", "")).is_empty()
	_phase_controls.visible = has_private_player
	if not has_private_player:
		return
	_phase_controls.render(_model)
	_phase_controls.set_inputs_locked(bool(_model.get("frozen", false)))
	_bottom_seat.get_node("Hand").visible = int(_model.get("phase", 0)) != 3


func _render_abilities() -> void:
	var has_private_player := not str(_model.get("private_player_id", "")).is_empty()
	_ability_panel.visible = has_private_player
	if has_private_player:
		_ability_panel.render(
			_model.get("private_abilities", []), int(_model.get("phase", 0)),
			_model.get("ability_catalog", {}), bool(_model.get("frozen", false))
		)
	_render_ability_history()
	if _targeting_overlay.visible and not _active_ability_still_legal():
		_targeting_overlay.cancel(&"interrupted")


func _render_ability_history() -> void:
	for child in _ability_history.get_children():
		_ability_history.remove_child(child)
		child.queue_free()
	for event in _model.get("recent_public_abilities", []):
		if not event is Dictionary:
			continue
		var row := Label.new()
		var source := str(event.get("source_player_id", "?"))
		var target := str(event.get("target_player_id", ""))
		row.text = "%s  ·  %s%s" % [
			str(event.get("ability_id", "ability")).replace("_", " ").capitalize(),
			source,
			(" → " + target) if not target.is_empty() else "",
		]
		_ability_history.add_child(row)
	$AbilityHistory.visible = _ability_history.get_child_count() > 0


func _render_connection_state() -> void:
	var connection: Dictionary = _model.get("connection_state", {})
	var status := str(connection.get("status", "connected"))
	if bool(_model.get("frozen", false)) or status == "reconnecting":
		var remaining := maxi(
			int(connection.get("deadline_msec", 0)) - int(connection.get("now_msec", _model.get("now_msec", 0))), 0
		)
		_connection_overlay.visible = true
		_connection_message.text = "Match paused while a player reconnects  ·  %.1fs remaining" % (remaining / 1000.0)
		_connection_action_button.visible = false
	elif status == "connected":
		_connection_overlay.visible = false
		_connection_action_button.visible = true


func show_connection_failure(reason: StringName) -> void:
	var states := {
		&"forfeit": ["You forfeited this match.", "RETURN TO LOBBY", &"lobby"],
		&"host_lost": ["The host connection was lost. This match cannot continue.", "RETURN TO MENU", &"menu"],
		&"direct_connection_failed": ["A direct connection could not be established.", "TRY AGAIN", &"retry"],
		&"room_closed": ["This room was closed by the host.", "RETURN TO MENU", &"menu"],
	}
	var state: Array = states.get(reason, ["The match connection ended.", "RETURN TO MENU", &"menu"])
	_connection_overlay.visible = true
	_connection_message.text = state[0]
	_connection_action_button.text = state[1]
	_connection_action_button.visible = true
	_connection_action = state[2]
	_phase_controls.set_inputs_locked(true)


func _on_ability_activated(copy_id: StringName, ability: Dictionary) -> void:
	_active_copy_id = copy_id
	_active_ability = ability.duplicate(true)
	var timing := int(ability.get("timing", -1))
	var workflow: Dictionary = ability.get("choice_schema", {})
	if timing == 0:
		intent_requested.emit(&"stage_manipulation", {"copy_id": str(copy_id)})
		_targeting_overlay.begin(workflow)
	elif workflow.get("steps", []).is_empty():
		intent_requested.emit(&"play_public_ability", {"copy_id": str(copy_id), "target_player_id": ""})
		_clear_active_ability()
	else:
		_targeting_overlay.begin(workflow)


func _on_targeting_commit_requested(choices: Dictionary) -> void:
	var timing := int(_active_ability.get("timing", -1))
	if timing == 0:
		intent_requested.emit(&"commit_manipulation", {
			"card_id": str(_single_choice(choices, "card_id", "")),
			"half_index": int(_single_choice(choices, "half_index", 0)),
			"context": int(_single_choice(choices, "context", 0)),
			"rank": int(_single_choice(choices, "rank", 1)),
			"suit": int(_single_choice(choices, "suit", 0)),
		})
	else:
		intent_requested.emit(&"play_public_ability", {
			"copy_id": str(_active_copy_id),
			"target_player_id": str(_single_choice(choices, "target_player_id", "")),
		})


func _on_targeting_selection_changed(kind: StringName, eligible: Array, selected: Array) -> void:
	if kind == &"card":
		_phase_controls.set_targeting(eligible, selected)
	else:
		_phase_controls.clear_targeting()


func _on_targeting_closed(reason: StringName) -> void:
	_phase_controls.clear_targeting()
	if reason == &"cancelled" and int(_active_ability.get("timing", -1)) == 0:
		intent_requested.emit(&"cancel_manipulation", {})
	_clear_active_ability()


func _on_connection_action_pressed() -> void:
	connection_action_requested.emit(_connection_action)


func _active_ability_still_legal() -> bool:
	var timing := int(_active_ability.get("timing", -1))
	var phase := int(_model.get("phase", 0))
	var timing_allowed := (
		(timing == 0 and phase == 3) or (timing in [1, 3] and phase == 2)
		or (timing == 2 and phase in [2, 4])
	)
	if not timing_allowed:
		return false
	for ability in _model.get("private_abilities", []):
		if ability is Dictionary and StringName(ability.get("copy_id", "")) == _active_copy_id:
			return true
	return false


func _single_choice(choices: Dictionary, key: String, fallback: Variant) -> Variant:
	var values: Array = choices.get(key, [])
	return values[0] if not values.is_empty() else fallback


func _clear_active_ability() -> void:
	_active_copy_id = &""
	_active_ability.clear()


func _on_phase_intent_requested(kind: StringName, payload: Dictionary) -> void:
	intent_requested.emit(kind, payload.duplicate(true))


func _request_for(requests: Dictionary, player: Dictionary) -> Dictionary:
	if player.is_empty():
		return {}
	var request: Variant = requests.get(str(player.get("player_id", "")), {})
	return request if request is Dictionary else {}


func _progress_player() -> Dictionary:
	var private_id := str(_model.get("private_player_id", ""))
	var first_active: Dictionary = {}
	for player in _model.get("players", []):
		if not player is Dictionary or bool(player.get("spectator", false)):
			continue
		if first_active.is_empty():
			first_active = player
		if str(player.get("player_id", "")) == private_id:
			return player
	return first_active


func _lobby_setting(key: String, fallback: Variant) -> Variant:
	var settings: Dictionary = _model.get("lobby_settings", {})
	return settings.get(key, fallback)


func _context_name(index: int) -> String:
	return CONTEXT_NAMES[index] if index >= 0 and index < CONTEXT_NAMES.size() else "?"
