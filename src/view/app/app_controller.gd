class_name AppController
extends Control

signal presentation_changed(state: Dictionary, sequence: int)
signal connection_changed(state: Dictionary)
signal screen_requested(screen_id: StringName, payload: Dictionary)
signal host_requested(player_name: String)
signal join_requested(player_name: String, room_code: String, role: String)
signal lobby_intent_requested(kind: StringName, payload: Dictionary)
signal game_intent_requested(kind: StringName, payload: Dictionary)
signal rematch_requested(payload: Dictionary)

const PresentationState = preload("res://src/view/common/presentation_state.gd")
const PresentationQueue = preload("res://src/view/common/presentation_queue.gd")
const UICommandGateway = preload("res://src/view/common/ui_command_gateway.gd")
const MAIN_MENU_SCENE := preload("res://src/view/lobby/main_menu_screen.tscn")
const LOBBY_SCENE := preload("res://src/view/lobby/lobby_screen.tscn")
const MATCH_SCENE := preload("res://src/view/match/match_screen.tscn")
const RESULTS_SCENE := preload("res://src/view/results/results_screen.tscn")

var presentation_state: PresentationState
var presentation_queue: PresentationQueue
var command_gateway: UICommandGateway
var _session: Variant
var _connection := {"status": "idle", "reason": ""}
var _current_screen_id: StringName = &""
var _current_screen: Node
var _last_presentation: Dictionary = {}

@onready var _screen_host: Control = $SafeArea/ScreenHost


func _ready() -> void:
	show_screen(&"menu")


func _init() -> void:
	presentation_state = PresentationState.new()
	presentation_queue = PresentationQueue.new()
	command_gateway = UICommandGateway.new()
	presentation_state.changed.connect(_on_presentation_changed)
	presentation_queue.event_ready.connect(_on_event_ready)


func bind_session(session: Variant) -> void:
	_session = session
	command_gateway.bind_session(session)
	if session == null:
		_set_connection("idle", "")
		return
	_connect_if_present(session, "snapshot_applied", _on_snapshot_applied)
	_connect_if_present(session, "events_applied", _on_events_applied)
	_connect_if_present(session, "command_result_received", _on_command_result)
	_connect_if_present(session, "session_failed", _on_session_failed)
	_connect_if_present(session, "connection_state_changed", _on_connection_state_changed)
	_set_connection("connected", "")


func advance_presentation(delta_msec: int) -> void:
	presentation_queue.tick(delta_msec)


func connection_state() -> Dictionary:
	return _connection.duplicate(true)


func request_screen(screen_id: StringName, payload: Dictionary = {}) -> void:
	show_screen(screen_id, payload)
	screen_requested.emit(screen_id, payload.duplicate(true))


func current_screen_id() -> StringName:
	return _current_screen_id


func show_screen(screen_id: StringName, model: Dictionary = {}) -> void:
	for child in _screen_host.get_children():
		_screen_host.remove_child(child)
		child.queue_free()
	var scene: PackedScene
	match screen_id:
		&"menu": scene = MAIN_MENU_SCENE
		&"lobby": scene = LOBBY_SCENE
		&"match": scene = MATCH_SCENE
		&"results": scene = RESULTS_SCENE
		_: return
	_current_screen_id = screen_id
	_current_screen = scene.instantiate()
	_screen_host.add_child(_current_screen)
	if _current_screen is Control:
		_current_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wire_current_screen()
	if not model.is_empty() and _current_screen.has_method("render"):
		_current_screen.render(model)


func present_state(state: Dictionary) -> void:
	_last_presentation = state.duplicate(true)
	if bool(state.get("match_complete", false)):
		show_screen(&"results", state)
	elif _current_screen_id == &"match":
		_current_screen.render(state)


func _process(delta: float) -> void:
	if _session != null and _session.has_method("poll"):
		_session.poll()
	advance_presentation(int(delta * 1000.0))


func _on_snapshot_applied(snapshot: Dictionary, sequence: int) -> void:
	presentation_queue.cancel_before_sequence(sequence + 1)
	presentation_state.apply_snapshot(snapshot, sequence)


func _on_events_applied(events: Array, sequence: int) -> void:
	var queued: Array[Dictionary] = []
	for event in events:
		if event is Dictionary:
			var item: Dictionary = event.duplicate(true)
			item["sequence"] = sequence
			queued.append(item)
	presentation_queue.enqueue(queued)


