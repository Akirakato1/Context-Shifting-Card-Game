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
const RuntimeGameSession = preload("res://src/view/app/runtime_game_session.gd")
const PracticeGameSession = preload("res://src/view/app/practice_game_session.gd")
const DisplayPreferences = preload("res://src/view/app/display_preferences.gd")
const GameplayPreferences = preload("res://src/view/app/gameplay_preferences.gd")
const CursorArtwork = preload("res://src/view/app/cursor_artwork.gd")
const GameTypes = preload("res://src/core/common/game_types.gd")
const MAIN_MENU_SCENE := preload("res://src/view/lobby/main_menu_screen.tscn")
const GENERAL_SETTINGS_SCENE := preload("res://src/view/lobby/general_settings_screen.tscn")
const LOBBY_SCENE := preload("res://src/view/lobby/lobby_screen.tscn")
const MATCH_SCENE := preload("res://src/view/match/match_screen.tscn")
const RESULTS_SCENE := preload("res://src/view/results/results_screen.tscn")
const WEBRTC_EXTENSION_PATH := "res://addons/webrtc_native/webrtc_native.gdextension"
const STARTUP_SMOKE_PREFIX := "--startup-smoke="

var presentation_state: PresentationState
var presentation_queue: PresentationQueue
var command_gateway: UICommandGateway
var gameplay_preferences := GameplayPreferences.new()
@export var cursor_artwork: CursorArtwork
var _session: Variant
var _connection := {"status": "idle", "reason": ""}
var _current_screen_id: StringName = &""
var _current_screen: Node
var _last_presentation: Dictionary = {}
var _settings_overlay: Control
var _settings_previous_focus: WeakRef
var _player_name := ""

@onready var _screen_host: Control = $SafeArea/ScreenHost
@onready var _connection_banner: PanelContainer = $SafeArea/ConnectionBanner
@onready var _connection_banner_label: Label = $SafeArea/ConnectionBanner/Label


func _ready() -> void:
	DisplayPreferences.apply(get_window(), DisplayPreferences.load_mode())
	if cursor_artwork != null:
		cursor_artwork.apply()
	gameplay_preferences.apply_audio()
	gameplay_preferences.draw_speed_changed.connect(_apply_draw_speed)
	show_screen(&"menu")
	for argument in OS.get_cmdline_user_args():
		if argument == "--practice":
			start_practice()
			return
		if argument.begins_with(STARTUP_SMOKE_PREFIX):
			show_screen(&"lobby")
			var marker_path := argument.trim_prefix(STARTUP_SMOKE_PREFIX)
			var result := write_startup_smoke_marker(marker_path)
			get_tree().quit(0 if result == OK else 1)
			return


func _init() -> void:
	presentation_state = PresentationState.new()
	presentation_queue = PresentationQueue.new()
	command_gateway = UICommandGateway.new()
	presentation_state.changed.connect(_on_presentation_changed)
	presentation_queue.event_ready.connect(_on_event_ready)
	command_gateway.command_completed.connect(_on_command_result)
	command_gateway.command_blocked.connect(_on_command_blocked)


func bind_session(session: Variant) -> void:
	if _session != null and _session != session:
		_disconnect_if_present(_session, "snapshot_applied", _on_snapshot_applied)
		_disconnect_if_present(_session, "events_applied", _on_events_applied)
		_disconnect_if_present(_session, "session_failed", _on_session_failed)
		_disconnect_if_present(_session, "connection_state_changed", _on_connection_state_changed)
	_session = session
	command_gateway.bind_session(session)
	command_gateway.set_input_locked(false)
	if session == null:
		_set_connection("idle", "")
		return
	_connect_if_present(session, "snapshot_applied", _on_snapshot_applied)
	_connect_if_present(session, "events_applied", _on_events_applied)
	_connect_if_present(session, "session_failed", _on_session_failed)
	_connect_if_present(session, "connection_state_changed", _on_connection_state_changed)
	_set_connection("connected", "")


func advance_presentation(delta_msec: int) -> void:
	presentation_queue.tick(delta_msec)


func connection_state() -> Dictionary:
	return _connection.duplicate(true)


func write_startup_smoke_marker(marker_path: String) -> int:
	if marker_path.is_empty():
		return ERR_INVALID_PARAMETER
	if FileAccess.file_exists(WEBRTC_EXTENSION_PATH) and not GDExtensionManager.is_extension_loaded(WEBRTC_EXTENSION_PATH):
		var load_result := GDExtensionManager.load_extension(WEBRTC_EXTENSION_PATH)
		if load_result != OK:
			return int(load_result)
	var peer := WebRTCPeerConnection.new()
	var initialize_result := peer.initialize({"iceServers": []})
	if initialize_result != OK:
		return initialize_result
	peer.close()
	var marker := FileAccess.open(marker_path, FileAccess.WRITE)
	if marker == null:
		return FileAccess.get_open_error()
	marker.store_string("startup_ok\nwebrtc_ok\n")
	marker.close()
	return OK


