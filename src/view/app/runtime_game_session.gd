class_name RuntimeGameSession
extends RefCounted

signal command_result_received(request_message_id: String, result: Dictionary)
signal events_applied(events: Array, sequence: int)
signal snapshot_applied(snapshot: Dictionary, sequence: int)
signal session_failed(reason: String)
signal connection_state_changed(state: Dictionary)

const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")
const ContextHandDefinition = preload("res://src/core/scoring/context_hand_definition.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")
const SnapshotProjector = preload("res://src/core/match/snapshot_projector.gd")
const SignalingClient = preload("res://src/network/signaling_client.gd")
const WebRTCPeerTransport = preload("res://src/network/webrtc_peer_transport.gd")
const HostNetworkSession = preload("res://src/network/host_network_session.gd")
const ClientNetworkSession = preload("res://src/network/client_network_session.gd")
const ReconnectStore = preload("res://src/network/reconnect_store.gd")

const MATCH_ID := "shift-match"
const HOST_PLAYER_ID := &"host"
const RECONNECT_MESSAGE_ID := "runtime-reconnect-message"

var _transport: Variant
var _now: Callable
var _mode := ""
var _role := "active"
var _local_player_id: StringName = &""
var _local_display_name := ""
var _room_code := ""
var _signaling_url := ""
var _host_session: Variant
var _client_session: Variant
var _controller: Variant
var _local_sequence := 0
var _peer_assignments: Dictionary = {}
var _display_names: Dictionary = {}
var _settings: Dictionary
var _closed := false
var _failed := false
var _reconnect_store: ReconnectStore
var _reconnect_pending := false
var _reconnect_token := ""
var _transport_factory: Callable


func _init(
	transport_override: Variant = null,
	now: Callable = Callable(),
	reconnect_store_override: ReconnectStore = null,
	transport_factory: Callable = Callable()
) -> void:
	_transport = transport_override
	_now = now
	_settings = _default_settings()
	_reconnect_store = (
		reconnect_store_override if reconnect_store_override != null
		else ReconnectStore.new()
	)
	_transport_factory = transport_factory


func start_host(signaling_url: String, display_name: String) -> Error:
	if not _mode.is_empty() or signaling_url.is_empty() or display_name.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	_mode = "host"
	_signaling_url = signaling_url
	_role = "active"
	_local_player_id = HOST_PLAYER_ID
	_local_display_name = display_name.strip_edges().left(32)
	_display_names[HOST_PLAYER_ID] = _local_display_name
	_ensure_transport()
	_wire_transport()
	_emit_connection("connecting", "")
	return _transport.host_room(signaling_url)


func start_join(
	signaling_url: String,
	room_code: String,
	role: String,
	display_name: String
) -> Error:
	if (
		not _mode.is_empty() or signaling_url.is_empty() or room_code.is_empty()
		or role not in ["active", "spectator"] or display_name.strip_edges().is_empty()
	):
		return ERR_INVALID_PARAMETER
	_mode = "client"
	_signaling_url = signaling_url
	_role = role
	_room_code = room_code.to_upper()
	_local_display_name = display_name.strip_edges().left(32)
	_reconnect_store.clear()
	_ensure_transport()
	_wire_transport()
	_emit_connection("connecting", "")
	return _transport.join_room(
		signaling_url, _room_code, _role, _local_display_name
	)


func retry_connection() -> Error:
	if _mode != "client" or _role != "active" or _room_code.is_empty():
		return ERR_UNCONFIGURED
	var record := _reconnect_store.load_record(_reconnect_now_msec())
	if record.is_empty():
		return ERR_DOES_NOT_EXIST
	if _client_session != null:
		_client_session.close()
	_disconnect_transport_signals()
	if _transport != null and _transport.has_method("close"):
		_transport.close()
	_client_session = null
	_transport = null
	_local_player_id = StringName(record.player_id)
	_reconnect_token = str(record.token)
	_reconnect_pending = true
	_failed = false
	_ensure_transport()
	_wire_transport()
	_emit_connection("reconnecting", "direct")
	return _transport.join_room(
		_signaling_url, _room_code, _role, _local_display_name,
		str(_local_player_id)
	)


