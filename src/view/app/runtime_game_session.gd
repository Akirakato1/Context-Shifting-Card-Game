class_name RuntimeGameSession
extends RefCounted

signal command_result_received(request_message_id: String, result: Dictionary)
signal events_applied(events: Array, sequence: int)
signal snapshot_applied(snapshot: Dictionary, sequence: int)
signal spectator_views_received(views: Dictionary)
signal session_failed(reason: String)
signal connection_state_changed(state: Dictionary)
signal leave_completed

const GameTypes = preload("res://src/core/common/game_types.gd")
const CommandKinds = preload("res://src/core/commands/command_kinds.gd")
const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const ContextHandCatalog = preload("res://src/core/scoring/context_hand_catalog.gd")
const ScoringReference = preload("res://src/view/app/scoring_reference.gd")
const GameCommand = preload("res://src/core/commands/game_command.gd")
const DomainEvent := preload("res://src/core/events/domain_event.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")
const SnapshotProjector = preload("res://src/core/match/snapshot_projector.gd")
const SignalingClient = preload("res://src/network/signaling_client.gd")
const WebRTCPeerTransport = preload("res://src/network/webrtc_peer_transport.gd")
const HostNetworkSession = preload("res://src/network/host_network_session.gd")
const ClientNetworkSession = preload("res://src/network/client_network_session.gd")
const ReconnectStore = preload("res://src/network/reconnect_store.gd")
const NetworkDiagnostics = preload("res://src/network/network_diagnostics.gd")
const BotMatchRunner = preload("res://src/core/match/bot_match_runner.gd")
const AvatarCatalog := preload("res://src/view/common/avatar_catalog.gd")
const PracticeHandHint := preload("res://src/view/app/practice_hand_hint.gd")

const MATCH_ID := "shift-match"
const HOST_PLAYER_ID := &"host"
const RECONNECT_MESSAGE_ID := "runtime-reconnect-message"
const LEAVE_MESSAGE_ID := "runtime-leave-message"
const AVATAR_MESSAGE_ID := "runtime-avatar-message"
const LEAVE_ACK_TIMEOUT_MSEC := 1000

var _transport: Variant
var _now: Callable
var _mode := ""
var _role := "active"
var _local_player_id: StringName = &""
var _local_display_name := ""
var _local_avatar_id := ""
var _sent_avatar := false
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
var _leave_deadline_msec := -1
var _is_practice := false
var _bots: Dictionary = {}
var _next_bot_id := 0
var _bot_runner := BotMatchRunner.new()
var _practice_hint := PracticeHandHint.new()
var _pending_view_update := {}


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


func start_host(signaling_url: String, display_name: String, avatar_id: String = "") -> Error:
	avatar_id = GameTypes.canonical_avatar_id(avatar_id)
	if (
		not _mode.is_empty() or signaling_url.is_empty() or display_name.strip_edges().is_empty()
		or (not avatar_id.is_empty() and avatar_id not in GameTypes.AVATAR_IDS)
	):
		return ERR_INVALID_PARAMETER
	_mode = "host"
	_signaling_url = signaling_url
	_role = "active"
	_local_player_id = HOST_PLAYER_ID
	_local_display_name = display_name.strip_edges().left(32)
	_local_avatar_id = avatar_id
	_display_names[HOST_PLAYER_ID] = _local_display_name
	_ensure_transport()
	_wire_transport()
	_emit_connection("connecting", "")
	return _transport.host_room(signaling_url)


func start_practice(avatar_id: String = "") -> Error:
	if _closed or not _mode.is_empty():
		return ERR_ALREADY_IN_USE
	avatar_id = GameTypes.canonical_avatar_id(avatar_id)
	if not avatar_id.is_empty() and avatar_id not in GameTypes.AVATAR_IDS:
		return ERR_INVALID_PARAMETER
	_mode = "host"
	_is_practice = true
	_local_player_id = HOST_PLAYER_ID
	_local_display_name = "You"
	_local_avatar_id = avatar_id if not avatar_id.is_empty() else GameTypes.default_avatar_id(0)
	_display_names[HOST_PLAYER_ID] = _local_display_name
	_settings.victory_mode = GameTypes.VictoryMode.ROUND_WIN_RACE
	_settings.victory_target = 3
	_settings.information_visibility = GameTypes.InformationVisibility.PRIVATE
	_create_authority([HOST_PLAYER_ID])
	for _index in range(3):
		_add_bot()
	_emit_connection("connected", "")
	_publish_authority([])
	return OK


