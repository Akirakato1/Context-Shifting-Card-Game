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
		var phase_motion: Tween = table.get_node("PhaseBadge").get("_motion")
		phase_motion.custom_step(1.0)
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
	var score_style := table.get_node("MatchScore").get_theme_stylebox("panel") as StyleBoxTexture
	assert_eq(score_style.texture.resource_path.get_file(), "button_2.png")
	var context_style := table.get_node("SortControls/Rise").get_theme_stylebox("normal") as StyleBoxTexture
	assert_eq(context_style.texture.resource_path.get_file(), "button_3.png")
	assert_false(table.get_node("SortControls/Rise").disabled)
	table.queue_free()
	await Engine.get_main_loop().process_frame


func test_table_art_covers_the_hotbar_seam_and_uses_context_shades() -> void:
	var scene := load("res://src/view/match/match_screen.tscn") as PackedScene
	var table := scene.instantiate()
	Engine.get_main_loop().root.add_child(table)
	var scenery := table.get_node("TableScenery")
	var constants: Dictionary = scenery.get_script().get_script_constant_map()
	var rect: Rect2 = constants.get("TABLE_RECT", Rect2())
	assert_eq(rect.get_center().x, 960.0)
	assert_eq(constants.get("TABLE_SHADE_OPACITY", 0.0), 0.5)
	var board: Texture2D = scenery.get("table_art")
	assert_true(board != null)
	if board != null:
		assert_eq(board.resource_path.get_file(), "board.png")
		var source: Rect2 = scenery.get("table_source_region")
		var board_layer := scenery.get_node("BoardArt") as TextureRect
		var shade_layer := scenery.get_node("ContextShade") as ColorRect
		var design_size: Vector2 = constants["BASE"]
		var view_scale: Vector2 = scenery.size / design_size
		var scale_per_pixel := board_layer.size / board.get_size()
		assert_eq(board_layer.texture, board, "Render the full board texture, including both lower rails")
		assert_eq(shade_layer.get_rect(), board_layer.get_rect())
		var shade_material := shade_layer.material as ShaderMaterial
		for context in ["rise", "flourish", "fall"]:
			assert_eq(shade_material.get_shader_parameter(context + "_region"), Vector4(0, 0, 1, 1))
		assert_true((board_layer.position + source.position * scale_per_pixel).is_equal_approx(rect.position * view_scale))
		assert_true((board_layer.position + source.end * scale_per_pixel).is_equal_approx(rect.end * view_scale))
		var board_pixels := board.get_image()
		var seam_row := floori(source.position.y + (709.0 - rect.position.y) / rect.size.y * source.size.y)
		for fraction in [0.25, 0.5, 0.75]:
			var column := floori(source.position.x + source.size.x * fraction)
			assert_true(board_pixels.get_pixel(column, seam_row).a > 0.95, "Table art should reach the hotbar")
		for rail_column in [210, 2865]:
			assert_true(board_pixels.get_pixel(rail_column, seam_row).a > 0.95,
				"Both wooden rails extend beyond the reference region at the hotbar")
	var shades: Array = scenery.get("table_shading") if scenery.get("table_shading") != null else []
	assert_eq(shades.map(func(texture: Texture2D): return texture.resource_path.get_file()), [
		"board_shade_blue.png", "board_shade_green.png", "board_shade_red.png",
	])
	var surfaces := {"lower_bar_art": "card_area_bg.png", "hand_tray_art": "card_area.png"}
	for surface: String in surfaces:
		var artwork := scenery.get(surface) as Texture2D
		assert_true(artwork != null and artwork.resource_path.get_file() == surfaces[surface])
	var drawer := table.get_node("AbilityPanel/Drawer") as PanelContainer
	var drawer_art := drawer.get_theme_stylebox("panel") as StyleBoxTexture
	assert_true(drawer_art != null and drawer_art.texture != null and drawer_art.texture.resource_path.get_file() == "ability_card_bg.png")
	var tray := scenery.get_node("HandTrayArt") as TextureRect
	assert_eq(tray.texture, scenery.get("hand_tray_art"))
	assert_eq(tray.material, drawer.material)
	var button_assets := {
		"MenuButton": "button_4.png",
		"MatchMenu/Options/Settings": "button_4.png",
		"HelpButton": "button_3.png",
		"PhaseControls/MainControls/ReadyButton": "button_4.png",
	}
	for button_path: String in button_assets:
		var button := table.get_node(button_path) as Button
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style := button.get_theme_stylebox(state) as StyleBoxTexture
			assert_true(style != null and style.texture.resource_path.get_file() == button_assets[button_path])
	var menu := table.get_node("MatchMenu") as PanelContainer
	var history: Button = table.get_node("AbilityHistory/Toggle")
	assert_eq(history.icon.resource_path.get_file(), "history_scroll.png")
	assert_eq(history.text, "")
	var clock_bounds: Rect2 = scenery.call("clock_rect")
	var clock_center := clock_bounds.get_center()
	var history_center := history.get_global_rect().get_center()
	assert_true(history_center.x > clock_center.x and history_center.y > clock_center.y)
	assert_false(history.get_global_rect().intersects(tray.get_global_rect()))
	assert_true(table.get_node("Header/Timer").get_global_rect().position.x > table.get_node("PhaseBadge").get_global_rect().end.x)
	var round_badge: PhaseSign = table.get_node("RoundBadge")
	assert_true(round_badge.get_node("UpperChains").position.y + round_badge.resting_y <= 0.0)
	assert_true(round_badge.get_index() < table.get_node("PhaseBadge").get_index())
	assert_eq(menu.get_theme_stylebox("panel").texture.resource_path.get_file(), "button_5.png")
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
	model.private_hand.append({
		"card_id": "joker", "first": _half(0, 4),
		"second": {"kind": 1, "base_context": 2, "joker_context": 1, "joker_suit": 2},
		"eligible_half_indexes": [0, 1],
	})
	table.render(model)
	assert_true(controls.card_widget(&"joker").orientation_flipped)
	assert_eq(controls.local_hand_order(), [&"joker", &"up", &"flip", &"rise"])
	table.queue_free()
	await Engine.get_main_loop().process_frame


