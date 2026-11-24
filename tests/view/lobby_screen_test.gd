extends "res://tests/test_case.gd"

const MAIN_MENU_PATH := "res://src/view/lobby/main_menu_screen.tscn"
const LOBBY_PATH := "res://src/view/lobby/lobby_screen.tscn"


func test_lobby_settings_page_stays_open_when_roster_snapshot_updates() -> void:
	var lobby = await _mount(LOBBY_PATH)
	lobby.render(_lobby_model(true, false, 2, 0))
	var settings := lobby.get_node_or_null("Layout/Footer/SettingsButton") as Button
	assert_true(settings != null, "The lobby must expose Lobby Settings")
	if settings != null:
		settings.pressed.emit()
		lobby.render(_lobby_model(true, false, 3, 0))
		assert_true(lobby.get_node("Layout/Body/Settings").visible)
		assert_false(lobby.get_node("Layout/Body/Roster").visible)
		settings.pressed.emit()
		assert_true(lobby.get_node("Layout/Body/Roster").visible)
		assert_false(lobby.get_node("Layout/Body/Settings").visible)
	await _unmount(lobby)


func test_main_menu_normalizes_join_code_and_blocks_duplicate_confirmation() -> void:
	var menu = await _mount(MAIN_MENU_PATH)
	if menu == null:
		return
	var logo := menu.get_node_or_null("Content/Logo") as TextureRect
	assert_true(logo != null and logo.is_visible_in_tree())
	if logo != null:
		assert_eq((logo.texture as AtlasTexture).atlas.resource_path, "res://assets/artwork/logo.png")
		assert_false(menu.get_node("Content/Title").visible)
		menu.set_page(&"join_lobby")
		assert_false(logo.visible)
		assert_true(menu.get_node("Content/Title").visible)
	var joins: Array[Dictionary] = []
	menu.join_requested.connect(func(name: String, code: String, role: String):
		joins.append({"name": name, "code": code, "role": role})
	)
	menu.get_node("Content/PlayerName").text = "  Mira  "
	menu.get_node("Content/JoinPanel/JoinFields/Code").text = " ab-c234 "
	menu.get_node("Content/JoinPanel/JoinFields/Role").select(1)
	menu.get_node("Content/JoinPanel/JoinFields/JoinButton").pressed.emit()
	menu.get_node("Content/JoinPanel/JoinFields/JoinButton").pressed.emit()
	assert_eq(joins, [{"name": "Mira", "code": "ABC234", "role": "spectator"}])
	assert_true(menu.get_node("Content/HostButton").disabled)
	assert_true(menu.get_node("Content/JoinPanel/JoinFields/JoinButton").disabled)
	await _unmount(menu)


func test_no_time_limit_disables_phase_deadlines_and_shows_the_victory_target() -> void:
	var lobby = await _mount(LOBBY_PATH)
	var model := _lobby_model(true, false, 2, 0)
	model.settings.no_time_limit = true
	model.settings.victory_target = 1_000
	lobby.render(model)
	var settings: Control = lobby.get_node("Layout/Body/Settings")
	var toggle := settings.get_node_or_null("NoTimeLimit") as CheckButton
	assert_true(toggle != null)
	assert_eq(settings.get_node("VictoryTarget").value, 1_000.0)
	assert_false(settings.get_node("StartTimer").editable)
	assert_false(settings.get_node("HandTimer").editable)
	assert_false(settings.get_node("HardLimitTimer").editable)
	assert_true(settings.get_node("ReconnectTimer").editable)
	if toggle != null:
		assert_true(toggle.button_pressed)
		var changes: Array = []
		lobby.setting_change_requested.connect(func(key: StringName, value: Variant):
			changes.append([key, value])
		)
		toggle.set_pressed(false)
		assert_eq(changes, [[&"no_time_limit", false]])
		model.is_host = false
		lobby.render(model)
		assert_true(toggle.disabled)
	await _unmount(lobby)