func add_bot() -> StringName:
	var error := _lobby_roster_error()
	if not error.is_empty():
		return error
	if _controller == null:
		_create_host_authority()
	error = _add_bot()
	if error.is_empty():
		_publish_authority([])
	return error


func _add_bot() -> StringName:
	var state: MatchState = _controller.state
	if state.seat_order.size() >= 4 or _bots.size() >= 3:
		return &"active_seats_full"
	var avatars := _available_bot_avatars()
	_next_bot_id += 1
	var bot_id := StringName("bot-%d" % _next_bot_id)
	var result: CommandResult = _controller.submit(GameCommand.new(
		&"add-lobby-bot", bot_id, CommandKinds.JOIN_ACTIVE
	), _now_msec())
	if not result.accepted:
		return result.error_code
	var avatar: String = avatars.pick_random()
	var bot: PlayerState = state.players[bot_id]
	bot.avatar_id = avatar
	bot.ready = true
	_display_names[bot_id] = AvatarCatalog.display_name(avatar)
	_bots[bot_id] = 1
	return &""


func remove_bot(bot_id: StringName) -> StringName:
	var error := _lobby_roster_error()
	if not error.is_empty():
		return error
	if not _bots.erase(bot_id):
		return &"unknown_bot"
	_display_names.erase(bot_id)
	_publish_authority(_controller.remove_transient_participant(bot_id))
	return &""


func set_bot_difficulty(bot_id: StringName, difficulty: int) -> StringName:
	var error := _lobby_roster_error()
	if not error.is_empty():
		return error
	if not _bots.has(bot_id):
		return &"unknown_bot"
	if difficulty not in [0, 1, 2]:
		return &"invalid_bot_difficulty"
	_bots[bot_id] = difficulty
	_publish_authority([])
	return &""


func set_bot_avatar(bot_id: StringName, avatar: String) -> StringName:
	var error := _lobby_roster_error()
	if not error.is_empty():
		return error
	if not _bots.has(bot_id):
		return &"unknown_bot"
	avatar = GameTypes.canonical_avatar_id(avatar)
	if avatar not in GameTypes.AVATAR_IDS:
		return &"invalid_avatar"
	if avatar not in _available_bot_avatars(bot_id):
		return &"avatar_in_use"
	_controller.state.players[bot_id].avatar_id = avatar
	_display_names[bot_id] = AvatarCatalog.display_name(avatar)
	_publish_authority([])
	return &""


func set_practice_avatar(avatar: String) -> StringName:
	if not _is_practice:
		return &"practice_only"
	var error := _lobby_roster_error()
	if not error.is_empty():
		return error
	avatar = GameTypes.canonical_avatar_id(avatar)
	if avatar not in GameTypes.AVATAR_IDS:
		return &"invalid_avatar"
	var player: PlayerState = _controller.state.players[HOST_PLAYER_ID]
	if player.avatar_id == avatar:
		return &""
	for bot_id: StringName in _bots:
		var bot: PlayerState = _controller.state.players[bot_id]
		if bot.avatar_id == avatar:
			bot.avatar_id = player.avatar_id
			_display_names[bot_id] = AvatarCatalog.display_name(bot.avatar_id)
			break
	player.avatar_id = avatar
	_local_avatar_id = avatar
	_publish_authority([])
	return &""


func _available_bot_avatars(excluded_player := &"") -> Array:
	var avatars := GameTypes.AVATAR_IDS.duplicate()
	for player_id: StringName in _controller.state.seat_order:
		if player_id == excluded_player:
			continue
		var player: PlayerState = _controller.state.players[player_id]
		var avatar := player.avatar_id if not player.avatar_id.is_empty() else GameTypes.default_avatar_id(player.seat_index)
		avatars.erase(avatar)
	return avatars


func _lobby_roster_error() -> StringName:
	if _mode != "host":
		return &"host_only"
	if _closed or (not _is_practice and _room_code.is_empty()):
		return &"lobby_unavailable"
	if _controller != null and (_controller.state.config.match_started or _controller.state.phase != GameTypes.Phase.START):
		return &"config_locked"
	return &""


