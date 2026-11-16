extends "res://tests/test_case.gd"

const MAIN_MENU_PATH := "res://src/view/lobby/main_menu_screen.tscn"
const LOBBY_PATH := "res://src/view/lobby/lobby_screen.tscn"


func test_main_menu_normalizes_join_code_and_blocks_duplicate_confirmation() -> void:
	var menu = await _mount(MAIN_MENU_PATH)
	if menu == null:
		return
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


func test_non_host_cannot_edit_or_start_and_host_needs_two_players() -> void:
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
	lobby.render(_lobby_model(true, false, 2, 0))
	lobby.get_node("Layout/Footer/StartButton").pressed.emit()
	lobby.get_node("Layout/Footer/StartButton").pressed.emit()
	assert_eq(starts.size(), 1)
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
	assert_true(status.contains("try again"))
	assert_true(lobby.get_node("Layout/StatusPanel/RetryButton").visible)
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