func submit_command(message_id: String, command: Dictionary) -> Error:
	if _closed:
		return ERR_UNAVAILABLE
	if _mode == "client":
		return (
			_client_session.submit_command(message_id, command)
			if _client_session != null else ERR_UNCONFIGURED
		)
	if _controller == null or _host_session == null:
		return ERR_UNCONFIGURED
	if (
		message_id.is_empty() or typeof(command.get("command_id", null)) != TYPE_STRING
		or typeof(command.get("kind", null)) != TYPE_STRING
		or not command.get("payload", null) is Dictionary
	):
		return ERR_INVALID_PARAMETER
	var game_command := GameCommand.new(
		StringName(command.command_id), _local_player_id,
		StringName(command.kind), command.payload
	)
	var result = _controller.submit(game_command, _now_msec())
	command_result_received.emit(message_id, {
		"accepted": result.accepted,
		"error_code": str(result.error_code),
	})
	if result.accepted:
		_host_session.publish_state_change(result.events)
	return OK


func update_lobby_setting(key: StringName, value: Variant) -> StringName:
	if _mode != "host":
		return &"host_only"
	var error := _apply_setting(_settings, key, value)
	if not error.is_empty():
		return error
	if _controller != null:
		error = _apply_config_setting(_controller.state.config, key, value)
		if not error.is_empty():
			return error
		_host_session.publish_state_change([])
	else:
		_emit_lobby_snapshot()
	return &""


func start_match() -> Error:
	if _mode != "host" or _controller == null or _host_session == null:
		return ERR_UNCONFIGURED
	if _controller.state.active_player_ids().size() < 2:
		return ERR_UNAVAILABLE
	_controller.state.config.match_started = true
	_host_session.publish_state_change([])
	return OK


func poll() -> void:
	if _closed or _transport == null:
		return
	if _mode == "host" and _host_session != null:
		_host_session.poll()
	elif _mode == "client" and _client_session != null:
		_client_session.poll()
	else:
		_transport.poll()


func close() -> void:
	if _closed:
		return
	_closed = true
	if _host_session != null:
		_host_session.close()
	if _client_session != null:
		_client_session.close()
	_disconnect_transport_signals()
	if _transport != null and _transport.has_method("close"):
		_transport.close()
	_host_session = null
	_client_session = null
	_controller = null
	_transport = null
	_emit_connection("closed", "")


func _ensure_transport() -> void:
	if _transport != null:
		return
	if _transport_factory.is_valid():
		_transport = _transport_factory.call()
		return
	var signaling := SignalingClient.new()
	_transport = WebRTCPeerTransport.new(signaling, _ice_servers(), Callable(), 15_000)


func _wire_transport() -> void:
	_transport.lobby_created.connect(_on_lobby_created)
	_transport.join_status.connect(_on_join_status)
	_transport.peer_connected.connect(_on_peer_connected)
	_transport.peer_disconnected.connect(_on_peer_disconnected)
	_transport.transport_failed.connect(_on_transport_failed)


func _disconnect_transport_signals() -> void:
	if _transport == null:
		return
	for pair in [
		[_transport.lobby_created, _on_lobby_created],
		[_transport.join_status, _on_join_status],
		[_transport.peer_connected, _on_peer_connected],
		[_transport.peer_disconnected, _on_peer_disconnected],
		[_transport.transport_failed, _on_transport_failed],
	]:
		var signal_value: Signal = pair[0]
		var callable: Callable = pair[1]
		if signal_value.is_connected(callable):
			signal_value.disconnect(callable)


func _on_lobby_created(code: String) -> void:
	_room_code = code.to_upper()
	_emit_connection("connected", "")
	if _controller == null:
		_emit_lobby_snapshot()


func _on_join_status(status: String, details: Dictionary) -> void:
	if status != "approved":
		_fail(str(details.get("error", "join_rejected")))
		return
	var peer_id := String(details.get("peer_id", ""))
	if peer_id.is_empty():
		_fail("malformed_join_approval")
		return
	var assignment := {
		"role": str(details.get("role", "active")),
		"display_name": str(details.get("display_name", "Player")).left(32),
		"reconnect_player_id": str(details.get("reconnect_player_id", "")),
	}
	if _mode == "host":
		_peer_assignments[peer_id] = assignment
		var named_player_id := StringName(
			assignment.reconnect_player_id if not assignment.reconnect_player_id.is_empty()
			else peer_id
		)
		_display_names[named_player_id] = assignment.display_name
		if _controller == null:
			_emit_lobby_snapshot()
	else:
		if not _reconnect_pending:
			_local_player_id = StringName(peer_id)
		_display_names[_local_player_id] = _local_display_name