func start_join(
	signaling_url: String,
	room_code: String,
	role: String,
	display_name: String,
	avatar_id: String = ""
) -> Error:
	avatar_id = GameTypes.canonical_avatar_id(avatar_id)
	if (
		not _mode.is_empty() or signaling_url.is_empty() or room_code.is_empty()
		or role not in ["active", "spectator"] or display_name.strip_edges().is_empty()
		or (not avatar_id.is_empty() and avatar_id not in GameTypes.AVATAR_IDS)
	):
		return ERR_INVALID_PARAMETER
	_mode = "client"
	_signaling_url = signaling_url
	_role = role
	_room_code = room_code.to_upper()
	_local_display_name = display_name.strip_edges().left(32)
	_local_avatar_id = avatar_id
	if _role == "active":
		var record := _saved_seat_for_room()
		if not record.is_empty():
			return _join_saved_seat(record)
	_reconnect_store.clear()
	_ensure_transport()
	_wire_transport()
	_emit_connection("connecting", "")
	return _transport.join_room(
		signaling_url, _room_code, _role, _local_display_name
	)


func retry_connection() -> Error:
	if _mode != "client" or _role != "active" or _room_code.is_empty():
		NetworkDiagnostics.log_event(_mode, "reconnect_not_configured")
		return ERR_UNCONFIGURED
	if _reconnect_pending and not _failed:
		return ERR_BUSY
	var record := _saved_seat_for_room()
	if record.is_empty():
		NetworkDiagnostics.log_event("client", "reconnect_record_missing_or_expired")
		return ERR_DOES_NOT_EXIST
	if _client_session != null:
		_client_session.close()
	_disconnect_transport_signals()
	if _transport != null and _transport.has_method("close"):
		_transport.close()
	_client_session = null
	_transport = null
	return _join_saved_seat(record)


func _saved_seat_for_room() -> Dictionary:
	var record := _reconnect_store.load_record(_reconnect_now_msec())
	return record if record.get("room_code", "") == _room_code else {}


func _join_saved_seat(record: Dictionary) -> Error:
	_local_player_id = StringName(record.player_id)
	_reconnect_token = str(record.token)
	_reconnect_pending = true
	_sent_avatar = true
	_failed = false
	_ensure_transport()
	_wire_transport()
	NetworkDiagnostics.log_event("client", "reconnect_started")
	_emit_connection("reconnecting", "direct")
	var error: Error = _transport.join_room(
		_signaling_url, _room_code, _role, _local_display_name,
		str(_local_player_id)
	)
	if error != OK:
		_reconnect_pending = false
		_failed = true
		NetworkDiagnostics.log_event("client", "reconnect_socket_open_failed_%d" % error)
	return error


func request_match_leave() -> bool:
	if _mode != "client" or _role != "active":
		return false
	if _leave_deadline_msec >= 0:
		return true
	_reconnect_store.clear()
	if _client_session == null or _failed:
		return false
	var snapshot: Dictionary = _client_session.latest_snapshot
	if (
		not snapshot.get("match_started", false) or snapshot.get("match_complete", false)
		or not snapshot.has("private_player_id")
	):
		return false
	_leave_deadline_msec = _now_msec() + LEAVE_ACK_TIMEOUT_MSEC
	var result: Error = _client_session.submit_command(LEAVE_MESSAGE_ID, {
		"command_id": "runtime-leave-command", "kind": "forfeit", "payload": {},
	})
	if result != OK:
		_finish_requested_leave()
	return true


func _finish_requested_leave() -> void:
	if _leave_deadline_msec < 0:
		return
	_leave_deadline_msec = -1
	_reconnect_store.clear()
	# Let the active receive/poll callback finish before the app closes the transport.
	leave_completed.emit.call_deferred()


func submit_command(message_id: String, command: Dictionary) -> Error:
	if _closed:
		return ERR_UNAVAILABLE
	if _mode == "client":
		return (
			_client_session.submit_command(message_id, command)
			if _client_session != null else ERR_UNCONFIGURED
		)
	if _controller == null:
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
	if result.accepted and game_command.kind != CommandKinds.UPDATE_HAND_DRAFT:
		_publish_authority(result.events)
	return OK