func _on_event_ready(event: Dictionary) -> void:
	presentation_state.apply_event(event, int(event.get("sequence", presentation_state.sequence())))


func _on_command_result(_request_message_id: String, _result: Dictionary) -> void:
	pass


func _on_session_failed(reason: String) -> void:
	command_gateway.set_input_locked(true)
	presentation_queue.skip_to_latest()
	_set_connection("failed", reason)


func _on_connection_state_changed(value: Variant) -> void:
	if value is Dictionary:
		_connection = value.duplicate(true)
		connection_changed.emit(_connection.duplicate(true))
	else:
		_set_connection(str(value), "")


func _on_presentation_changed(state: Dictionary, sequence: int) -> void:
	present_state(state)
	presentation_changed.emit(state.duplicate(true), sequence)


func _wire_current_screen() -> void:
	match _current_screen_id:
		&"menu":
			_current_screen.host_requested.connect(func(player_name: String): host_requested.emit(player_name))
			_current_screen.join_requested.connect(func(player_name: String, code: String, role: String): join_requested.emit(player_name, code, role))
		&"lobby":
			_current_screen.setting_change_requested.connect(func(key: StringName, value: Variant): lobby_intent_requested.emit(&"setting", {"key": key, "value": value}))
			_current_screen.ready_requested.connect(func(ready: bool): lobby_intent_requested.emit(&"ready", {"ready": ready}))
			_current_screen.start_requested.connect(func(): lobby_intent_requested.emit(&"start", {}))
			_current_screen.leave_requested.connect(func(): show_screen(&"menu"))
		&"match":
			_current_screen.intent_requested.connect(_on_match_intent)
			_current_screen.connection_action_requested.connect(_on_connection_action)
		&"results":
			_current_screen.rematch_requested.connect(_on_rematch_requested)
			_current_screen.return_to_lobby_requested.connect(_on_return_to_lobby_requested)
			_current_screen.menu_requested.connect(func(): show_screen(&"menu"))


func _on_match_intent(kind: StringName, payload: Dictionary) -> void:
	game_intent_requested.emit(kind, payload.duplicate(true))
	if _session != null:
		command_gateway.send(kind, payload)


func _on_connection_action(action: StringName) -> void:
	if action == &"menu":
		show_screen(&"menu")
	elif action == &"lobby":
		show_screen(&"lobby", _lobby_from_result({}))


func _on_rematch_requested(payload: Dictionary) -> void:
	rematch_requested.emit(payload.duplicate(true))
	show_screen(&"lobby", _lobby_from_result(payload))


func _on_return_to_lobby_requested(payload: Dictionary) -> void:
	show_screen(&"lobby", _lobby_from_result(payload))


func _lobby_from_result(payload: Dictionary) -> Dictionary:
	var rows: Array = []
	var active_count := 0
	var spectator_count := 0
	for player in _last_presentation.get("players", []):
		if not player is Dictionary:
			continue
		var spectator := bool(player.get("spectator", false))
		if spectator: spectator_count += 1
		else: active_count += 1
		rows.append({
			"name": str(player.get("name", player.get("player_id", "Player"))),
			"role": "spectator" if spectator else "active", "ready": false,
		})
	var settings: Dictionary = _last_presentation.get("lobby_settings", {}).duplicate(true)
	if settings.is_empty():
		settings = {
			"victory_mode": int(_last_presentation.get("victory_mode", 0)),
			"victory_target": int(_last_presentation.get("victory_target", 10)),
			"information_visibility": 0, "start_timer_msec": 5000,
			"main_timer_msec": 10000, "hand_timer_msec": 30000,
			"end_timer_msec": 5000, "reconnect_grace_msec": 30000,
		}
	return {
		"is_host": bool(_last_presentation.get("is_host", true)),
		"room_code": str(payload.get("room_code", _last_presentation.get("room_code", "------"))),
		"match_started": false, "active_player_count": active_count,
		"spectator_count": spectator_count, "players": rows, "settings": settings,
		"connection": {"status": "connected", "reason": ""},
	}


func _set_connection(status: String, reason: String) -> void:
	_connection = {"status": status, "reason": reason}
	connection_changed.emit(_connection.duplicate(true))


func _connect_if_present(target: Variant, signal_name: String, callable: Callable) -> void:
	if target.has_signal(signal_name):
		var signal_value: Signal = target.get(signal_name)
		if not signal_value.is_connected(callable):
			signal_value.connect(callable)