func test_host_lobby_shows_code_counts_and_editable_settings_until_start() -> void:
	var lobby = await _mount(LOBBY_PATH)
	if lobby == null:
		return
	var changes: Array[Dictionary] = []
	lobby.setting_change_requested.connect(func(key: StringName, value: Variant):
		changes.append({"key": key, "value": value})
	)
	lobby.render(_lobby_model(true, false, 2, 1))
	assert_eq(lobby.get_node("Layout/Header/RoomCode").text, "ROOM  ABC234")
	assert_eq(lobby.get_node("Layout/Body/Roster/Counts").text, "2 / 4 players   •   1 / 4 spectators")
	assert_false(lobby.get_node("Layout/Body/Settings/VictoryTarget").editable == false)
	assert_false(lobby.get_node("Layout/Footer/StartButton").disabled)

	lobby.get_node("Layout/Body/Settings/VictoryTarget").value = 25
	assert_eq(changes[-1], {"key": &"victory_target", "value": 25})
	assert_false(lobby.has_node("Layout/Body/Settings/BaseScoreMode"))
	lobby.get_node("Layout/Body/Settings/ReactionTimer").value = 3.5
	assert_eq(changes[-1], {"key": &"reaction_window_msec", "value": 3500})
	lobby.get_node("Layout/Body/Settings/HardLimitTimer").value = 45
	assert_eq(changes[-1], {"key": &"public_hard_limit_msec", "value": 45000})
	lobby.render(_lobby_model(true, true, 2, 1))
	var change_count := changes.size()
	lobby.get_node("Layout/Body/Settings/VictoryTarget").value = 30
	assert_eq(changes.size(), change_count)
	assert_false(lobby.get_node("Layout/Body/Settings/VictoryTarget").editable)
	assert_true(lobby.get_node("Layout/Footer/StartButton").disabled)
	await _unmount(lobby)


func test_only_the_host_can_start_and_must_wait_for_guests_to_ready_up() -> void:
	var lobby = await _mount(LOBBY_PATH)
	if lobby == null:
		return
	var starts: Array[bool] = []
	lobby.start_requested.connect(func(): starts.append(true))
	lobby.render(_lobby_model(false, false, 2, 0))
	assert_false(lobby.get_node("Layout/Body/Settings/VictoryTarget").editable)
	assert_false(lobby.get_node("Layout/Footer/StartButton").visible)

	lobby.render(_lobby_model(true, false, 1, 0))
	assert_true(lobby.get_node("Layout/Footer/StartButton").disabled)
	lobby.get_node("Layout/Footer/StartButton").pressed.emit()
	assert_eq(starts.size(), 0)
	var waiting := _lobby_model(true, false, 2, 1)
	waiting.lobby_unready_guests = 1
	waiting.players[1].ready = false
	lobby.render(waiting)
	assert_true(lobby.get_node("Layout/Footer/StartButton").disabled)
	assert_true(lobby.get_node("Layout/StatusPanel/Status").text.contains("ready up"))
	lobby.get_node("Layout/Footer/StartButton").pressed.emit()
	assert_eq(starts.size(), 0)
	lobby.render(_lobby_model(true, false, 2, 0))
	lobby.get_node("Layout/Footer/StartButton").pressed.emit()
	lobby.get_node("Layout/Footer/StartButton").pressed.emit()
	assert_eq(starts.size(), 1)
	await _unmount(lobby)


func test_lobby_ready_control_is_only_for_active_guests() -> void:
	var lobby = await _mount(LOBBY_PATH)
	var ready: CheckButton = lobby.get_node("Layout/Footer/ReadyButton")
	var requests: Array[bool] = []
	lobby.ready_requested.connect(func(value: bool): requests.append(value))

	lobby.render(_lobby_model(true, false, 2, 0))
	assert_false(ready.visible)
	assert_true(lobby.get_node("Layout/Footer/StartButton").visible)
	ready.toggled.emit(true)
	assert_eq(requests, [])

	var guest := _lobby_model(false, false, 2, 1)
	lobby.render(guest)
	assert_true(ready.visible)
	ready.toggled.emit(true)
	assert_eq(requests, [true])

	guest["local_role"] = "spectator"
	lobby.render(guest)
	assert_false(ready.visible)
	ready.toggled.emit(true)
	assert_eq(requests, [true])
	await _unmount(lobby)