func update_lobby_setting(key: StringName, value: Variant) -> StringName:
	if _mode != "host":
		return &"host_only"
	if _controller != null and (
		_controller.state.config.match_started or _controller.state.phase != GameTypes.Phase.START
	):
		return &"config_locked"
	if key == &"ability_deck_recipe":
		return _update_ability_deck_recipe(value)
	var updated_settings := _settings.duplicate()
	var error := _apply_setting(updated_settings, key, value)
	if not error.is_empty():
		return error
	if _controller != null:
		error = _apply_config_setting(_controller.state.config, key, value)
		if not error.is_empty():
			return error
	_settings = updated_settings
	_publish_lobby_settings()
	return &""


func _update_ability_deck_recipe(value: Variant) -> StringName:
	if not value is Dictionary:
		return &"invalid_ability_deck_recipe"
	var known_ids := AbilityCatalog.public_catalog({})
	var recipe := {}
	var total := 0
	for id in value:
		var copies: Variant = value[id]
		if (not id is String and not id is StringName) or not known_ids.has(str(id)):
			return &"invalid_ability_deck_recipe"
		if not copies is int or copies < 0 or copies > AbilityCatalog.MAX_RECIPE_COPIES_PER_ABILITY:
			return &"invalid_ability_deck_recipe"
		if copies > 0:
			recipe[str(id)] = copies
			total += copies
	if total < AbilityCatalog.MIN_LOBBY_DECK_SIZE:
		return &"insufficient_ability_cards"
	if recipe == _settings.ability_deck_recipe:
		return &""
	if _controller != null:
		var error: StringName = _controller.state.replace_lobby_ability_deck(AbilityCatalog.build_deck(recipe))
		if not error.is_empty():
			return error
	_settings["ability_deck_recipe"] = recipe
	_publish_lobby_settings()
	return &""


func _publish_lobby_settings() -> void:
	if _controller != null:
		_publish_authority([])
	else:
		_emit_lobby_snapshot()


func _publish_authority(events: Array) -> void:
	if _host_session != null:
		_host_session.publish_state_change(events)
	else:
		_on_authoritative_state_changed(events)


func start_match() -> Error:
	if _mode != "host" or _controller == null:
		return ERR_UNCONFIGURED
	var state: MatchState = _controller.state
	if state.config.match_started:
		return ERR_ALREADY_IN_USE
	if state.phase != GameTypes.Phase.START or state.match_complete:
		return ERR_UNAVAILABLE
	if not state.config.validate().is_empty():
		return ERR_UNAVAILABLE
	if _unready_lobby_guest_count() > 0:
		return ERR_BUSY
	var events: Array = _controller.begin_match(_now_msec())
	if events.is_empty():
		return ERR_INVALID_DATA
	_publish_authority(events)
	return OK


func _unready_lobby_guest_count() -> int:
	var waiting := 0
	for player_id in _controller.state.seat_order:
		var player: PlayerState = _controller.state.players[player_id]
		if (
			player_id != HOST_PLAYER_ID and not _bots.has(player_id) and player.active and not player.pending
			and (not player.connected or not player.ready)
		):
			waiting += 1
	return waiting


func start_rematch() -> Error:
	return reset_for_rematch(true)


func reset_for_rematch(start_immediately: bool = false) -> Error:
	if _mode != "host" or _controller == null:
		return ERR_UNCONFIGURED
	var state: MatchState = _controller.state
	if (
		state.phase != GameTypes.Phase.COMPLETE or not state.match_complete
		or not state.config.validate(not start_immediately).is_empty()
	):
		return ERR_UNAVAILABLE
	_controller.reset_for_rematch(Time.get_ticks_usec(), GameTypes.Phase.START)
	var events: Array = _controller.begin_match(_now_msec()) if start_immediately else []
	_publish_authority(events)
	return OK


func update_match_view(view: Dictionary) -> void:
	if _closed or _role != "active" or _is_practice:
		return
	if _mode == "host" and _host_session != null:
		_host_session.update_player_view(_local_player_id, view)
	elif _mode == "client" and _client_session != null and not _reconnect_pending:
		_pending_view_update = view.duplicate(true)


