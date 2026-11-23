extends "res://tests/test_case.gd"

const OVERLAY := preload("res://src/view/match/targeting_overlay.tscn")
const SEAT := preload("res://src/view/match/player_seat.tscn")
const BOARD_TARGETS := preload("res://src/view/match/table_ability_targets.gd")


func test_player_workflow_uses_board_inputs_without_the_legacy_dimmer() -> void:
	var overlay := OVERLAY.instantiate() as TargetingOverlay
	Engine.get_main_loop().root.add_child(overlay)
	var commits: Array[Dictionary] = []
	overlay.commit_requested.connect(func(choices: Dictionary): commits.append(choices))
	var target_workflow := {"steps": [{"key": "target_player_id", "kind": "player", "count": 1}]}
	var players := [{"player_id": "north", "display_name": "North"}]
	overlay.begin(target_workflow, [], players, true)
	assert_eq(overlay.get_node("Panel/Layout/Options").get_child_count(), 0)
	assert_false(overlay.get_node("Dimmer").visible)
	overlay.select_value("unavailable")
	assert_true(commits.is_empty())
	overlay.select_value("north")
	assert_eq(commits, [{"target_player_id": ["north"]}])
	overlay.queue_free()
	await Engine.get_main_loop().process_frame


func test_card_selection_stays_highlightable_in_the_next_step() -> void:
	var overlay := OVERLAY.instantiate() as TargetingOverlay
	Engine.get_main_loop().root.add_child(overlay)
	overlay.begin({"steps": [
		{"key": "card", "kind": "full_card", "count": 1},
		{"key": "half_index", "kind": "half_index", "count": 1, "eligible": [0, 1]},
	]}, [{"card_id": "card-a"}], [], true)
	overlay.select_value("card-a")
	assert_eq(overlay.hand_choice_values(), ["card-a"])
	assert_eq(overlay.current_step_index(), 1)
	assert_eq(overlay.get_node("Panel/Layout/Options").get_child_count(), 0)
	overlay.queue_free()
	await Engine.get_main_loop().process_frame


func test_board_targets_only_accept_the_lit_areas_after_priming() -> void:
	var targets := BOARD_TARGETS.new()
	targets.size = Vector2(1920, 1080)
	Engine.get_main_loop().root.add_child(targets)
	var selected: Array[String] = []
	targets.target_requested.connect(func(player_id: String): selected.append(player_id))
	var seats := {&"top": "north", &"bottom": "local"}
	targets.set_targets(seats, ["local"], [], false)
	assert_eq(targets.target_rects().size(), 1)
	var local_point := Vector2(965, 678)
	targets._gui_input(_click(local_point))
	assert_true(selected.is_empty())

	targets.set_targets(seats, ["local"], [], true)
	assert_true(targets._has_point(local_point))
	assert_false(targets._has_point(Vector2(965, 711)), "Targeting cannot cover the hotbar")
	assert_false(targets._has_point(Vector2(965, 306)))
	targets._gui_input(_click(Vector2(965, 306)))
	targets._gui_input(_click(local_point))
	assert_eq(selected, ["local"])
	var activate := InputEventAction.new()
	activate.action = &"ui_accept"
	activate.pressed = true
	targets._gui_input(activate)
	assert_eq(selected, ["local", "local"])
	targets.queue_free()
	await Engine.get_main_loop().process_frame


func test_real_click_selects_an_opponent_seat_only_while_targeting() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 200)
	Engine.get_main_loop().root.add_child(viewport)
	var seat := SEAT.instantiate() as PlayerSeat
	viewport.add_child(seat)
	seat.position = Vector2(20, 20)
	seat.size = Vector2(300, 60)
	seat.render({"player_id": "north", "name": "North"}, 2, false, false, 0)
	await Engine.get_main_loop().process_frame

	var selected: Array[String] = []
	seat.ability_target_requested.connect(func(player_id: String): selected.append(player_id))
	var point: Vector2 = seat.ability_target_rect().get_center()
	seat.set_ability_target(true)
	_send_click(viewport, point)
	assert_true(selected.is_empty())
	seat.set_ability_target(true, false, true)
	_send_click(viewport, point)
	assert_eq(selected, ["north"])
	seat.render({}, 2, false, false, 0)
	_send_click(viewport, point)
	assert_eq(selected, ["north"])
	viewport.queue_free()
	await Engine.get_main_loop().process_frame


func _send_click(viewport: Viewport, point: Vector2) -> void:
	var event := _click(point)
	viewport.push_input(event, true)
	event = _click(point)
	event.pressed = false
	viewport.push_input(event, true)


func _click(at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.pressed = true
	return event