func test_lobby_errors_are_actionable_without_exposing_network_internals() -> void:
	var lobby = await _mount(LOBBY_PATH)
	if lobby == null:
		return
	lobby.render(_lobby_model(false, false, 2, 4))
	lobby.show_error(&"spectator_slots_full")
	var status: String = lobby.get_node("Layout/StatusPanel/Status").text.to_lower()
	assert_true(status.contains("spectator"))
	assert_true(status.contains("full"))
	assert_false(status.contains("ip"))
	assert_false(status.contains("webrtc"))
	lobby.show_error(&"direct_connection_failed")
	status = lobby.get_node("Layout/StatusPanel/Status").text.to_lower()
	assert_true(status.contains("direct and relay"))
	assert_true(status.contains("try again"))
	assert_true(lobby.get_node("Layout/StatusPanel/RetryButton").visible)
	lobby.show_error(&"relay_unavailable")
	status = lobby.get_node("Layout/StatusPanel/Status").text.to_lower()
	assert_true(status.contains("relay fallback"))
	assert_true(lobby.get_node("Layout/StatusPanel/RetryButton").visible)
	await _unmount(lobby)


func test_guest_shortcut_toggles_ready_only_when_control_is_available() -> void:
	var lobby = await _mount(LOBBY_PATH)
	assert_true(lobby.has_method("trigger_ready_shortcut"))
	if not lobby.has_method("trigger_ready_shortcut"):
		await _unmount(lobby)
		return
	var requests: Array[bool] = []
	lobby.ready_requested.connect(func(value: bool): requests.append(value))
	var guest := _lobby_model(false, false, 2, 0)
	lobby.render(guest)
	assert_true(lobby.trigger_ready_shortcut())
	assert_true(lobby.trigger_ready_shortcut())
	assert_eq(requests, [true, false])

	lobby.get_node("Layout/Footer/SettingsButton").pressed.emit()
	assert_false(lobby.trigger_ready_shortcut())
	lobby.get_node("Layout/Footer/SettingsButton").pressed.emit()
	lobby.render(_lobby_model(false, true, 2, 0))
	assert_false(lobby.trigger_ready_shortcut())
	lobby.render(_lobby_model(true, false, 2, 0))
	assert_false(lobby.trigger_ready_shortcut())
	assert_eq(requests, [true, false])
	await _unmount(lobby)


func _lobby_model(
	is_host: bool,
	match_started: bool,
	active_count: int,
	spectator_count: int
) -> Dictionary:
	return {
		"is_host": is_host,
		"room_code": "ABC234",
		"match_started": match_started,
		"active_player_count": active_count,
		"lobby_unready_guests": 0,
		"spectator_count": spectator_count,
		"players": [
			{"name": "Host", "role": "active", "ready": true},
			{"name": "Guest", "role": "active", "ready": false},
		],
		"settings": {
			"victory_mode": 0,
			"victory_target": 10,
			"information_visibility": 0,
			"start_timer_msec": 5000,
			"main_timer_msec": 5000,
			"hand_timer_msec": 15000,
			"end_timer_msec": 3000,
			"reaction_window_msec": 2000,
			"public_hard_limit_msec": 30000,
			"reconnect_grace_msec": 30000,
		},
		"connection": {"status": "connected", "reason": ""},
	}


func _mount(path: String) -> Variant:
	if not ResourceLoader.exists(path):
		assert_true(false, "%s must exist" % path)
		return null
	var node = load(path).instantiate()
	Engine.get_main_loop().root.add_child(node)
	await Engine.get_main_loop().process_frame
	return node


func _unmount(node: Node) -> void:
	node.queue_free()
	await Engine.get_main_loop().process_frame