func poll() -> void:
	if _closed:
		return
	if _leave_deadline_msec >= 0 and _now_msec() >= _leave_deadline_msec:
		_finish_requested_leave()
		return
	if _controller != null and not _bots.is_empty():
		var updates := _bot_runner.poll(_controller, _bots, _now_msec())
		if updates.changed:
			_publish_authority(updates.events)
	if _closed:
		return
	if _is_practice:
		var events: Array = _controller.tick(_now_msec())
		if _practice_hint.refresh(_controller.state, _local_player_id) or not events.is_empty():
			_publish_authority(events)
	elif _mode == "host" and _host_session != null:
		_host_session.poll()
	elif _mode == "client" and _client_session != null:
		_client_session.poll()
		if _client_session != null and not _pending_view_update.is_empty() and not _reconnect_pending:
			if _client_session.send_view_update(_pending_view_update) != ERR_BUSY:
				_pending_view_update.clear()
	elif _transport != null:
		_transport.poll()


func close() -> void:
	if _closed:
		return
	_closed = true
	_pending_view_update.clear()
	_bot_runner.close()
	_practice_hint.close()
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
	NetworkDiagnostics.log_event("host", "signaling_ready")
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
		if assignment.reconnect_player_id.is_empty():
			_display_names[StringName(peer_id)] = assignment.display_name
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
				if message_id == LEAVE_MESSAGE_ID:
					_finish_requested_leave()
					return
				if message_id == RECONNECT_MESSAGE_ID:
					if bool(result.get("accepted", false)):
						NetworkDiagnostics.log_event("client", "reconnect_accepted")
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
		_client_session.spectator_views_received.connect(func(views: Dictionary):
			if _role == "spectator":
				spectator_views_received.emit(views)
		)
		_client_session.session_failed.connect(_fail)
		if _reconnect_pending:
			NetworkDiagnostics.log_event("client", "reconnect_data_channel_open")
			var reconnect_error: Error = _client_session.submit_command(
				RECONNECT_MESSAGE_ID, {
					"command_id": "runtime-reconnect-%d" % _reconnect_now_msec(),
					"kind": "reconnect", "payload": {"token": _reconnect_token},
				}
			)
			if reconnect_error != OK:
				_fail("reconnect_send_failed")
		else:
			NetworkDiagnostics.log_event("client", "data_channel_open")
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


func _create_authority(ids: Array) -> void:
	var config := _build_config(ids)
	var state := MatchState.create(config, Time.get_ticks_usec(), true)
	state.players[HOST_PLAYER_ID].avatar_id = _local_avatar_id
	state.config.match_started = false
	_controller = MatchController.new(state)


func _create_host_authority(first_peer_id: String = "") -> void:
	var ids := [HOST_PLAYER_ID]
	if not first_peer_id.is_empty():
		ids.append(StringName(first_peer_id))
	_create_authority(ids)
	_host_session = HostNetworkSession.new(
		_controller, _transport, MATCH_ID, HOST_PLAYER_ID, _now,
		HostNetworkSession.DEFAULT_HEARTBEAT_INTERVAL_MSEC,
		HostNetworkSession.DEFAULT_HEARTBEAT_TIMEOUT_MSEC,
		Callable(), Callable(self, "_decorate_network_snapshot")
	)
	_host_session.authoritative_state_changed.connect(_on_authoritative_state_changed)
	if not first_peer_id.is_empty():
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
	var projected := DomainEvent.for_recipient(
		events, _local_player_id, GameTypes.RecipientRole.ACTIVE_PLAYER
	)
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
	if _is_practice:
		_practice_hint.refresh(_controller.state, _local_player_id)
		if not _practice_hint.view.is_empty():
			snapshot["practice_hint"] = _practice_hint.view.duplicate(true)
	snapshot_applied.emit(
		_decorate_snapshot(snapshot, _local_player_id, GameTypes.RecipientRole.ACTIVE_PLAYER),
		_local_sequence
	)


