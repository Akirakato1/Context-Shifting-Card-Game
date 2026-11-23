extends "res://tests/test_case.gd"

const MATCH_PATH := "res://src/view/match/match_screen.tscn"


func test_display_preserves_a_full_hd_design_canvas() -> void:
	var window: Window = Engine.get_main_loop().root
	assert_eq(window.content_scale_size, Vector2i(1920, 1080))
	assert_eq(window.content_scale_mode, Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
	assert_eq(window.content_scale_aspect, Window.CONTENT_SCALE_ASPECT_KEEP)


func test_display_modes_are_available_from_the_main_menu() -> void:
	var scene_path := "res://src/view/app/app_root.tscn"
	var screen := await _mount_in_host(scene_path, Vector2(1920, 1080))
	screen.get_node("SafeArea/ScreenHost/MainMenuScreen/Content/SettingsButton").pressed.emit()
	var modes := screen.get_node_or_null("SafeArea/ScreenHost/GeneralSettingsScreen/Content/Modes") as OptionButton
	assert_true(modes != null, "The main menu must expose display modes")
	if modes != null:
		assert_eq(modes.item_count, 6)
		assert_eq(modes.get_item_id(modes.item_count - 1), 0)
	await _unmount(screen)


func test_full_table_stays_inside_supported_landscape_sizes() -> void:
	for viewport_size in [Vector2(1280, 720), Vector2(1600, 900), Vector2(1920, 1080), Vector2(2560, 1440)]:
		var table = await _mount_table(viewport_size)
		if table == null:
			return
		table.render(_crowded_model())
		await Engine.get_main_loop().process_frame
		for path in [
			"Header", "TableLayer/TopSeat", "TableLayer/LeftSeat", "TableLayer/RightSeat",
			"Center", "PhaseControls", "AbilityPanel/ToggleButton",
		]:
			_assert_inside(table.get_node(path), Rect2(Vector2.ZERO, viewport_size), "%s at %s" % [path, viewport_size])
		var submit_button: Control = table.get_node("PhaseControls/HandPlayControls/ActionRow/SubmitButton")
		var ability_button: Control = table.get_node("AbilityPanel/ToggleButton")
		assert_false(submit_button.get_global_rect().intersects(ability_button.get_global_rect()), "ability tab overlaps hand action at %s" % viewport_size)
		var hand := table.get_node("PhaseControls/HandPlayControls/Hand/Cards") as HBoxContainer
		assert_eq(hand.get_child_count(), 6)
		for slot: Control in hand.get_children():
			var card := slot.get_child(0) as Control
			_assert_inside(card, Rect2(Vector2.ZERO, viewport_size), "hand card at %s" % viewport_size)
			assert_true(card.size.x >= 200.0 and card.size.y >= 300.0, "hand card should be larger at %s" % viewport_size)
			assert_false(card.get_global_rect().intersects(submit_button.get_global_rect()), "hand overlaps hand action at %s" % viewport_size)
			assert_false(card.get_global_rect().intersects(ability_button.get_global_rect()), "hand overlaps abilities at %s" % viewport_size)
		await _unmount(table)


func test_main_menu_lobby_and_results_root_layouts_fill_viewport() -> void:
	for scene_path in [
		"res://src/view/lobby/main_menu_screen.tscn",
		"res://src/view/lobby/lobby_screen.tscn",
		"res://src/view/results/results_screen.tscn",
	]:
		if not ResourceLoader.exists(scene_path):
			assert_true(false, "%s must exist" % scene_path)
			continue
		var screen = await _mount_in_host(scene_path, Vector2(1280, 720))
		assert_eq(screen.position, Vector2.ZERO)
		assert_eq(screen.size, Vector2(1280, 720))
		await _unmount(screen)


func test_end_shows_each_resolved_hand_at_its_seat_without_overlapping_discards() -> void:
	for viewport_size in [Vector2(1280, 720), Vector2(1920, 1080)]:
		var table = await _mount_table(viewport_size)
		var model := _crowded_model()
		model.phase = 5
		model["required_ability_discards"] = 1
		model["public_history"] = [{
			"kind": "round_finalized", "round_number": 8,
			"payload": {"round_number": 8, "winner_id": "p1", "scores": {"p1": 20}},
		}]
		for player: Dictionary in model.players:
			var cards: Array = []
			for index in 6:
				cards.append({
					"card_id": "%s-%d" % [player.player_id, index], "selected_half_index": 0,
					"halves": [
						{"context": 0, "rank": 10, "suit": 0},
						{"context": 1, "rank": 9, "suit": 2},
					],
				})
			player["revealed_submission"] = {"cards": cards, "finalized_score": 20}
		table.render(model)
		await Engine.get_main_loop().process_frame
		await Engine.get_main_loop().process_frame
		var discards: Control = table.get_node("PhaseControls/EndControls")
		assert_true(discards.is_visible_in_tree())
		assert_false(table.get_node("PhaseControls/HandPlayControls").is_visible_in_tree())
		var seats := {"BottomSeat": "p1", "TopSeat": "p2", "LeftSeat": "p3", "RightSeat": "p4"}
		var shown_cards: Array[Control] = []
		for position: String in seats:
			var seat = table.get_node("TableLayer/" + position)
			assert_true(seat.is_visible_in_tree())
			var hand: Control = seat.get_node("Hand")
			assert_eq(hand.get_child_count(), 6)
			for card: Control in hand.get_children():
				assert_true(card.is_visible_in_tree())
				assert_true(card.card_id.begins_with(seats[position]))
				assert_false(card.face_down)
				_assert_inside(card, Rect2(Vector2.ZERO, viewport_size), card.card_id)
				assert_false(card.get_global_rect().intersects(discards.get_global_rect()))
				for other in shown_cards:
					assert_false(card.get_global_rect().intersects(other.get_global_rect()))
				shown_cards.append(card)
		model.erase("private_player_id")
		model.erase("private_hand")
		table.render(model)
		assert_true(table.get_node("TableLayer/BottomSeat/Hand").is_visible_in_tree())
		await _unmount(table)


func _assert_inside(control: Control, bounds: Rect2, label: String) -> void:
	var rect := control.get_global_rect()
	assert_true(bounds.encloses(rect), "%s escaped viewport: %s" % [label, rect])


func _crowded_model() -> Dictionary:
	var hand: Array = []
	for index in 6:
		hand.append({
			"card_id": "c%d" % index,
			"first": _half(0, index + 1, index % 3),
			"second": _half((index % 2) + 1, 10 - index, (index + 1) % 3),
		})
	var players: Array = []
	for index in 4:
		players.append({
			"player_id": "p%d" % (index + 1),
			"name": "Player With A Very Long Name %d" % (index + 1),
			"seat_index": index, "spectator": false, "active": true,
			"connected": true, "ready": index % 2 == 0, "hand_count": 6,
			"ability_count": 3, "match_score": 20 - index, "round_wins": index,
		})
	for index in 4:
		players.append({
			"player_id": "s%d" % index, "name": "Spectator %d" % index,
			"seat_index": -1, "spectator": true, "active": false, "connected": true,
		})
	var fields: Array = []
	for index in 5:
		fields.append({"ability_id": "persistent_field_%d" % index, "source_player_id": "p1", "remaining_rounds": index + 1})
	return {
		"phase": 3, "round_number": 8, "active_context": 0, "context_direction": -1,
		"phase_deadline_msec": 30000, "now_msec": 10000,
		"private_player_id": "p1", "private_hand": hand,
		"private_abilities": [
			{"copy_id": "a1", "ability_id": "reshape"},
			{"copy_id": "a2", "ability_id": "pair_boost"},
			{"copy_id": "a3", "ability_id": "reverse_clock"},
		],
		"ability_catalog": {
			"reshape": {"label": "Reshape", "timing": 0, "choice_schema": {}},
			"pair_boost": {"label": "Pair Boost", "timing": 2, "choice_schema": {}},
			"reverse_clock": {"label": "Reverse Clock", "timing": 1, "choice_schema": {}},
		},
		"private_staging": {"pending_manipulation": {}, "staged_submission": [], "hand_locked": false},
		"players": players, "active_fields": fields, "frozen": false,
		"victory_mode": 0, "victory_target": 100,
		"pile_counts": {"0": {"draw_count": 65}, "1": {"draw_count": 66}, "2": {"draw_count": 67}},
	}


func _half(context: int, rank: int, suit: int) -> Dictionary:
	return {"effective_context": context, "effective_rank": rank, "effective_suit": suit, "kind": 0}


func _mount_table(viewport_size: Vector2) -> Variant:
	if not ResourceLoader.exists(MATCH_PATH):
		assert_true(false, "%s must exist" % MATCH_PATH)
		return null
	return await _mount_in_host(MATCH_PATH, viewport_size)


func _mount_in_host(scene_path: String, viewport_size: Vector2) -> Control:
	var host := Control.new()
	host.name = "TestViewportHost"
	host.set_anchors_preset(Control.PRESET_TOP_LEFT)
	host.position = Vector2.ZERO
	host.size = viewport_size
	Engine.get_main_loop().root.add_child(host)
	var node: Control = load(scene_path).instantiate()
	host.add_child(node)
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await Engine.get_main_loop().process_frame
	return node


func _unmount(node: Node) -> void:
	var parent := node.get_parent()
	if parent != null and parent.name == "TestViewportHost":
		parent.queue_free()
	else:
		node.queue_free()
	await Engine.get_main_loop().process_frame
