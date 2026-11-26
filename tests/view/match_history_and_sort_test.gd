extends "res://tests/test_case.gd"

const MatchScene := preload("res://src/view/match/match_screen.tscn")


func test_history_opens_upward_and_lists_named_public_plays_and_scores() -> void:
	var table := MatchScene.instantiate()
	Engine.get_main_loop().root.add_child(table)
	table.render({
		"phase": 2, "round_number": 3,
		"players": [{"player_id": "p1", "name": "Mira"}, {"player_id": "p2", "name": "Ren"}],
		"ability_catalog": {"pair_breaker": {"display_name": "Pair Breaker"}},
		"public_history": [
			{"kind": "public_ability_played", "round_number": 2, "payload": {
				"ability_id": "pair_breaker", "source_player_id": "p1", "target_player_id": "p2",
				"hidden_test_value": "private_copy_419",
			}},
			{"kind": "round_finalized", "round_number": 2, "payload": {
				"winner_id": "p2", "scores": {"p1": 12, "p2": 30}, "points_awarded": 18,
			}},
			{"kind": "context_changed", "round_number": 3, "payload": {"context": 1}},
		],
	})
	var drawer: Control = table.get_node_or_null("AbilityHistory/Drawer")
	assert_true(drawer != null)
	if drawer != null:
		var toggle: Button = table.get_node("AbilityHistory/Toggle")
		assert_false(drawer.visible)
		var motion := InputEventMouseMotion.new()
		motion.position = toggle.get_global_transform_with_canvas() * (toggle.size * 0.5)
		table.get_viewport().push_input(motion, true)
		assert_eq(table.get_viewport().gui_get_hovered_control(), toggle)
		toggle.pressed.emit()
		await Engine.get_main_loop().process_frame
		assert_true(drawer.visible)
		assert_true(drawer.get_global_rect().end.y <= toggle.get_global_rect().position.y)
		var rows := drawer.get_node("Margin/Layout/Scroll/Rows")
		var latest := rows.get_child(0) as VBoxContainer
		var previous := rows.get_child(1) as VBoxContainer
		assert_true(latest != null and previous != null, "History separates turns into sections")
		if latest != null and previous != null:
			assert_eq(latest.get_node("Heading").text, "ROUND 3")
			assert_true(latest.get_child(2).get_parsed_text().begins_with("Clock moved to"))
			assert_eq(previous.get_node("Heading").text, "ROUND 2")
			assert_true(previous.get_child(0) is HSeparator)
			assert_true(previous.get_child(2).text.contains("Ren wins"))
			assert_true(previous.get_child(2).text.contains("+18 match points"))
			assert_true(previous.get_child(2).text.contains("Ren 30"))
			assert_true(previous.get_child(3).text.contains("Mira → Ren"))
			assert_false(previous.get_child(3).text.contains("private_copy_419"))
		toggle.pressed.emit()
		assert_false(drawer.visible)
	table.queue_free()
	await Engine.get_main_loop().process_frame