func _on_client_snapshot(snapshot: Dictionary, sequence: int) -> void:
	var rendered := snapshot.duplicate(true)
	if not rendered.has("connection_state"):
		rendered["connection_state"] = {"status": "connected", "reason": ""}
	if not _sent_avatar and not _reconnect_pending and not _local_avatar_id.is_empty():
		_sent_avatar = true
		_client_session.submit_command(AVATAR_MESSAGE_ID, {
			"command_id": "runtime-avatar-command",
			"kind": str(CommandKinds.SET_AVATAR),
			"payload": {"avatar_id": _local_avatar_id},
		})
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
	var settings: Dictionary = snapshot.get("lobby_settings", {})
	if settings.is_empty() and _controller != null:
		settings = _controller.state.config.to_dict()
	var started := bool(settings.get("match_started", false))
	if int(snapshot.get("phase", GameTypes.Phase.START)) != GameTypes.Phase.START:
		started = true
		settings["match_started"] = true
	var players: Array = snapshot.get("players", [])
	var active_count := 0
	var spectator_count := 0
	for player in players:
		if not player is Dictionary:
			continue
		var player_id := StringName(player.get("player_id", ""))
		player["name"] = str(_display_names.get(player_id, _fallback_name(player)))
		player["is_host"] = player_id == HOST_PLAYER_ID
		player["role"] = "spectator" if bool(player.get("spectator", false)) else "active"
		if _bots.has(player_id):
			player["is_bot"] = true
			player["bot_difficulty"] = _bots[player_id]
			if not started:
				player["ready"] = true
				if recipient_id == HOST_PLAYER_ID:
					player["bot_available_avatars"] = _available_bot_avatars(player_id)
		if bool(player.get("spectator", false)):
			spectator_count += 1
		elif bool(player.get("active", false)):
			active_count += 1
	snapshot["players"] = players
	snapshot["room_code"] = _room_code
	snapshot["is_host"] = recipient_id == HOST_PLAYER_ID
	snapshot["is_practice"] = _is_practice
	snapshot["can_add_bot"] = not started and recipient_id == HOST_PLAYER_ID and active_count < 4
	snapshot["local_role"] = (
		"spectator" if recipient_role == GameTypes.RecipientRole.SPECTATOR else "active"
	)
	snapshot["match_started"] = started
	snapshot["screen_id"] = "match" if started else "lobby"
	snapshot["active_player_count"] = active_count
	snapshot["spectator_count"] = spectator_count
	if not started and _controller != null:
		snapshot["lobby_unready_guests"] = _unready_lobby_guest_count()
	snapshot["settings"] = _flatten_settings(settings)
	snapshot["victory_mode"] = snapshot.settings.victory_mode
	snapshot["victory_target"] = snapshot.settings.victory_target
	var active_catalog := _ability_catalog(settings.get("ability_definitions", []))
	var recipe := {}
	for id in active_catalog:
		recipe[id] = active_catalog[id].copies
	var catalog := AbilityCatalog.public_catalog(recipe)
	# Preserve the actual definition metadata when a match supplies custom definitions.
	catalog.merge(active_catalog, true)
	snapshot["ability_catalog"] = catalog
	snapshot["scoring_catalog"] = ScoringReference.catalog_from_config(settings)
	snapshot["settings"]["ability_deck_recipe"] = recipe
	# The catalogue and recipe carry the public deck composition in one entry per design.
	settings.erase("ability_definitions")
	settings["ability_deck_recipe"] = recipe
	snapshot["lobby_settings"] = settings
	snapshot["required_half_count"] = maxi(
		0, 6 - snapshot.get("private_hand", []).size()
	) * 2
	snapshot["connection_state"] = {"status": "connected", "reason": ""}
	return snapshot


