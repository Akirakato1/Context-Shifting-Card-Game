class_name MatchScreen
extends Control

const CONTEXT_NAMES := ["A", "B", "C"]
const PHASE_NAMES := ["SETUP", "START", "MAIN 1", "HAND PLAY", "MAIN 2", "END", "COMPLETE"]

var _model: Dictionary = {}

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


func _ready() -> void:
	_top_seat.seat_position = &"top"
	_left_seat.seat_position = &"left"
	_right_seat.seat_position = &"right"
	_bottom_seat.seat_position = &"bottom"


func render(model: Dictionary) -> void:
	_model = model.duplicate(true)
	_render_header()
	_render_context_and_piles()
	_render_fields()
	_render_seats()


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
