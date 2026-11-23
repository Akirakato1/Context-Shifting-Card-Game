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
				"winner_id": "p2", "scores": {"p1": 12, "p2": 30},
			}},
		],
	})
	var drawer: Control = table.get_node_or_null("AbilityHistory/Drawer")
	assert_true(drawer != null)
	if drawer != null:
		var toggle: Button = table.get_node("AbilityHistory/Toggle")
		assert_false(drawer.visible)
		toggle.pressed.emit()
		await Engine.get_main_loop().process_frame
		assert_true(drawer.visible)
		assert_true(drawer.get_global_rect().end.y <= toggle.get_global_rect().position.y)
		var rows := drawer.get_node("Margin/Layout/Scroll/Rows")
		assert_true(rows.get_child(0).text.contains("Ren wins"))
		assert_true(rows.get_child(0).text.contains("Ren 30"))
		assert_true(rows.get_child(1).text.contains("Mira → Ren"))
		assert_false(rows.get_child(1).text.contains("private_copy_419"))
		toggle.pressed.emit()
		assert_false(drawer.visible)
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