func request_screen(screen_id: StringName, payload: Dictionary = {}) -> void:
	show_screen(screen_id, payload)
	screen_requested.emit(screen_id, payload.duplicate(true))


func current_screen_id() -> StringName:
	return _current_screen_id


func show_screen(screen_id: StringName, model: Dictionary = {}) -> void:
	var scene: PackedScene
	match screen_id:
		&"menu", &"create_lobby", &"join_lobby": scene = MAIN_MENU_SCENE
		&"lobby": scene = LOBBY_SCENE
		&"match": scene = MATCH_SCENE
		&"results": scene = RESULTS_SCENE
		_: return
	_close_general_settings()
	if is_instance_valid(_current_screen):
		_screen_host.remove_child(_current_screen)
		_current_screen.queue_free()
	_current_screen_id = screen_id
	_current_screen = scene.instantiate()
	_screen_host.add_child(_current_screen)
	if _current_screen is Control:
		_current_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _current_screen.has_method("set_page"):
		_current_screen.set_page(screen_id, _player_name)
	_wire_current_screen()
	if not model.is_empty() and _current_screen.has_method("render"):
		_current_screen.render(model)


func present_state(state: Dictionary) -> void:
	_last_presentation = state.duplicate(true)
	if state.is_empty():
		return
	var requested_screen := StringName(state.get("screen_id", ""))
	if int(state.get("phase", -1)) == GameTypes.Phase.COMPLETE:
		requested_screen = &"results"
	if requested_screen in [&"lobby", &"match", &"results"] and requested_screen != _current_screen_id:
		show_screen(requested_screen, state)
	elif _current_screen != null and _current_screen.has_method("render"):
		_current_screen.render(state)


func _process(delta: float) -> void:
	if _session != null and _session.has_method("poll"):
		_session.poll()
	advance_presentation(int(delta * 1000.0))


func _input(event: InputEvent) -> void:
	if (
		_current_screen_id not in [&"match", &"lobby"] or not is_instance_valid(_current_screen)
		or is_instance_valid(_settings_overlay) or not event is InputEventKey or not event.pressed
	):
		return
	var action := gameplay_preferences.hotkey_action(event.get_keycode_with_modifiers())
	if action.is_empty():
		return
	var handled: bool
	if _current_screen_id == &"match":
		handled = _current_screen.handle_match_hotkey(action, event.echo)
	elif action == GameplayPreferences.HOTKEY_READY and not event.echo:
		handled = _current_screen.trigger_ready_shortcut()
	if handled:
		get_viewport().set_input_as_handled()


func _on_snapshot_applied(snapshot: Dictionary, sequence: int) -> void:
	presentation_queue.cancel_before_sequence(sequence + 1)
	presentation_state.apply_snapshot(snapshot, sequence)


func _on_events_applied(events: Array, sequence: int) -> void:
	# Live cues are consumed before the authoritative snapshot clears its event batch.
	if _current_screen_id == &"match" and sequence > presentation_state.sequence():
		_current_screen.present_ability_events(events)
	var queued: Array[Dictionary] = []
	for event in events:
		if event is Dictionary:
			var payload: Variant = event.get("payload", {})
			if event.get("kind") == "manipulation_resolved" or (
				event.get("kind") == "sabotage_resolved" and payload is Dictionary
				and payload.has("card_changes")
			):
				continue
			var item: Dictionary = event.duplicate(true)
			item["sequence"] = sequence
			queued.append(item)
	presentation_queue.enqueue(queued)


func _on_event_ready(event: Dictionary) -> void:
	presentation_state.apply_event(event, int(event.get("sequence", presentation_state.sequence())))


func _on_command_result(
	kind: StringName,
	_request_message_id: String,
	result: Dictionary
) -> void:
	if _current_screen_id != &"match" or not _current_screen.has_method("handle_command_result"):
		return
	_current_screen.handle_command_result(
		kind,
		bool(result.get("accepted", false)),
		StringName(result.get("error_code", "")),
		int(_last_presentation.get("phase", -1))
	)


func _on_command_blocked(kind: StringName, reason: StringName) -> void:
	if reason != &"duplicate_in_flight":
		_on_command_result(kind, "", {"accepted": false, "error_code": reason})


