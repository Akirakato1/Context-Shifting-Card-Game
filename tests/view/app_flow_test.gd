extends "res://tests/test_case.gd"

const APP_PATH := "res://src/view/app/app_root.tscn"
const GameTypes = preload("res://src/core/common/game_types.gd")


class FakeSession extends RefCounted:
	signal snapshot_applied(snapshot: Dictionary, sequence: int)
	signal events_applied(events: Array, sequence: int)
	signal command_result_received(request_message_id: String, result: Dictionary)
	signal session_failed(reason: String)

	var submissions: Array[Dictionary] = []
	var start_calls := 0

	func submit_command(message_id: String, command: Dictionary) -> Error:
		submissions.append({"message_id": message_id, "command": command.duplicate(true)})
		return OK

	func poll() -> void:
		pass

	func start_match() -> Error:
		start_calls += 1
		return OK


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
	complete["phase"] = GameTypes.Phase.COMPLETE
	complete["winner_id"] = "p1"
	complete["end_reason"] = "victory_target"
	complete["room_code"] = "ABC234"
	complete["is_host"] = true
	app.present_state(complete)
	assert_eq(app.current_screen_id(), &"results")
	assert_eq(app.get_node("SafeArea/ScreenHost").get_child(0).get_node("Layout/Title").text, "MIRA WINS")
	await _unmount(app)


func test_lobby_start_does_not_auto_ready_host_in_main_one() -> void:
	var app = await _mount_app()
	if app == null:
		return
	var session := FakeSession.new()
	app.bind_session(session)
	app.show_screen(&"lobby", _lobby_model())
	var lobby = app.get_node("SafeArea/ScreenHost").get_child(0)
	lobby.get_node("Layout/Footer/StartButton").pressed.emit()

	assert_eq(session.start_calls, 1)
	assert_eq(session.submissions, [])
	await _unmount(app)


func test_winning_end_stays_on_match_until_discards_complete() -> void:
	var app = await _mount_app()
	if app == null:
		return
	app.show_screen(&"match", _match_model())
	var end_state := _match_model()
	end_state["screen_id"] = "match"
	end_state["phase"] = GameTypes.Phase.END
	end_state["match_complete"] = true
	end_state["winner_id"] = "p1"
	end_state["required_ability_discards"] = 2
	app.present_state(end_state)
	assert_eq(app.current_screen_id(), &"match")

	end_state["phase"] = GameTypes.Phase.COMPLETE
	app.present_state(end_state)
	assert_eq(app.current_screen_id(), &"results")
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


func test_authoritative_screen_id_routes_lobby_then_match_without_mock_calls() -> void:
	var app = await _mount_app()
	if app == null:
		return
	var lobby := _lobby_model()
	lobby["screen_id"] = "lobby"
	app.present_state(lobby)
	assert_eq(app.current_screen_id(), &"lobby")

	var match_model := _match_model()
	match_model["screen_id"] = "match"
	app.present_state(match_model)
	assert_eq(app.current_screen_id(), &"match")
	assert_eq(
		app.get_node("SafeArea/ScreenHost").get_child(0).get_node("Header/Round").text,
		"ROUND 1"
	)
	await _unmount(app)


func test_connection_banner_uses_player_friendly_failure_text() -> void:
	var app = await _mount_app()
	if app == null:
		return
	var session := FakeSession.new()
	app.bind_session(session)
	session.session_failed.emit("direct_connection_failed")
	var banner: PanelContainer = app.get_node("SafeArea/ConnectionBanner")
	var label: Label = app.get_node("SafeArea/ConnectionBanner/Label")
	assert_true(banner.visible)
	assert_true(label.text.contains("direct and relay"))
	assert_false(label.text.contains("direct_connection_failed"))
	session.session_failed.emit("relay_unavailable")
	assert_true(label.text.contains("relay fallback was unavailable"))
	await _unmount(app)


func test_app_routes_stage_ack_back_to_match_and_sends_followup_lock() -> void:
	var app = await _mount_app()
	if app == null:
		return
	var session := FakeSession.new()
	app.bind_session(session)
	var model := _match_model()
	model["screen_id"] = "match"
	model["phase"] = 3
	model["private_hand"] = [{
		"card_id": "c1",
		"first": {"effective_context": 0, "effective_rank": 7, "effective_suit": 0, "kind": 0},
		"second": {"effective_context": 1, "effective_rank": 4, "effective_suit": 2, "kind": 0},
	}]
	app.present_state(model)
	var controls = app.get_node("SafeArea/ScreenHost").get_child(0).get_node("PhaseControls")
	controls.click_card(&"c1")
	controls.get_node("HandPlayControls/ActionRow/LockButton").pressed.emit()
	assert_eq(session.submissions.size(), 1)
	assert_eq(session.submissions[0].command.kind, "stage_hand")
	session.command_result_received.emit(session.submissions[0].message_id, {
		"accepted": true, "error_code": "",
	})
	assert_eq(session.submissions.size(), 2)
	assert_eq(session.submissions[1].command.kind, "lock_hand")
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