func _half(context: int, rank: int) -> Dictionary:
	return {"kind": 0, "effective_context": context, "effective_rank": rank, "effective_suit": 0}


func test_drag_reorders_the_hand_without_staging_cards() -> void:
	var model := _hand_drag_model()
	var table := _open_hand_drag_table(model)
	var controls = table.get_node("PhaseControls")
	table.get_node("SortControls/Rise").pressed.emit()
	await Engine.get_main_loop().process_frame
	var view := table.get_viewport()
	var card: Control = controls.card_widget(&"a")
	var neighbor: Control = controls.card_widget(&"b")
	var source := card.get_global_rect().get_center()
	var neighbor_start := neighbor.get_global_rect().get_center()
	var destination: Vector2 = controls.card_widget(&"c").get_global_rect().get_center()
	_push_hand_click(view, source, true)
	var before_center := neighbor_start - Vector2(12, 0)
	_push_hand_motion(view, source, before_center)
	assert_true(view.gui_is_dragging())
	assert_true(not card.is_visible_in_tree() or is_zero_approx(card.modulate.a), "The hand shows a gap while the card is attached to the cursor")
	await Engine.get_main_loop().create_timer(0.20).timeout
	assert_eq(neighbor.get_global_rect().get_center(), neighbor_start, "A card stays put until the pointer reaches its center")
	_push_hand_motion(view, before_center, destination)
	assert_eq(neighbor.get_global_rect().get_center(), neighbor_start, "The neighbor starts its slide from the current position")
	await Engine.get_main_loop().create_timer(0.25).timeout
	assert_true(neighbor.get_global_rect().get_center().distance_to(source) < 1.0, "The neighbor has slid into the gap before release")
	assert_eq(controls.local_hand_order(), [&"a", &"b", &"c"], "Hovering keeps the committed order")
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
	await Engine.get_main_loop().process_frame
	var right_click := InputEventMouseButton.new()
	right_click.position = controls.card_widget(&"a").get_global_rect().get_center()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.button_mask = MOUSE_BUTTON_MASK_RIGHT
	right_click.pressed = true
	view.push_input(right_click, true)
	assert_eq(controls.staged_selection(&"a").get("half_index"), 1)
	right_click.button_mask = 0
	right_click.pressed = false
	view.push_input(right_click, true)
	table.queue_free()
	await Engine.get_main_loop().process_frame