func _on_session_failed(reason: String) -> void:
	command_gateway.set_input_locked(true)
	presentation_queue.skip_to_latest()
	_set_connection("failed", reason)
	if _current_screen_id in [&"menu", &"create_lobby", &"join_lobby"]:
		_current_screen.show_error(_connection_error_message(reason))
	elif _current_screen_id == &"lobby" and _current_screen.has_method("show_error"):
		_current_screen.show_error(StringName(reason))
	elif _current_screen_id == &"match" and _current_screen.has_method("show_connection_failure"):
		_current_screen.show_connection_failure(StringName(reason))


func _on_connection_state_changed(value: Variant) -> void:
	if value is Dictionary:
		_connection = value.duplicate(true)
		if str(_connection.get("status", "")) == "connected":
			command_gateway.set_input_locked(false)
		_render_connection_banner()
		connection_changed.emit(_connection.duplicate(true))
	else:
		_set_connection(str(value), "")


func _on_presentation_changed(state: Dictionary, sequence: int) -> void:
	present_state(state)
	presentation_changed.emit(state.duplicate(true), sequence)


func _wire_current_screen() -> void:
	match _current_screen_id:
		&"menu", &"create_lobby", &"join_lobby":
			_current_screen.host_requested.connect(_begin_host_runtime)
			_current_screen.join_requested.connect(_begin_join_runtime)
			_current_screen.screen_requested.connect(_on_menu_screen_requested)
			_current_screen.settings_requested.connect(_open_general_settings)
			_current_screen.practice_requested.connect(start_practice)
		&"lobby":
			_current_screen.setting_change_requested.connect(func(key: StringName, value: Variant): _on_lobby_intent(&"setting", {"key": key, "value": value}))
			_current_screen.ready_requested.connect(func(ready: bool): _on_lobby_intent(&"ready", {"ready": ready}))
			_current_screen.start_requested.connect(func(): _on_lobby_intent(&"start", {}))
			_current_screen.leave_requested.connect(_return_to_menu)
			_current_screen.retry_requested.connect(func(): _on_connection_action(&"retry"))
		&"match":
			_current_screen.set_draw_speed(gameplay_preferences.draw_speed)
			_current_screen.intent_requested.connect(_on_match_intent)
			_current_screen.connection_action_requested.connect(_on_connection_action)
			_connect_if_present(_current_screen, "settings_requested", _open_general_settings)
			_connect_if_present(_current_screen, "leave_requested", _return_to_menu)
		&"results":
			_current_screen.rematch_requested.connect(_on_rematch_requested)
			_current_screen.return_to_lobby_requested.connect(_on_return_to_lobby_requested)
			_current_screen.menu_requested.connect(_return_to_menu)


func _on_menu_screen_requested(screen_id: StringName) -> void:
	if not _current_screen.player_name().is_empty():
		_player_name = _current_screen.player_name()
	if screen_id == &"menu":
		_return_to_menu()
	else:
		request_screen(screen_id)


func _open_general_settings() -> void:
	if is_instance_valid(_settings_overlay):
		return
	var previous_focus := get_viewport().gui_get_focus_owner()
	_settings_previous_focus = weakref(previous_focus) if previous_focus != null else null
	_settings_overlay = GENERAL_SETTINGS_SCENE.instantiate()
	_settings_overlay.preferences = gameplay_preferences
	_settings_overlay.back_requested.connect(_close_general_settings)
	_screen_host.add_child(_settings_overlay)


func _apply_draw_speed(speed: int) -> void:
	if _current_screen_id == &"match" and is_instance_valid(_current_screen):
		_current_screen.set_draw_speed(speed)


func _close_general_settings() -> void:
	if not is_instance_valid(_settings_overlay):
		return
	_screen_host.remove_child(_settings_overlay)
	_settings_overlay.queue_free()
	_settings_overlay = null
	var previous_focus: Control = _settings_previous_focus.get_ref() if _settings_previous_focus != null else null
	_settings_previous_focus = null
	if is_instance_valid(previous_focus) and previous_focus.is_visible_in_tree():
		previous_focus.grab_focus()


func start_practice() -> void:
	_close_current_session()
	bind_session(PracticeGameSession.new())
	_session.start()


func _begin_host_runtime(player_name: String) -> void:
	_player_name = player_name
	host_requested.emit(player_name)
	_replace_runtime_session()
	var error: Error = _session.start_host(_signaling_url(), player_name)
	if error != OK:
		_set_connection("idle", "")
		_show_current_error("Could not start the room service (%d)." % error)


func _begin_join_runtime(player_name: String, room_code: String, role: String) -> void:
	_player_name = player_name
	join_requested.emit(player_name, room_code, role)
	_replace_runtime_session()
	var error: Error = _session.start_join(
		_signaling_url(), room_code, role, player_name
	)
	if error != OK:
		_set_connection("idle", "")
		_show_current_error("Could not contact that room (%d)." % error)


