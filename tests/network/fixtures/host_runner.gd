extends SceneTree

const WEBRTC_EXTENSION := "res://addons/webrtc_native/webrtc_native.gdextension"
const GameTypes = preload("res://src/core/common/game_types.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")
const SignalingClient = preload("res://src/network/signaling_client.gd")
const WebRTCPeerTransport = preload("res://src/network/webrtc_peer_transport.gd")
const HostNetworkSession = preload("res://src/network/host_network_session.gd")
const GameProtocol = preload("res://src/network/game_protocol.gd")

var _signaling_url := ""
var _output_dir := ""
var _stop_file := ""
var _exit_marker := ""
var _room_code := ""
var _signaling
var _transport
var _controller
var _session
var _peer_assignments := {}
var _active_join_count := 0
var _direct_gameplay_messages := 0
var _reconnects := 0
var _last_error := ""
var _last_status_write_msec := 0


func _initialize() -> void:
	if FileAccess.file_exists(WEBRTC_EXTENSION):
		GDExtensionManager.load_extension(WEBRTC_EXTENSION)
	_signaling_url = _argument("--signaling-url")
	_output_dir = _argument("--output-dir")
	_exit_marker = _argument("--exit-marker")
	_stop_file = _output_dir.path_join("stop")
	if _signaling_url.is_empty() or _output_dir.is_empty() or _exit_marker.is_empty():
		_fail("missing host runner arguments")
		return

	var state := MatchState.create(_config(), 9001)
	state.config.match_started = false
	_controller = MatchController.new(state)
	_controller.begin_match(Time.get_ticks_msec())
	_controller.state.players[&"host"].ready = true
	_signaling = SignalingClient.new()
	_transport = WebRTCPeerTransport.new(_signaling, [], Callable(), 15_000)
	_session = HostNetworkSession.new(
		_controller, _transport, "integration-match", &"host"
	)
	_transport.lobby_created.connect(_on_lobby_created)
	_transport.join_status.connect(_on_join_status)
	_transport.peer_connected.connect(_on_peer_connected)
	_transport.peer_disconnected.connect(_on_peer_disconnected)
	_transport.message_received.connect(_observe_direct_message)
	_transport.transport_failed.connect(_on_transport_failed)
	var error: Error = _transport.host_room(_signaling_url)
	if error != OK:
		_fail("host_room failed: %d" % error)
		return
	_write_status()


func _process(_delta: float) -> bool:
	if _transport == null or _session == null:
		return false
	if FileAccess.file_exists(_stop_file):
		_transport.close()
		_write_status("stopped")
		_write_exit_marker(0)
		_session = null
		_transport = null
		_signaling = null
		_controller = null
		quit(0)
		return true
	_session.poll()
	if (
		_controller.state.players.has(&"player-2")
		and _controller.state.players[&"player-2"].connected
		and _reconnects == 0
		and _active_join_count > 3
	):
		_reconnects = 1
	if Time.get_ticks_msec() - _last_status_write_msec >= 50:
		_write_status()
	return false


func _on_lobby_created(code: String) -> void:
	_room_code = code
	print("LOBBY_CREATED code=%s" % code)
	_write_status("room_ready")


func _on_join_status(status: String, details: Dictionary) -> void:
	if status != "approved":
		_fail("join rejected: %s" % details)
		return
	var peer_id: String = details.peer_id
	var role: String = details.role
	var player_id := "spectator"
	var reconnect := false
	if role == "active":
		var initial_ids := ["player-2", "player-3", "player-4"]
		if _active_join_count < initial_ids.size():
			player_id = initial_ids[_active_join_count]
		else:
			player_id = "player-2"
			reconnect = true
		_active_join_count += 1
	_peer_assignments[peer_id] = {
		"player_id": StringName(player_id),
		"role": role,
		"reconnect": reconnect,
	}
	print("JOIN_APPROVED peer=%s player=%s role=%s reconnect=%s" % [
		peer_id, player_id, role, reconnect,
	])


