extends "res://tests/test_case.gd"

const APP_PATH := "res://src/view/app/app_root.tscn"
const GameTypes = preload("res://src/core/common/game_types.gd")
const AbilityCatalog := preload("res://src/core/abilities/ability_catalog.gd")
const AbilityState := preload("res://src/core/abilities/ability_state.gd")


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


func test_menu_opens_separate_create_and_join_forms_and_returns() -> void:
	var app = await _mount_app()
	var host: Control = app.get_node("SafeArea/ScreenHost")
	var button := host.get_node_or_null("MainMenuScreen/Content/CreateLobbyButton") as Button
	assert_true(button != null, "The main menu must expose Create Lobby")
	if button != null:
		button.pressed.emit()
		assert_eq(app.current_screen_id(), &"create_lobby")
		assert_true(host.get_child(0).get_node("Content/PlayerName").visible)
		assert_false(host.get_child(0).get_node("Content/JoinPanel").visible)
		var back: Button = host.get_child(0).get_node("Content/BackButton")
		back.pressed.emit()
		assert_eq(app.current_screen_id(), &"menu")
		host.get_child(0).get_node("Content/JoinLobbyButton").pressed.emit()
		assert_eq(app.current_screen_id(), &"join_lobby")
		assert_true(host.get_child(0).get_node("Content/JoinPanel").visible)
		assert_false(host.get_child(0).get_node("Content/HostButton").visible)
	await _unmount(app)


func test_general_settings_opens_and_closes_without_replacing_the_menu() -> void:
	var app = await _mount_app()
	var host: Control = app.get_node("SafeArea/ScreenHost")
	var menu := host.get_child(0)
	var button := menu.get_node_or_null("Content/SettingsButton") as Button
	assert_true(button != null, "The main menu must expose Settings")
	if button != null:
		button.pressed.emit()
		assert_eq(host.get_child(0), menu)
		var settings := host.get_node_or_null("GeneralSettingsScreen")
		assert_true(settings != null)
		if settings != null:
			settings.get_node("Content/BackButton").pressed.emit()
			assert_eq(host.get_child_count(), 1)
	await _unmount(app)


func test_general_settings_update_match_speed_and_save_audio_levels() -> void:
	var path := "res://src/view/app/gameplay_preferences.gd"
	if not ResourceLoader.exists(path):
		assert_true(false, "Gameplay preferences need to survive app restarts")
		return
	var preference_script := load(path)
	var saved := "user://shift-test-gameplay-%d.cfg" % Time.get_ticks_usec()
	var prefs = preference_script.new(saved)
	var app = load(APP_PATH).instantiate()
	app.gameplay_preferences = prefs
	Engine.get_main_loop().root.add_child(app)
	app.show_screen(&"match", _match_model())
	var host: Control = app.get_node("SafeArea/ScreenHost")
	var table := host.get_child(0)
	table.settings_requested.emit()
	var settings: Control = host.get_node("GeneralSettingsScreen")
	var speed: OptionButton = settings.get_node("Content/DrawSpeed")
	assert_eq(speed.get_item_text(speed.get_selected()), "1.0×")
	speed.select(speed.get_item_index(2))
	speed.item_selected.emit(speed.get_selected())
	var ambient: HSlider = settings.get_node("Content/Ambient/Slider")
	var effects: HSlider = settings.get_node("Content/SoundEffects/Slider")
	var music: HSlider = settings.get_node("Content/Music/Slider")
	ambient.value = 0
	effects.value = 50
	music.value = 25

	var ambient_bus := AudioServer.get_bus_index(&"Ambient")
	var effects_bus := AudioServer.get_bus_index(&"Sound Effects")
	var music_bus := AudioServer.get_bus_index(&"Music")
	assert_true(AudioServer.is_bus_mute(ambient_bus))
	assert_true(is_equal_approx(AudioServer.get_bus_volume_db(effects_bus), linear_to_db(0.5)))
	assert_true(is_equal_approx(AudioServer.get_bus_volume_db(music_bus), linear_to_db(0.25)))
	assert_eq(table.get_node("DrawAnimation").get("playback_speed"), 2.0)
	var restored = preference_script.new(saved)
	assert_eq(restored.draw_speed, 2)
	assert_eq(restored.volume(&"Ambient"), 0)
	assert_eq(restored.volume(&"Sound Effects"), 50)
	assert_eq(restored.volume(&"Music"), 25)
	await _unmount(app)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved))
	preference_script.new(saved).apply_audio()


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


func test_practice_button_starts_a_match_and_can_open_settings_or_return() -> void:
	var app = await _mount_app()
	var host: Control = app.get_node("SafeArea/ScreenHost")
	host.get_child(0).get_node("Content/PracticeButton").pressed.emit()
	assert_eq(app.current_screen_id(), &"match")
	if app.current_screen_id() == &"match":
		var table := host.get_child(0)
		table.settings_requested.emit()
		assert_eq(host.get_child(0), table)
		assert_true(host.has_node("GeneralSettingsScreen"))
		host.get_node("GeneralSettingsScreen/Content/BackButton").pressed.emit()
		table.leave_requested.emit()
		assert_eq(app.current_screen_id(), &"menu")
		assert_false(host.has_node("GeneralSettingsScreen"))
	await _unmount(app)