func _replace_runtime_session() -> void:
	_close_current_session()
	bind_session(RuntimeGameSession.new())


func _on_lobby_intent(kind: StringName, payload: Dictionary) -> void:
	lobby_intent_requested.emit(kind, payload.duplicate(true))
	if _session == null:
		return
	match kind:
		&"setting":
			if not _session.has_method("update_lobby_setting"):
				return
			var error: StringName = _session.update_lobby_setting(
				StringName(payload.get("key", "")), payload.get("value")
			)
			if not error.is_empty() and _current_screen.has_method("show_error"):
				_current_screen.show_error(error)
		&"ready":
			command_gateway.send(&"set_ready", {"ready": bool(payload.get("ready", false))})
		&"start":
			if not _session.has_method("start_match"):
				return
			var result: Error = _session.start_match()
			if result != OK:
				if _current_screen.has_method("show_error"):
					_current_screen.show_error(&"not_enough_players")
				return


func _return_to_menu() -> void:
	_close_current_session()
	show_screen(&"menu")


func _close_current_session() -> void:
	var previous_session: Variant = _session
	bind_session(null)
	if previous_session != null and previous_session.has_method("close"):
		previous_session.close()
	presentation_queue.clear()
	presentation_state.clear()


func _signaling_url() -> String:
	var environment_url := OS.get_environment("SHIFT_SIGNALING_URL").strip_edges()
	if not environment_url.is_empty():
		return environment_url
	return str(ProjectSettings.get_setting(
		"shift/network/signaling_url", "ws://127.0.0.1:8080"
	)).strip_edges()


func _show_current_error(message: String) -> void:
	if _current_screen != null and _current_screen.has_method("show_error"):
		_current_screen.show_error(message)


func _connection_error_message(reason: String) -> String:
	var messages := {
		"room_not_found": "That room was not found. Check the code and try again.",
		"signaling_timeout": "The room service did not respond. Try again.",
		"active_capacity_reached": "The player seats are full. Try joining as a spectator.",
		"spectator_capacity_reached": "The spectator seats are full.",
		"direct_connection_failed": "The direct and relay routes could not establish a connection on this network.",
		"relay_unavailable": "A direct route could not be established, and relay fallback was unavailable.",
	}
	return messages.get(reason, "The room connection failed. Please try again.")


func _on_match_intent(kind: StringName, payload: Dictionary) -> void:
	game_intent_requested.emit(kind, payload.duplicate(true))
	if _session != null:
		command_gateway.send(kind, payload)


func _on_connection_action(action: StringName) -> void:
	if action == &"menu":
		_return_to_menu()
	elif action == &"lobby":
		show_screen(&"lobby", _lobby_from_result({}))
	elif action == &"retry" and _session != null and _session.has_method("retry_connection"):
		var error: Error = _session.retry_connection()
		if error != OK:
			_return_to_menu()


func _on_rematch_requested(payload: Dictionary) -> void:
	rematch_requested.emit(payload.duplicate(true))
	if bool(payload.get("is_practice", false)):
		start_practice()
	elif _session == null or not _session.has_method("start_rematch") or _session.start_rematch() != OK:
		_show_current_error("Could not start a rematch. Try again.")


func _on_return_to_lobby_requested(payload: Dictionary) -> void:
	if _session != null and _session.has_method("reset_for_rematch"):
		var result: Error = _session.reset_for_rematch()
		if result != OK:
			_show_current_error("Could not return to the lobby. Try again.")
		return
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
	_render_connection_banner()
	connection_changed.emit(_connection.duplicate(true))


func _render_connection_banner() -> void:
	if not is_node_ready():
		return
	var status := str(_connection.get("status", "idle"))
	_connection_banner.visible = status in ["connecting", "reconnecting", "failed"]
	match status:
		"connecting": _connection_banner_label.text = "Connecting to the room service…"
		"reconnecting": _connection_banner_label.text = "Restoring the room connection…"
		"failed": _connection_banner_label.text = _connection_error_message(
			str(_connection.get("reason", "unknown"))
		)


func _connect_if_present(target: Variant, signal_name: String, callable: Callable) -> void:
	if target.has_signal(signal_name):
		var signal_value: Signal = target.get(signal_name)
		if not signal_value.is_connected(callable):
			signal_value.connect(callable)


func _disconnect_if_present(target: Variant, signal_name: String, callable: Callable) -> void:
	if target.has_signal(signal_name):
		var signal_value: Signal = target.get(signal_name)
		if signal_value.is_connected(callable):
			signal_value.disconnect(callable)
