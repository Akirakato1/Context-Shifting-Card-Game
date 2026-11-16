extends "res://tests/test_case.gd"

const APP_PATH := "res://src/view/app/app_root.tscn"


func test_app_starts_on_menu_and_can_present_each_mock_screen() -> void:
	var app = await _mount_app()
	if app == null:
		return
	assert_eq(app.current_screen_id(), &"menu")
	assert_eq(app.get_node("SafeArea/ScreenHost").get_child(0).name, "MainMenuScreen")

	app.show_screen(&"lobby", _lobby_model())
	assert_eq(app.current_screen_id(), &"lobby")
	assert_eq(app.get_node("SafeArea/ScreenHost").get_child(0).get_node("Layout/Header/RoomCode").text, "ROOM  ABC234")

	app.show_screen(&"match", _match_model())
	assert_eq(app.current_screen_id(), &"match")
	assert_eq(app.get_node("SafeArea/ScreenHost").get_child(0).get_node("Header/Round").text, "ROUND 1")

	var complete := _match_model()
	complete["match_complete"] = true
	complete["winner_id"] = "p1"
	complete["end_reason"] = "victory_target"
	complete["room_code"] = "ABC234"
	complete["is_host"] = true
	app.present_state(complete)
	assert_eq(app.current_screen_id(), &"results")
	assert_eq(app.get_node("SafeArea/ScreenHost").get_child(0).get_node("Layout/Title").text, "MIRA WINS")
	await _unmount(app)


func test_results_return_to_lobby_preserves_room_and_unlocks_settings() -> void:
	var app = await _mount_app()
	if app == null:
		return
	var complete := _match_model()
	complete["match_complete"] = true
	complete["winner_id"] = "p1"
	complete["end_reason"] = "victory_target"
	complete["room_code"] = "ABC234"
	complete["is_host"] = true
	app.show_screen(&"results", complete)
	var results = app.get_node("SafeArea/ScreenHost").get_child(0)
	results.get_node("Layout/Actions/LobbyButton").pressed.emit()
	assert_eq(app.current_screen_id(), &"lobby")
	var lobby = app.get_node("SafeArea/ScreenHost").get_child(0)
	assert_eq(lobby.get_node("Layout/Header/RoomCode").text, "ROOM  ABC234")
	assert_true(lobby.get_node("Layout/Body/Settings/VictoryTarget").editable)
	await _unmount(app)


func test_startup_smoke_writes_marker_only_after_native_webrtc_initializes() -> void:
	var app = load(APP_PATH).instantiate()
	var marker_path := "user://startup-smoke-test.txt"
	if FileAccess.file_exists(marker_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(marker_path))
	var result: int = app.write_startup_smoke_marker(marker_path)
	assert_eq(result, OK)
	assert_true(FileAccess.file_exists(marker_path))
	var marker := FileAccess.get_file_as_string(marker_path)
	assert_true(marker.contains("startup_ok"))
	assert_true(marker.contains("webrtc_ok"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(marker_path))
	app.free()


func _lobby_model() -> Dictionary:
	return {
		"is_host": true, "room_code": "ABC234", "match_started": false,
		"active_player_count": 2, "spectator_count": 0,
		"players": [{"name": "Mira", "role": "active", "ready": true}, {"name": "North", "role": "active", "ready": false}],
		"settings": {
			"victory_mode": 0, "victory_target": 20, "information_visibility": 0,
			"start_timer_msec": 5000, "main_timer_msec": 10000,
			"hand_timer_msec": 30000, "end_timer_msec": 5000,
			"reconnect_grace_msec": 30000,
		},
		"connection": {"status": "connected", "reason": ""},
	}


func _match_model() -> Dictionary:
	return {
		"phase": 2, "round_number": 1, "active_context": 0, "context_direction": 1,
		"phase_deadline_msec": 10000, "now_msec": 0, "reaction_deadline_msec": -1,
		"private_player_id": "p1", "private_hand": [], "private_abilities": [],
		"private_staging": {"pending_manipulation": {}, "staged_submission": [], "hand_locked": false},
		"players": [
			{"player_id": "p1", "name": "Mira", "seat_index": 0, "spectator": false, "active": true, "connected": true, "ready": false, "hand_count": 0, "match_score": 21, "round_wins": 2},
			{"player_id": "p2", "name": "North", "seat_index": 1, "spectator": false, "active": true, "connected": true, "ready": false, "hand_count": 6, "match_score": 15, "round_wins": 1},
		],
		"active_fields": [], "frozen": false, "victory_mode": 0, "victory_target": 20,
		"pile_counts": {"0": {"draw_count": 70}, "1": {"draw_count": 70}, "2": {"draw_count": 70}},
	}


func _mount_app() -> Variant:
	if not ResourceLoader.exists(APP_PATH):
		assert_true(false, "%s must exist" % APP_PATH)
		return null
	var node = load(APP_PATH).instantiate()
	Engine.get_main_loop().root.add_child(node)
	await Engine.get_main_loop().process_frame
	return node


func _unmount(node: Node) -> void:
	node.queue_free()
	await Engine.get_main_loop().process_frame
