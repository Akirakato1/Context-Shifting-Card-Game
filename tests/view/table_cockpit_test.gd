extends "res://tests/test_case.gd"


func test_cockpit_keeps_card_rectangles_between_phases() -> void:
	var scene := load("res://src/view/match/match_screen.tscn") as PackedScene
	var table: Control = scene.instantiate()
	Engine.get_main_loop().root.add_child(table)
	var controls = table.get_node("PhaseControls")
	var model := {"phase": 2, "private_player_id": "p1", "active_context": 0,
		"private_hand": [{"card_id": "a", "first": _half(0, 2), "second": _half(1, 3)}]}
	table.render(model)
	await Engine.get_main_loop().process_frame
	var card: Control = controls.card_widget(&"a")
	assert_true(card != null and card.is_visible_in_tree(), "The local hand is visible in Main 1")
	if card != null:
		var original := card.get_global_rect()
		model.phase = 3
		table.render(model)
		await Engine.get_main_loop().process_frame
		assert_eq(controls.card_widget(&"a").get_global_rect(), original)
		assert_eq(table.get_node("PhaseBadge/Phase").text, "HAND PLAY")
		var factors: HBoxContainer = controls.get_node("HandPlayControls/Preview/Factors")
		var colors := {"Base": "#ffffff", "Hand": "#8ac7ff", "Context": "#ff9393", "Field": "#99dfaa"}
		for key: String in colors:
			var value: Label = factors.get_node(key + "Value")
			assert_eq(value.get_theme_color("font_color"), Color(colors[key]))
	table.queue_free()
	await Engine.get_main_loop().process_frame


func test_match_can_hide_the_sketch_guides_without_disabling_controls() -> void:
	var scene := load("res://src/view/match/match_screen.tscn") as PackedScene
	var table = scene.instantiate()
	table.show_placeholder_guides = false
	Engine.get_main_loop().root.add_child(table)
	assert_false(table.get_node("Backdrop").visible)
	assert_false(table.get_node("TableScenery").show_placeholder_guides)
	assert_true(table.get_node("MatchScore").get_theme_stylebox("panel") is StyleBoxEmpty)
	assert_eq(table.get_node("SortControls/Rise").get_child_count(), 0)
	assert_false(table.get_node("SortControls/Rise").disabled)
	table.queue_free()
	await Engine.get_main_loop().process_frame


func test_top_half_is_the_scoring_half_and_selected_card_keeps_its_slot() -> void:
	var scene := load("res://src/view/match/match_screen.tscn") as PackedScene
	var table: Control = scene.instantiate()
	Engine.get_main_loop().root.add_child(table)
	var model := {
		"phase": 3, "active_context": 0, "active_contexts": [0, 1],
		"private_player_id": "p1",
		"private_hand": [
			{"card_id": "a", "first": _half(2, 1), "second": _half(0, 2), "eligible_half_indexes": [1]},
			{"card_id": "b", "first": _half(0, 3), "second": _half(1, 4), "eligible_half_indexes": [0, 1]}
		],
		"private_staging": {}
	}
	table.render(model)
	await Engine.get_main_loop().process_frame
	var controls = table.get_node("PhaseControls")
	var slot_index: int = controls.card_widget(&"b").get_parent().get_index()
	controls.click_card(&"b")
	assert_true(controls.has_staged_card(&"b"))
	assert_eq(controls.card_widget(&"b").get_parent().get_index(), slot_index)
	controls.right_click_card(&"b")
	assert_eq(controls.staged_selection(&"b").get("half_index"), 1)
	controls.right_click_card(&"a")
	assert_true(controls.card_widget(&"a").orientation_flipped)
	controls.click_card(&"b")
	assert_false(controls.has_staged_card(&"b"))
	table.queue_free()
	await Engine.get_main_loop().process_frame