func _on_peer_connected(peer_id: String) -> void:
	if _mode == "client":
		if peer_id != "host" or _local_player_id.is_empty():
			return
		_client_session = ClientNetworkSession.new(
			_transport, "host", MATCH_ID, _local_player_id,
			_reconnect_store, _room_code, _now
		)
		_client_session.command_result_received.connect(
			func(message_id: String, result: Dictionary):
				if message_id == RECONNECT_MESSAGE_ID:
					if bool(result.get("accepted", false)):
						_reconnect_pending = false
						_reconnect_token = ""
						_emit_connection("connected", "")
					else:
						_fail("reconnect_rejected:%s" % result.get("error_code", "unknown"))
				command_result_received.emit(message_id, result.duplicate(true))
		)
		_client_session.events_applied.connect(
			func(events: Array, sequence: int):
				events_applied.emit(events.duplicate(true), sequence)
		)
		_client_session.snapshot_applied.connect(_on_client_snapshot)
		_client_session.session_failed.connect(_fail)
		if _reconnect_pending:
			var reconnect_error: Error = _client_session.submit_command(
				RECONNECT_MESSAGE_ID, {
					"command_id": "runtime-reconnect-%d" % _reconnect_now_msec(),
					"kind": "reconnect", "payload": {"token": _reconnect_token},
				}
			)
			if reconnect_error != OK:
				_fail("reconnect_send_failed")
		else:
			_emit_connection("connected", "")
		return
	if not _peer_assignments.has(peer_id):
		_fail("unapproved_peer")
		return
	var assignment: Dictionary = _peer_assignments[peer_id]
	if not str(assignment.get("reconnect_player_id", "")).is_empty():
		if _host_session == null:
			_transport.disconnect_peer(peer_id, "reconnect_unavailable")
		return
	if _controller == null and assignment.role == "active":
		_create_host_authority(peer_id)
		return
	if _host_session == null:
		assignment["connected"] = true
		_emit_lobby_snapshot()
		return
	var admission: Dictionary = _host_session.admit_peer(
		peer_id, StringName(peer_id), assignment.role
	)
	if not admission.accepted:
		_transport.disconnect_peer(peer_id, str(admission.error_code))


func _create_host_authority(first_peer_id: String) -> void:
	var config := _build_config([HOST_PLAYER_ID, StringName(first_peer_id)])
	var state := MatchState.create(config, int(Time.get_unix_time_from_system()))
	state.config.match_started = false
	_controller = MatchController.new(state)
	_host_session = HostNetworkSession.new(
		_controller, _transport, MATCH_ID, HOST_PLAYER_ID, _now,
		HostNetworkSession.DEFAULT_HEARTBEAT_INTERVAL_MSEC,
		HostNetworkSession.DEFAULT_HEARTBEAT_TIMEOUT_MSEC,
		Callable(), Callable(self, "_decorate_network_snapshot")
	)
	_host_session.authoritative_state_changed.connect(_on_authoritative_state_changed)
	var registration: Error = _host_session.register_peer(
		first_peer_id, StringName(first_peer_id), GameTypes.RecipientRole.ACTIVE_PLAYER
	)
	if registration != OK:
		_fail("peer_registration_failed")
		return
	_host_session.send_snapshot(first_peer_id)
	for queued_peer_variant in _peer_assignments.keys():
		var queued_peer := String(queued_peer_variant)
		if queued_peer == first_peer_id:
			continue
		var queued: Dictionary = _peer_assignments[queued_peer]
		if bool(queued.get("connected", false)):
			_host_session.admit_peer(
				queued_peer, StringName(queued_peer), queued.role
			)
	_emit_host_snapshot()


func _on_authoritative_state_changed(events: Array) -> void:
	_local_sequence += 1
	var projected: Array = []
	for event in events:
		if not event is Object:
			continue
		if event.audience == &"public" or (
			event.audience == &"player" and event.recipient_id == _local_player_id
		):
			projected.append({
				"kind": str(event.kind), "payload": event.payload.duplicate(true),
			})
	if not projected.is_empty():
		events_applied.emit(projected, _local_sequence)
	_emit_host_snapshot()