func test_help_stacks_over_history_and_match_menu_blocks_the_table() -> void:
	var table := MatchScene.instantiate() as Control
	var window: Window = Engine.get_main_loop().root
	window.add_child(table)
	table.get_node("AbilityHistory/Toggle").pressed.emit()
	table.get_node("HelpButton").pressed.emit()
	var rules: Control = table.get_node("RulesAndCardsModal")
	var history: Control = table.get_node("AbilityHistory")
	var drawer: Control = history.get_node("Drawer")
	assert_true(rules.visible and drawer.visible)
	assert_true(rules.z_index > history.z_index, "History draws below the rules panel")
	rules.close()
	assert_true(drawer.visible)
	var menu_button: Button = table.get_node("MenuButton")
	var menu: Control = table.get_node("MatchMenu")
	var dimmer := table.get_node_or_null("MatchMenuDimmer") as ColorRect
	assert_true(dimmer != null, "The match menu has a backdrop")
	if dimmer != null:
		assert_false(dimmer.visible)
		menu_button.pressed.emit()
		await Engine.get_main_loop().process_frame
		assert_true(menu.visible and dimmer.visible)
		assert_true(menu.z_index > dimmer.z_index and dimmer.z_index > history.z_index)
		assert_true(dimmer.get_global_rect().encloses(table.get_global_rect()))
		var outside_point := table.get_global_rect().position + Vector2(40, table.size.y * 0.5)
		var motion := InputEventMouseMotion.new()
		motion.position = outside_point
		window.push_input(motion, true)
		assert_eq(window.gui_get_hovered_control(), dimmer)
		var settings: Button = menu.get_node("Options/Settings")
		motion.position = settings.get_global_rect().get_center()
		window.push_input(motion, true)
		assert_eq(window.gui_get_hovered_control(), settings)
		var outside := InputEventMouseButton.new()
		outside.button_index = MOUSE_BUTTON_LEFT
		outside.position = outside_point
		outside.pressed = true
		window.push_input(outside, true)
		outside.pressed = false
		window.push_input(outside, true)
		assert_false(menu.visible or dimmer.visible)
		menu_button.pressed.emit()
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		window.push_input(escape, true)
		assert_false(menu.visible or dimmer.visible)
	table.queue_free()
	await Engine.get_main_loop().process_frame


func test_practice_match_menu_stays_centered_with_separate_options_in_every_phase() -> void:
	var table := MatchScene.instantiate() as MatchScreen
	Engine.get_main_loop().root.add_child(table)
	var menu: PanelContainer = table.get_node("MatchMenu")
	var toggle: Button = table.get_node("MenuButton")
	var settings: Button = menu.get_node("Options/Settings")
	var leave: Button = menu.get_node("Options/Leave")
	for phase in [GameTypes.Phase.START, GameTypes.Phase.MAIN_1, GameTypes.Phase.HAND_PLAY,
		GameTypes.Phase.MAIN_2, GameTypes.Phase.END]:
		table.render({"phase": phase, "round_number": 1, "is_practice": true, "private_player_id": "host"})
		toggle.pressed.emit()
		await Engine.get_main_loop().process_frame
		assert_true(menu.visible)
		assert_true(menu.get_global_rect().get_center().is_equal_approx(table.get_global_rect().get_center()))
		assert_false(settings.get_global_rect().intersects(leave.get_global_rect()))
		assert_false(menu.get_global_rect().intersects(toggle.get_global_rect()))
		assert_true(settings.has_focus(), "Keyboard navigation starts at Settings")
		var focus := settings.get_theme_stylebox("focus") as StyleBoxFlat
		assert_true(focus != null and focus.border_width_bottom > 0
			and focus.border_width_top == 0 and focus.border_width_left == 0 and focus.border_width_right == 0)
		toggle.pressed.emit()
	table.queue_free()
	await Engine.get_main_loop().process_frame


func test_context_sort_buttons_use_emblems_and_show_the_rank_direction() -> void:
	var table := MatchScene.instantiate()
	Engine.get_main_loop().root.add_child(table)
	var rise: Button = table.get_node("SortControls/Rise")
	var rank: Button = table.get_node("SortControls/Rank")
	assert_true(rise.icon != null)
	assert_eq(rise.text, "↕")
	rise.pressed.emit()
	assert_eq(rise.text, "↑")
	rank.pressed.emit()
	assert_eq(rise.text, "↓")
	table.queue_free()
	await Engine.get_main_loop().process_frame


func test_ability_drawer_reaches_the_viewport_edge_outside_safe_area() -> void:
	var table := MatchScene.instantiate() as Control
	Engine.get_main_loop().root.add_child(table)
	table.offset_left = 24
	table.offset_top = 20
	table.offset_right = -24
	await Engine.get_main_loop().process_frame
	var drawer: Control = table.get_node("AbilityPanel/Drawer")
	assert_true(is_equal_approx(drawer.get_global_rect().end.x, table.get_viewport_rect().end.x))
	assert_true(is_zero_approx(drawer.get_global_rect().position.y))
	table.queue_free()
	await Engine.get_main_loop().process_frame