func _emit_lobby_snapshot() -> void:
	_local_sequence += 1
	var players: Array = [{
		"player_id": str(HOST_PLAYER_ID), "name": _local_display_name,
		"avatar_id": _local_avatar_id,
		"is_host": true,
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
	var active_count := players.filter(func(player): return not player.spectator and player.connected).size()
	var spectator_count := players.filter(func(player): return player.spectator).size()
	snapshot_applied.emit({
		"screen_id": "lobby", "room_code": _room_code, "is_host": true,
		"can_add_bot": true,
		"match_started": false, "players": players,
		"active_player_count": active_count, "spectator_count": spectator_count,
		"lobby_unready_guests": maxi(active_count - 1, 0),
		"settings": _settings.duplicate(true),
		"ability_catalog": AbilityCatalog.public_catalog(_settings.ability_deck_recipe),
		"scoring_catalog": ScoringReference.default_catalog(),
		"connection": {"status": "connected", "reason": ""},
	}, _local_sequence)


func _on_peer_disconnected(peer_id: String, reason: String) -> void:
	NetworkDiagnostics.log_event(_mode, "peer_disconnected", reason)
	if _mode == "client" and peer_id == "host":
		_fail("host_lost" if reason != "direct_connection_failed" else reason)
	elif _mode == "host" and _peer_assignments.erase(peer_id) and _controller == null:
		_display_names.erase(StringName(peer_id))
		_emit_lobby_snapshot()


func _on_transport_failed(reason: String) -> void:
	NetworkDiagnostics.log_event(_mode, "transport_failed", reason)
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
	if _leave_deadline_msec >= 0:
		_finish_requested_leave()
		return
	var reported_reason := reason
	if (
		reason == "direct_connection_failed" and _transport != null
		and _transport.has_method("has_relay_fallback")
		and not bool(_transport.has_relay_fallback())
	):
		reported_reason = "relay_unavailable"
	_failed = true
	NetworkDiagnostics.log_event(
		_mode, "reconnect_failed" if _reconnect_pending else "session_failed", reported_reason
	)
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
		AbilityCatalog.build_deck(_settings.ability_deck_recipe),
		ScoringReference.normal_definitions(), ContextHandCatalog.definitions(),
		bool(_settings.no_time_limit)
	)


func _default_settings() -> Dictionary:
	return {
		"victory_mode": GameTypes.VictoryMode.SCORE_RACE,
		"victory_target": GameTypes.default_victory_target(GameTypes.VictoryMode.SCORE_RACE),
		"information_visibility": GameTypes.InformationVisibility.PUBLIC,
		"no_time_limit": true,
		"start_timer_msec": 20_000,
		"main_timer_msec": 30_000,
		"hand_timer_msec": 45_000,
		"end_timer_msec": 10_000,
		"reaction_window_msec": 2_000,
		"public_hard_limit_msec": 30_000,
		"reconnect_grace_msec": 30_000,
		"ability_deck_recipe": AbilityCatalog.provisional_deck_recipe(),
	}


func _apply_setting(settings: Dictionary, key: StringName, value: Variant) -> StringName:
	match key:
		&"victory_mode":
			if not value is int or value not in [GameTypes.VictoryMode.SCORE_RACE, GameTypes.VictoryMode.ROUND_WIN_RACE]:
				return &"invalid_victory_mode"
			if value != settings.victory_mode:
				settings.victory_target = GameTypes.default_victory_target(value)
		&"no_time_limit":
			if not value is bool:
				return &"invalid_setting"
		&"information_visibility":
			if not value is int:
				return &"invalid_setting"
		_:
			if not settings.has(str(key)) or not value is int or int(value) <= 0:
				return &"invalid_setting"
	settings[str(key)] = value
	return &""


func _apply_config_setting(config: MatchConfig, key: StringName, value: Variant) -> StringName:
	match key:
		&"victory_mode": return config.set_victory_mode(int(value))
		&"victory_target": return config.set_victory_target(int(value))
		&"no_time_limit": return config.set_no_time_limit(bool(value))
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
	var victory_mode := int(config.get("victory_mode", GameTypes.VictoryMode.SCORE_RACE))
	return {
		"victory_mode": victory_mode,
		"victory_target": int(config.get("victory_target", GameTypes.default_victory_target(victory_mode))),
		"information_visibility": int(config.get("information_visibility", 0)),
		"no_time_limit": bool(config.get("no_time_limit", false)),
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
		if result.has(id):
			result[id].copies += 1
			continue
		var display_name := str(definition.get("display_name", ""))
		result[id] = {
			"id": id,
			"label": display_name if not display_name.is_empty() else id.replace("_", " ").capitalize(),
			"display_name": display_name if not display_name.is_empty() else id.replace("_", " ").capitalize(),
			"rules_text": str(definition.get("rules_text", "")),
			"timing": int(definition.get("timing", -1)),
			"tags": definition.get("tags", []).duplicate(true),
			"field_duration": int(definition.get("field_duration", 0)),
			"effect_id": str(definition.get("effect_id", "noop")),
			"field_rule": str(definition.get("effect_parameters", {}).get("field_rule", "")),
			"context_emblem": int(definition.get("effect_parameters", {}).get("context", -1)),
			"suit_emblem": int(definition.get("effect_parameters", {}).get("suit", -1)),
			"operation": str(definition.get("effect_parameters", {}).get("operation", "")),
			"choice_schema": definition.get("choice_schema", {}).duplicate(true),
			"copies": 1,
		}
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