func test_live_sabotage_projects_a_different_animation_for_each_audience() -> void:
	var app = await _mount_app()
	var session := FakeSession.new()
	app.bind_session(session)
	var model := _match_model()
	model["screen_id"] = "match"
	model["ability_catalog"] = AbilityCatalog.public_catalog({})
	var common := {"ability_id": "rank_scramble", "source_player_id": "p1", "target_player_id": "p2"}
	var public_event := {"kind": "sabotage_resolved", "payload": common}
	var face := {"effective_context": 0, "effective_rank": 4, "effective_suit": 0}
	var after := face.merged({"effective_rank": 8}, true)
	var changes := [{"before": {"first": face, "second": face},
		"after": {"first": after, "second": face}, "half_index": 0}]
	for local_id in ["p1", "p2", ""]:
		model["private_player_id"] = local_id
		app.show_screen(&"match", model)
		var screen: Control = app.get_node("SafeArea/ScreenHost").get_child(0)
		var effects: Control = screen.get_node("AbilityEffects")
		var events := [public_event]
		if local_id == "p1":
			events.append({"kind": "sabotage_resolved", "payload": common.merged({"success": true})})
		elif local_id == "p2":
			events.append({"kind": "sabotage_resolved", "payload": common.merged({"card_changes": changes})})
		var sequence: int = app.presentation_state.sequence() + 1
		session.events_applied.emit(events, sequence)
		session.snapshot_applied.emit(model, sequence)
		var title: Label = effects.get_node("EffectTitle")
		var detail: Label = effects.get_node("EffectDetail")
		var cards: Array = effects.get("_cards")
		assert_eq(title.text, "Sabotage" if local_id.is_empty() else "Rank Scramble")
		assert_true(detail.text.contains("Mira → North"))
		assert_eq(cards.size(), 0 if local_id.is_empty() else 1)
		assert_eq(effects.get("_pending").size(), 0)
		var timeline: Tween = effects.get("_timeline")
		if timeline != null:
			timeline.pause()
			if not cards.is_empty():
				assert_eq(cards[0].face_down, local_id == "p1")
				if local_id == "p2":
					assert_true(cards[0].first_face_text().contains("4"))
					timeline.custom_step(1.4)
					assert_true(cards[0].first_face_text().contains("8"))
			timeline.custom_step(3.0)
		assert_false(title.visible)
		session.snapshot_applied.emit(model, sequence + 1)
		assert_false(title.visible, "A snapshot must not replay the live animation")
	await _unmount(app)


func test_practice_public_field_uses_the_live_clock_animation() -> void:
	var app = await _mount_app()
	app.start_practice()
	var practice: Variant = app.get("_session")
	var state: Variant = practice.get("_controller").state
	var host: Variant = state.players[&"host"]
	var field: Variant
	for copy in state.ability_deck.get("_all_cards").values():
		if copy.definition.id == &"reverse_cycle":
			field = copy
			break
	assert_true(field != null)
	if field != null:
		state.ability_deck.get("_draw_cards").erase(field)
		for player in state.players.values():
			player.ability_hand.erase(field)
		field.move_to(AbilityState.Zone.HAND, &"host")
		host.ability_hand.append(field)
		var screen: Control = app.get_node("SafeArea/ScreenHost").get_child(0)
		var effects: Control = screen.get_node("AbilityEffects")
		practice._submit_local("field", {"command_id": "field", "kind": "play_public_ability",
			"payload": {"copy_id": str(field.copy_id), "choices": {}}})
		assert_eq(state.context_direction, -1)
		assert_eq(effects.get_node("EffectTitle").text, "Reverse Cycle")
		var clock: Control = screen.get_node("TableScenery/ContextClock")
		assert_eq(clock.get("_direction"), -1)
		var reversal: Tween = clock.get("_direction_tween")
		assert_true(reversal != null)
		if reversal != null:
			reversal.pause()
			reversal.custom_step(0.12)
			var reverse_art := clock.get_node("ReverseCycle") as TextureRect
			assert_true(reverse_art.self_modulate.a > 0.0 and reverse_art.self_modulate.a < 1.0)
		assert_eq(effects.get("_pending").size(), 0)
		assert_eq(effects.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	await _unmount(app)


func test_observer_gets_a_brief_nerf_and_no_manipulation_animation() -> void:
	var app = await _mount_app()
	var model := _match_model()
	model["private_player_id"] = "p2"
	model.players.append({"player_id": "p3", "name": "West", "seat_index": 2,
		"active": true, "connected": true, "spectator": false})
	app.show_screen(&"match", model)
	var screen: Control = app.get_node("SafeArea/ScreenHost").get_child(0)
	var effects: Control = screen.get_node("AbilityEffects")
	screen.present_ability_events([
		{"kind": "manipulation_resolved", "payload": {"ability_id": "mirror_rank",
			"source_player_id": "p1", "card_changes": []}},
		{"kind": "factor_modifier_applied", "payload": {"source_definition_id": "family_nerf",
			"source_player_id": "p1", "target_player_id": "p3", "category_id": "family",
			"numerator": -2, "denominator": 1}},
	])
	assert_eq(effects.get_node("EffectTitle").text, "Nerf applied")
	assert_false(effects.get_node("EffectDetail").visible)
	assert_eq(effects.get("_cards").size(), 0)
	assert_eq(effects.get("_pending").size(), 0)
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
	controls.get_node("HandPlayControls/ActionRow/SubmitButton").pressed.emit()
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