func test_drag_released_outside_hand_restores_card_and_sorted_order() -> void:
	var table := _open_hand_drag_table(_hand_drag_model())
	var controls = table.get_node("PhaseControls")
	var sorter: Button = table.get_node("SortControls/Rise")
	sorter.pressed.emit()
	await Engine.get_main_loop().process_frame
	var view := table.get_viewport()
	var source: Vector2 = controls.card_widget(&"c").get_global_rect().get_center()
	var destination: Vector2 = controls.card_widget(&"a").get_global_rect().get_center() - Vector2(8, 0)
	var neighbor_start: Vector2 = controls.card_widget(&"b").get_global_rect().get_center()
	_push_hand_click(view, source, true)
	_push_hand_motion(view, source, destination)
	await Engine.get_main_loop().create_timer(0.25).timeout
	var neighbor_during_drag: Vector2 = controls.card_widget(&"b").get_global_rect().get_center()
	assert_true(neighbor_during_drag.distance_to(source) < 1.0, "Dragging left moves the neighbor right")
	var outside := Vector2(400, 400)
	_push_hand_motion(view, destination, outside)
	_push_hand_click(view, outside, false)
	await Engine.get_main_loop().create_timer(0.25).timeout
	var restored: Control = controls.card_widget(&"c")
	assert_true(restored.is_visible_in_tree() and is_equal_approx(restored.modulate.a, 1.0))
	assert_true(restored.get_global_rect().get_center().is_equal_approx(source))
	assert_true(controls.card_widget(&"b").get_global_rect().get_center().is_equal_approx(neighbor_start))
	assert_eq(controls.local_hand_order(), [&"a", &"b", &"c"])
	assert_true(sorter.button_pressed)
	assert_false(controls.has_staged_card(&"c"))
	table.queue_free()
	await Engine.get_main_loop().process_frame


func _hand_drag_model() -> Dictionary:
	return {
		"phase": 3, "active_context": 0, "active_contexts": [0, 1], "private_player_id": "p1",
		"private_hand": [
			{"card_id": "a", "first": _half(0, 2), "second": _half(1, 3)},
			{"card_id": "b", "first": _half(0, 4), "second": _half(1, 5)},
			{"card_id": "c", "first": _half(0, 6), "second": _half(1, 7)},
		],
	}


func _open_hand_drag_table(model: Dictionary) -> Control:
	var scene := load("res://src/view/match/match_screen.tscn") as PackedScene
	var table: Control = scene.instantiate()
	Engine.get_main_loop().root.add_child(table)
	table.render(model)
	return table


func _push_hand_motion(view: Viewport, from: Vector2, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.relative = point - from
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	view.push_input(event, true)


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
	assert_eq(opening.get("private_abilities", []).size(), 3)
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
				controls.get_node("HandPlayControls/ActionRow/SubmitButton").pressed.emit()
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


func test_practice_non_winning_end_waits_for_bots_when_the_host_is_done() -> void:
	var scene := load("res://src/view/app/app_root.tscn") as PackedScene
	var app = scene.instantiate()
	Engine.get_main_loop().root.add_child(app)
	app.start_practice()
	var session = app._session
	var state: MatchState = session._controller.state
	state.phase = GameTypes.Phase.END
	state.players[&"host"].round_wins = 2
	for player_id in state.seat_order:
		var player = state.players[player_id]
		state.ability_deck.discard(player.ability_hand.pop_back())
		if player_id != &"host":
			player.ability_hand.append_array(state.ability_deck.draw(player_id, 3, state.rng))
		player.end_discard_complete = player.ability_hand.size() <= state.ability_deck.end_hand_limit
	session._publish()

	assert_eq(app.current_screen_id(), &"match")
	assert_eq(state.players[&"host"].ability_hand.size(), 2)
	var controls: Control = app.get_node("SafeArea/ScreenHost").get_child(0).get_node("PhaseControls")
	assert_eq(controls.get_node("EndControls/Required").text, "Waiting for other players to discard…")
	assert_false(controls.get_node("EndControls/AbilityChoices").is_visible_in_tree())
	assert_false(controls.get_node("EndControls/ConfirmButton").is_visible_in_tree())

	session._next_bot_move = 0
	session.poll()
	assert_eq(state.phase, GameTypes.Phase.START)
	assert_eq(app.current_screen_id(), &"match")
	for player_id in state.seat_order:
		assert_eq(state.players[player_id].ability_hand.size(), 2)
	app.queue_free()
	await Engine.get_main_loop().process_frame


func _wait_for_phase(app, phase: int) -> bool:
	var deadline := Time.get_ticks_msec() + 5_000
	while Time.get_ticks_msec() < deadline:
		if int(app.presentation_state.private_state().get("phase", -1)) == phase:
			return true
		await Engine.get_main_loop().create_timer(0.04).timeout
	return false