func _emit_host_snapshot() -> void:
	if _controller == null:
		return
	var snapshot := SnapshotProjector.for_recipient(
		_controller.state, _local_player_id, GameTypes.RecipientRole.ACTIVE_PLAYER
	)
	snapshot["lobby_settings"] = _controller.state.config.to_dict()
	snapshot["server_now_msec"] = _now_msec()
	snapshot["now_msec"] = snapshot.server_now_msec
	snapshot_applied.emit(
		_decorate_snapshot(snapshot, _local_player_id, GameTypes.RecipientRole.ACTIVE_PLAYER),
		_local_sequence
	)


func _on_client_snapshot(snapshot: Dictionary, sequence: int) -> void:
	var rendered := snapshot.duplicate(true)
	if not rendered.has("connection_state"):
		rendered["connection_state"] = {"status": "connected", "reason": ""}
	snapshot_applied.emit(rendered, sequence)


func _decorate_network_snapshot(
	snapshot: Dictionary,
	recipient_id: StringName,
	recipient_role: int
) -> Dictionary:
	return _decorate_snapshot(snapshot, recipient_id, recipient_role)


func _decorate_snapshot(
	snapshot: Dictionary,
	recipient_id: StringName,
	recipient_role: int
) -> Dictionary:
	var settings: Dictionary = snapshot.get(
		"lobby_settings", _controller.state.config.to_dict()
	)
	var started := bool(settings.get("match_started", false))
	if int(snapshot.get("phase", GameTypes.Phase.START)) != GameTypes.Phase.START:
		started = true
		snapshot["lobby_settings"]["match_started"] = true
	var players: Array = snapshot.get("players", [])
	var active_count := 0
	var spectator_count := 0
	for player in players:
		if not player is Dictionary:
			continue
		var player_id := StringName(player.get("player_id", ""))
		player["name"] = str(_display_names.get(player_id, _fallback_name(player)))
		player["role"] = "spectator" if bool(player.get("spectator", false)) else "active"
		if bool(player.get("spectator", false)):
			spectator_count += 1
		elif bool(player.get("active", false)):
			active_count += 1
	snapshot["players"] = players
	snapshot["room_code"] = _room_code
	snapshot["is_host"] = recipient_id == HOST_PLAYER_ID
	snapshot["local_role"] = (
		"spectator" if recipient_role == GameTypes.RecipientRole.SPECTATOR else "active"
	)
	snapshot["match_started"] = started
	snapshot["screen_id"] = "match" if started else "lobby"
	snapshot["active_player_count"] = active_count
	snapshot["spectator_count"] = spectator_count
	snapshot["settings"] = _flatten_settings(settings)
	snapshot["victory_mode"] = int(settings.get("victory_mode", 0))
	snapshot["victory_target"] = int(settings.get("victory_target", 10))
	snapshot["ability_catalog"] = _ability_catalog(settings.get("ability_definitions", []))
	snapshot["required_half_count"] = maxi(
		0, 6 - snapshot.get("private_hand", []).size()
	) * 2
	snapshot["connection_state"] = {"status": "connected", "reason": ""}
	return snapshot


func _emit_lobby_snapshot() -> void:
	_local_sequence += 1
	var players: Array = [{
		"player_id": str(HOST_PLAYER_ID), "name": _local_display_name,
		"role": "active", "spectator": false, "active": true,
		"pending": false, "connected": true, "ready": false,
	}]
	for peer_id_variant in _peer_assignments.keys():
		var peer_id := String(peer_id_variant)
		var assignment: Dictionary = _peer_assignments[peer_id]
		players.append({
			"player_id": peer_id, "name": assignment.display_name,
			"role": assignment.role, "spectator": assignment.role == "spectator",
			"active": assignment.role == "active", "pending": true,
			"connected": bool(assignment.get("connected", false)), "ready": false,
		})
	var active_count := players.filter(func(player): return not player.spectator).size()
	var spectator_count := players.size() - active_count
	snapshot_applied.emit({
		"screen_id": "lobby", "room_code": _room_code, "is_host": true,
		"match_started": false, "players": players,
		"active_player_count": active_count, "spectator_count": spectator_count,
		"settings": _settings.duplicate(true),
		"connection": {"status": "connected", "reason": ""},
	}, _local_sequence)


