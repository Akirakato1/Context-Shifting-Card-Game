extends SceneTree

const WEBRTC_EXTENSION := "res://addons/webrtc_native/webrtc_native.gdextension"
const SignalingClient = preload("res://src/network/signaling_client.gd")
const WebRTCPeerTransport = preload("res://src/network/webrtc_peer_transport.gd")
const ClientNetworkSession = preload("res://src/network/client_network_session.gd")
const ReconnectStore = preload("res://src/network/reconnect_store.gd")

var _signaling_url := ""
var _room_code := ""
var _player_id := ""
var _role := ""
var _mode := ""
var _output_dir := ""
var _stop_file := ""
var _exit_marker := ""
var _transport
var _session
var _store
var _state := "starting"
var _command_accepted := false
var _saw_ready_event := false
var _private_leak := false
var _submitted := false
var _disconnect_started_msec := -1
var _last_error := ""
var _last_status_write_msec := 0


func _initialize() -> void:
	if FileAccess.file_exists(WEBRTC_EXTENSION):
		GDExtensionManager.load_extension(WEBRTC_EXTENSION)
	_signaling_url = _argument("--signaling-url")
	_room_code = _argument("--room-code")
	_player_id = _argument("--player-id")
	_role = _argument("--role")
	_mode = _argument("--mode")
	_output_dir = _argument("--output-dir")
	_exit_marker = _argument("--exit-marker")
	_stop_file = _output_dir.path_join("stop")
	if (
		_signaling_url.is_empty() or _room_code.is_empty() or _player_id.is_empty()
		or _role not in ["active", "spectator"] or _mode not in ["join", "reconnect"]
		or _output_dir.is_empty() or _exit_marker.is_empty()
	):
		_fail("missing client runner arguments")
		return

	_store = ReconnectStore.new(
		"user://integration-reconnect-%s.json" % _player_id
	)
	if _mode == "join":
		_store.clear()
	var signaling := SignalingClient.new()
	_transport = WebRTCPeerTransport.new(signaling, [], Callable(), 15_000)
	_transport.peer_connected.connect(_on_peer_connected)
	_transport.transport_failed.connect(_on_transport_failed)
	_transport.peer_disconnected.connect(_on_peer_disconnected)
	var error: Error = _transport.join_room(
		_signaling_url, _room_code, _role
	)
	if error != OK:
		_fail("join_room failed: %d" % error)
		return
	_write_status()


func _process(_delta: float) -> bool:
	if _transport == null:
		return false
	if FileAccess.file_exists(_stop_file):
		_transport.close()
		_write_status("stopped")
		_write_exit_marker(0)
		_session = null
		_transport = null
		_store = null
		quit(0)
		return true
	if _session != null:
		_session.poll()
	else:
		_transport.poll()

	if (
		_mode == "join" and _player_id == "player-2" and _state == "ready"
		and not _submitted
		and FileAccess.file_exists(_output_dir.path_join("submit-player-2"))
	):
		_submitted = true
		var result: Error = _session.submit_command("integration-ready-message", {
			"command_id": "integration-ready-command",
			"kind": "set_ready",
			"payload": {"ready": true},
		})
		if result != OK:
			_fail("ready command send failed: %d" % result)

	if (
		_mode == "join" and _player_id == "player-2"
		and _disconnect_started_msec < 0
		and FileAccess.file_exists(_output_dir.path_join("disconnect-player-2"))
	):
		_disconnect_started_msec = Time.get_ticks_msec()
		_state = "disconnecting"
		_transport.close()
		_write_status()
	if _disconnect_started_msec >= 0 and Time.get_ticks_msec() - _disconnect_started_msec >= 200:
		_write_exit_marker(0)
		_session = null
		_transport = null
		_store = null
		quit(0)
		return true
	if Time.get_ticks_msec() - _last_status_write_msec >= 50:
		_write_status()
	return false


func _on_peer_connected(peer_id: String) -> void:
	if peer_id != "host":
		return
	_session = ClientNetworkSession.new(
		_transport, "host", "integration-match", StringName(_player_id),
		_store, _room_code
	)
	_session.command_result_received.connect(_on_command_result)
	_session.events_applied.connect(_on_events_applied)
	_session.snapshot_applied.connect(_on_snapshot_applied)
	_session.session_failed.connect(_on_session_failed)
	print("DIRECT_PEER_READY player=%s role=%s" % [_player_id, _role])
	if _mode == "reconnect":
		var record: Dictionary = _store.load_record(
			int(Time.get_unix_time_from_system() * 1000.0)
		)
		if record.is_empty():
			_fail("no valid reconnect record")
			return
		var result: Error = _session.submit_command("integration-reconnect-message", {
			"command_id": "integration-reconnect-command",
			"kind": "reconnect",
			"payload": {"token": record.token},
		})
		if result != OK:
			_fail("reconnect command send failed: %d" % result)


func _on_command_result(request_message_id: String, result: Dictionary) -> void:
	if request_message_id == "integration-ready-message":
		_command_accepted = result.accepted
		if not result.accepted:
			_fail("ready command rejected: %s" % result.error_code)
	elif request_message_id == "integration-reconnect-message" and not result.accepted:
		_fail("reconnect command rejected: %s" % result.error_code)
	_write_status()


func _on_events_applied(events: Array, _sequence: int) -> void:
	for event: Dictionary in events:
		print("DIRECT_GAMEPLAY_EVENT player=%s kind=%s" % [_player_id, event.kind])
		if event.kind == "phase_changed":
			_saw_ready_event = true
	_write_status()


func _on_snapshot_applied(snapshot: Dictionary, _sequence: int) -> void:
	if _role == "spectator":
		for key in snapshot:
			if String(key).begins_with("private_"):
				_private_leak = true
	_state = "reconnected" if _mode == "reconnect" else "ready"
	print("DIRECT_SNAPSHOT_APPLIED player=%s mode=%s" % [_player_id, _mode])
	_write_status()


func _on_session_failed(reason: String) -> void:
	if _disconnect_started_msec >= 0:
		return
	_fail("session failed: %s" % reason)


func _on_transport_failed(reason: String) -> void:
	if _session != null and reason != "direct_connection_failed":
		return
	_fail("transport failed: %s" % reason)


func _on_peer_disconnected(peer_id: String, reason: String) -> void:
	if peer_id == "host" and _disconnect_started_msec < 0:
		_fail("host disconnected: %s" % reason)


func _write_status(state_override: String = "") -> void:
	if _output_dir.is_empty() or _player_id.is_empty():
		return
	_last_status_write_msec = Time.get_ticks_msec()
	var rendered_state := state_override if not state_override.is_empty() else _state
	var file := FileAccess.open(
		_output_dir.path_join("client-%s.json" % _player_id), FileAccess.WRITE
	)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"state": rendered_state,
		"player_id": _player_id,
		"role": _role,
		"command_accepted": _command_accepted,
		"saw_ready_event": _saw_ready_event,
		"private_leak": _private_leak,
		"last_error": _last_error,
	}))
	file.close()


func _fail(reason: String) -> void:
	_last_error = reason
	_state = "failed"
	push_error(reason)
	_write_status()
	if _transport != null:
		_transport.close()
	_write_exit_marker(1)
	quit(1)


func _write_exit_marker(code: int) -> void:
	if _exit_marker.is_empty():
		return
	var file := FileAccess.open(_exit_marker, FileAccess.WRITE)
	if file != null:
		file.store_string(str(code))
		file.close()


func _argument(name: String) -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find(name)
	return String(args[index + 1]) if index >= 0 and index + 1 < args.size() else ""