func _on_peer_connected(peer_id: String) -> void:
	if not _peer_assignments.has(peer_id):
		_fail("connected peer had no approved assignment: %s" % peer_id)
		return
	var assignment: Dictionary = _peer_assignments[peer_id]
	if assignment.reconnect:
		print("RECONNECT_CHANNEL_READY peer=%s" % peer_id)
		return
	var player_id: StringName = assignment.player_id
	if player_id == &"player-2":
		var registered: Error = _session.register_peer(
			peer_id, player_id, GameTypes.RecipientRole.ACTIVE_PLAYER
		)
		if registered != OK or _session.send_snapshot(peer_id) != OK:
			_fail("initial player registration failed: %d" % registered)
			return
	else:
		var result: Dictionary = _session.admit_peer(
			peer_id, player_id, assignment.role
		)
		if not result.accepted:
			_fail("participant admission failed: %s" % result.error_code)
			return
	print("DIRECT_PEER_READY peer=%s player=%s" % [peer_id, player_id])
	_write_status()


func _on_peer_disconnected(peer_id: String, reason: String) -> void:
	print("DIRECT_PEER_DISCONNECTED peer=%s reason=%s" % [peer_id, reason])
	_write_status()


func _observe_direct_message(peer_id: String, bytes: PackedByteArray) -> void:
	var decoded = GameProtocol.decode(bytes)
	if not decoded.ok:
		return
	var kind: String = decoded.envelope.kind
	if kind == "command":
		_direct_gameplay_messages += 1
		print("DIRECT_GAMEPLAY_RECEIVED peer=%s kind=%s command=%s" % [
			peer_id, kind, decoded.envelope.payload.get("kind", ""),
		])
	_write_status()


func _on_transport_failed(reason: String) -> void:
	if reason == "signaling_closed" and not _room_code.is_empty():
		var reconnect_error: Error = _signaling.reconnect()
		if reconnect_error == OK:
			print("SIGNALING_RECONNECT_STARTED code=%s" % _room_code)
			return
	_fail("transport failed: %s" % reason)


func _write_status(state_override: String = "") -> void:
	if _output_dir.is_empty():
		return
	_last_status_write_msec = Time.get_ticks_msec()
	var player_two_connected := true
	var frozen := false
	if _controller != null:
		frozen = _controller.state.frozen
		if _controller.state.players.has(&"player-2"):
			player_two_connected = _controller.state.players[&"player-2"].connected
	var state := state_override
	if state.is_empty():
		state = "room_ready" if not _room_code.is_empty() else "starting"
	var file := FileAccess.open(_output_dir.path_join("host.json"), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"state": state,
		"room_code": _room_code,
		"player_2_connected": player_two_connected,
		"frozen": frozen,
		"direct_gameplay_messages": _direct_gameplay_messages,
		"reconnects": _reconnects,
		"last_error": _last_error,
	}))
	file.close()


func _fail(reason: String) -> void:
	_last_error = reason
	push_error(reason)
	_write_status("failed")
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


func _config() -> MatchConfig:
	var abilities: Array[AbilityDefinition] = []
	for index in range(24):
		abilities.append(AbilityDefinition.new(
			StringName("integration-ability-%d" % index),
			AbilityDefinition.Timing.HAND_SHAPE, [], &"noop"
		))
	return MatchConfig.new(
		[&"host", &"player-2"], [], GameTypes.VictoryMode.SCORE_RACE, 100,
		GameTypes.InformationVisibility.PUBLIC,
		{
			GameTypes.Phase.START: 300_000,
			GameTypes.Phase.MAIN_1: 300_000,
			GameTypes.Phase.HAND_PLAY: 300_000,
			GameTypes.Phase.MAIN_2: 300_000,
			GameTypes.Phase.END: 300_000,
		},
		1_000, 300_000, 30_000, abilities
	)