func _on_peer_disconnected(peer_id: String, reason: String) -> void:
	if _mode == "client" and peer_id == "host":
		_fail("host_lost" if reason != "direct_connection_failed" else reason)


func _on_transport_failed(reason: String) -> void:
	if reason == "signaling_closed" and not _room_code.is_empty():
		if _mode == "host" and _transport.has_method("reconnect_signaling"):
			var reconnect_error: Error = _transport.reconnect_signaling()
			if reconnect_error == OK:
				_emit_connection("reconnecting", "signaling")
				return
		elif _mode == "client" and _client_session != null:
			return
	_fail(reason)


func _fail(reason: String) -> void:
	if _closed or _failed:
		return
	var reported_reason := reason
	if (
		reason == "direct_connection_failed" and _transport != null
		and _transport.has_method("has_relay_fallback")
		and not bool(_transport.has_relay_fallback())
	):
		reported_reason = "relay_unavailable"
	_failed = true
	_emit_connection("failed", reported_reason)
	session_failed.emit(reported_reason)


func _emit_connection(status: String, reason: String) -> void:
	connection_state_changed.emit({"status": status, "reason": reason})


func _build_config(active_ids: Array) -> MatchConfig:
	return MatchConfig.new(
		active_ids, [], int(_settings.victory_mode), int(_settings.victory_target),
		int(_settings.information_visibility), {
			GameTypes.Phase.START: int(_settings.start_timer_msec),
			GameTypes.Phase.MAIN_1: int(_settings.main_timer_msec),
			GameTypes.Phase.HAND_PLAY: int(_settings.hand_timer_msec),
			GameTypes.Phase.MAIN_2: int(_settings.main_timer_msec),
			GameTypes.Phase.END: int(_settings.end_timer_msec),
		}, int(_settings.reaction_window_msec),
		int(_settings.public_hard_limit_msec), int(_settings.reconnect_grace_msec),
		_default_abilities(), _placeholder_normal_hands(), _placeholder_context_hands()
	)


func _default_settings() -> Dictionary:
	return {
		"victory_mode": GameTypes.VictoryMode.SCORE_RACE,
		"victory_target": 100,
		"information_visibility": GameTypes.InformationVisibility.PUBLIC,
		"start_timer_msec": 20_000,
		"main_timer_msec": 30_000,
		"hand_timer_msec": 45_000,
		"end_timer_msec": 10_000,
		"reaction_window_msec": 2_000,
		"public_hard_limit_msec": 30_000,
		"reconnect_grace_msec": 30_000,
	}


func _apply_setting(settings: Dictionary, key: StringName, value: Variant) -> StringName:
	if not settings.has(str(key)) or not value is int or int(value) <= 0:
		if key in [&"victory_mode", &"information_visibility"] and value is int:
			pass
		else:
			return &"invalid_setting"
	settings[str(key)] = value
	return &""


func _apply_config_setting(config: MatchConfig, key: StringName, value: Variant) -> StringName:
	match key:
		&"victory_mode": return config.set_victory_mode(int(value))
		&"victory_target": return config.set_victory_target(int(value))
		&"information_visibility": return config.set_information_visibility(int(value))
		&"start_timer_msec": return config.set_phase_timer(GameTypes.Phase.START, int(value))
		&"main_timer_msec":
			var first := config.set_phase_timer(GameTypes.Phase.MAIN_1, int(value))
			if not first.is_empty(): return first
			var second := config.set_phase_timer(GameTypes.Phase.MAIN_2, int(value))
			if not second.is_empty(): return second
			return config.set_public_hard_limit_msec(int(value))
		&"hand_timer_msec": return config.set_phase_timer(GameTypes.Phase.HAND_PLAY, int(value))
		&"end_timer_msec": return config.set_phase_timer(GameTypes.Phase.END, int(value))
		&"reaction_window_msec": return config.set_reaction_window_msec(int(value))
		&"public_hard_limit_msec": return config.set_public_hard_limit_msec(int(value))
		&"reconnect_grace_msec": return config.set_reconnect_grace_msec(int(value))
	return &"unknown_setting"