func test_context_sort_groups_cards_with_the_matching_half_facing_up() -> void:
	var scene := load("res://src/view/match/match_screen.tscn") as PackedScene
	var table: Control = scene.instantiate()
	Engine.get_main_loop().root.add_child(table)
	var model := {
		"phase": 3, "active_context": 0, "active_contexts": [0, 1], "private_player_id": "p1",
		"private_hand": [
			{"card_id": "rise", "first": _half(0, 5), "second": _half(2, 1), "eligible_half_indexes": [0]},
			{"card_id": "flip", "first": _half(0, 2), "second": _half(1, 8), "eligible_half_indexes": [0, 1]},
			{"card_id": "up", "first": _half(1, 7), "second": _half(2, 3), "eligible_half_indexes": [0]},
		],
	}
	table.render(model)
	var controls = table.get_node("PhaseControls")
	var rank: Button = table.get_node("SortControls/Rank")
	rank.pressed.emit()
	assert_eq(controls.local_hand_order(), [&"up", &"rise", &"flip"])
	rank.pressed.emit()
	assert_eq(controls.local_hand_order(), [&"flip", &"rise", &"up"])
	controls.click_card(&"flip")
	table.get_node("SortControls/Flourish").pressed.emit()
	assert_eq(controls.local_hand_order(), [&"up", &"flip", &"rise"])
	assert_true(controls.card_widget(&"flip").orientation_flipped)
	assert_false(controls.card_widget(&"up").orientation_flipped)
	assert_eq(controls.staged_selection(&"flip").get("half_index"), 1)
	rank.pressed.emit()
	assert_eq(rank.text, "RANK ↓")
	assert_true(table.get_node("SortControls/Flourish").button_pressed)
	assert_eq(controls.local_hand_order(), [&"flip", &"up", &"rise"])
	assert_eq(controls.staged_selection(&"flip").get("half_index"), 1)
	rank.pressed.emit()
	assert_eq(rank.text, "RANK ↑")
	assert_eq(controls.local_hand_order(), [&"up", &"flip", &"rise"])
	model.active_contexts = [0]
	model.private_hand[1].eligible_half_indexes = [0]
	model.private_hand[2].eligible_half_indexes = []
	model.phase = 2
	table.render(model)
	model.phase = 3
	table.render(model)
	controls.right_click_card(&"flip")
	controls.click_card(&"flip")
	table.get_node("SortControls/Flourish").pressed.emit()
	assert_eq(controls.local_hand_order(), [&"up", &"flip", &"rise"])
	assert_false(controls.card_widget(&"flip").orientation_flipped)
	assert_eq(controls.staged_selection(&"flip").get("half_index"), 0)
	controls.click_card(&"flip")
	table.get_node("SortControls/Flourish").pressed.emit()
	assert_true(controls.card_widget(&"flip").orientation_flipped)
	controls.click_card(&"flip")
	assert_false(controls.has_staged_card(&"flip"))
	table.queue_free()
	await Engine.get_main_loop().process_frame


func _half(context: int, rank: int) -> Dictionary:
	return {"kind": 0, "effective_context": context, "effective_rank": rank, "effective_suit": 0}


func test_drag_reorders_the_hand_without_staging_cards() -> void:
	var scene := load("res://src/view/match/match_screen.tscn") as PackedScene
	var table: Control = scene.instantiate()
	Engine.get_main_loop().root.add_child(table)
	var controls = table.get_node("PhaseControls")
	var model := {
		"phase": 3, "active_context": 0, "private_player_id": "p1",
		"private_hand": [
			{"card_id": "a", "first": _half(0, 2), "second": _half(1, 3)},
			{"card_id": "b", "first": _half(0, 4), "second": _half(1, 5)},
			{"card_id": "c", "first": _half(0, 6), "second": _half(1, 7)},
		],
	}
	table.render(model)
	table.get_node("SortControls/Rise").pressed.emit()
	await Engine.get_main_loop().process_frame
	var view := table.get_viewport()
	var source: Vector2 = controls.card_widget(&"a").get_global_rect().get_center()
	var destination: Vector2 = controls.card_widget(&"c").get_global_rect().get_center()
	_push_hand_click(view, source, true)
	var motion := InputEventMouseMotion.new()
	motion.position = destination
	motion.relative = destination - source
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	view.push_input(motion, true)
	_push_hand_click(view, destination, false)
	assert_eq(controls.local_hand_order(), [&"b", &"c", &"a"])
	assert_false(controls.has_staged_card(&"a"))
	assert_false(table.get_node("SortControls/Rise").button_pressed)
	table.render(model)
	assert_eq(controls.local_hand_order(), [&"b", &"c", &"a"])
	await Engine.get_main_loop().process_frame
	var click: Vector2 = controls.card_widget(&"a").get_global_rect().get_center()
	_push_hand_click(view, click, true)
	_push_hand_click(view, click, false)
	assert_true(controls.has_staged_card(&"a"))
	table.queue_free()
	await Engine.get_main_loop().process_frame


func _push_hand_click(view: Viewport, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	view.push_input(event, true)


func test_practice_menu_uses_the_live_controller_through_hand_reveal() -> void:
	var scene := load("res://src/view/app/app_root.tscn") as PackedScene
	var app = scene.instantiate()
	Engine.get_main_loop().root.add_child(app)
	app.start_practice()
	var opening: Dictionary = app.presentation_state.private_state()
	assert_eq(opening.get("victory_mode"), 1)
	assert_eq(opening.get("local_role"), "active")
	assert_eq(opening.get("private_player_id"), "host")
	assert_false(opening.has("replacement_requests"))
	assert_eq(opening.get("phase"), GameTypes.Phase.MAIN_1)
	assert_eq(opening.get("private_abilities", []).size(), 2)
	var table: Control = app.get_node("SafeArea/ScreenHost").get_child(0)
	var controls = table.get_node("PhaseControls")
	assert_eq(table.get_node("Header/Timer").text, "UNTIMED")
	var controller = app._session._controller
	controller.tick(Time.get_ticks_msec())
	assert_true(controller.tick(Time.get_ticks_msec() + 600_000).is_empty())
	assert_eq(controller.state.phase, GameTypes.Phase.MAIN_1)
	var main_one: bool = controller.state.phase == GameTypes.Phase.MAIN_1
	if main_one:
		controls.get_node("MainControls/ReadyButton").pressed.emit()
		var hand_play := await _wait_for_phase(app, 3)
		assert_true(hand_play)
		if hand_play:
			var model: Dictionary = app.presentation_state.private_state()
			assert_eq(model.get("phase_deadline_msec"), -1)
			assert_true(controller.tick(Time.get_ticks_msec() + 600_000).is_empty())
			assert_eq(controller.state.phase, 3)
			var submitted_id := &""
			for card: Dictionary in model.private_hand:
				if card.eligible_half_indexes.is_empty() or card.first.kind == 1 or card.second.kind == 1:
					continue
				submitted_id = StringName(card.card_id)
				controls.card_widget(submitted_id).primary_clicked.emit(submitted_id)
				assert_true(controls.has_staged_card(submitted_id))
				controls.get_node("HandPlayControls/ActionRow/LockButton").pressed.emit()
				break
			var main_two := await _wait_for_phase(app, 4)
			assert_true(main_two, "Practice should send and lock the submission against the real controller")
			if main_two:
				assert_true(table.get_node("RoundReveal").visible)
				assert_true(not submitted_id.is_empty())
				assert_eq(controls.local_hand_order().size(), model.private_hand.size() - 1)
				assert_false(submitted_id in controls.local_hand_order())
				var revealed: Array = app.presentation_state.private_state().players.filter(func(player): return player.has("revealed_submission"))
				assert_eq(revealed.size(), 4)
	app.queue_free()
	await Engine.get_main_loop().process_frame


func _wait_for_phase(app, phase: int) -> bool:
	var deadline := Time.get_ticks_msec() + 5_000
	while Time.get_ticks_msec() < deadline:
		if int(app.presentation_state.private_state().get("phase", -1)) == phase:
			return true
		await Engine.get_main_loop().create_timer(0.04).timeout
	return false