func _flatten_settings(config: Dictionary) -> Dictionary:
	var timers: Dictionary = config.get("phase_timers", {})
	return {
		"victory_mode": int(config.get("victory_mode", 0)),
		"victory_target": int(config.get("victory_target", 100)),
		"information_visibility": int(config.get("information_visibility", 0)),
		"start_timer_msec": int(timers.get(str(GameTypes.Phase.START), 20_000)),
		"main_timer_msec": int(config.get("public_hard_limit_msec", 30_000)),
		"hand_timer_msec": int(timers.get(str(GameTypes.Phase.HAND_PLAY), 45_000)),
		"end_timer_msec": int(timers.get(str(GameTypes.Phase.END), 10_000)),
		"reaction_window_msec": int(config.get("reaction_window_msec", 2_000)),
		"public_hard_limit_msec": int(config.get("public_hard_limit_msec", 30_000)),
		"reconnect_grace_msec": int(config.get("reconnect_grace_msec", 30_000)),
	}


func _ability_catalog(definitions: Array) -> Dictionary:
	var result := {}
	for definition in definitions:
		if not definition is Dictionary:
			continue
		var id := str(definition.get("id", ""))
		var display_name := str(definition.get("display_name", ""))
		result[id] = {
			"label": display_name if not display_name.is_empty() else id.replace("_", " ").capitalize(),
			"rules_text": str(definition.get("rules_text", "")),
			"timing": int(definition.get("timing", -1)),
			"tags": definition.get("tags", []).duplicate(true),
			"effect_id": str(definition.get("effect_id", "noop")),
			"choice_schema": definition.get("choice_schema", {}).duplicate(true),
		}
	return result


func _default_abilities() -> Array[AbilityDefinition]:
	return AbilityCatalog.manipulation_definitions(2)


func _placeholder_normal_hands() -> Array[NormalHandDefinition]:
	return [
		NormalHandDefinition.new(&"high_card", 10, 1, &"high_card", Rational.new(1, 1)),
		NormalHandDefinition.new(&"pair", 20, 2, &"pair", Rational.new(1, 1)),
		NormalHandDefinition.new(&"three_kind", 30, 3, &"three_kind", Rational.new(1, 1)),
		NormalHandDefinition.new(&"straight_three", 40, 3, &"straight", Rational.new(1, 1)),
		NormalHandDefinition.new(&"straight_four", 41, 4, &"straight", Rational.new(1, 1)),
		NormalHandDefinition.new(&"straight_five", 42, 5, &"straight", Rational.new(1, 1)),
		NormalHandDefinition.new(&"straight_six", 43, 6, &"straight", Rational.new(1, 1)),
		NormalHandDefinition.new(&"full_house", 50, 5, &"full_house", Rational.new(1, 1)),
	]


func _placeholder_context_hands() -> Array[ContextHandDefinition]:
	var result: Array[ContextHandDefinition] = []
	for count in range(1, 5):
		result.append(ContextHandDefinition.new(
			StringName("all_contexts_%d" % count), count,
			{0: count, 1: count, 2: count}, Rational.new(1, 1)
		))
	for context in range(3):
		for count in range(5, 13):
			result.append(ContextHandDefinition.new(
				StringName("context_%d_%d" % [context, count]), 100 + count,
				{context: count}, Rational.new(1, 1)
			))
	for first in range(3):
		for second in range(first + 1, 3):
			for count in range(3, 7):
				result.append(ContextHandDefinition.new(
					StringName("contexts_%d_%d_%d" % [first, second, count]), 50 + count,
					{first: count, second: count}, Rational.new(1, 1)
				))
	return result


func _fallback_name(player: Dictionary) -> String:
	if bool(player.get("spectator", false)):
		return "Spectator"
	return "Player %d" % (int(player.get("seat_index", 0)) + 1)


func _ice_servers() -> Array:
	var configured: Variant = ProjectSettings.get_setting("shift/network/ice_servers", [])
	return configured.duplicate(true) if configured is Array else []


func _now_msec() -> int:
	return int(_now.call()) if _now.is_valid() else Time.get_ticks_msec()


func _reconnect_now_msec() -> int:
	return (
		int(_now.call()) if _now.is_valid()
		else int(Time.get_unix_time_from_system() * 1000.0)
	)
