extends "res://tests/test_case.gd"

const MATCH_SCENE := preload("res://src/view/match/match_screen.tscn")


func test_local_deal_flies_once_and_reveals_slots_when_it_finishes() -> void:
	var table := MATCH_SCENE.instantiate() as MatchScreen
	Engine.get_main_loop().root.add_child(table)
	var model := _draw_model()
	var cues: Array[StringName] = []
	table.get_node("DrawAnimation").sound_requested.connect(func(cue: StringName): cues.append(cue))
	table.render(model)
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	var animation := table.get_node_or_null("DrawAnimation")
	assert_true(animation != null)
	if animation != null:
		assert_eq(animation.get_child_count(), 2)
		var hand := table.get_node("PhaseControls") as PhaseControls
		assert_eq(hand.card_widget(&"dealt").modulate.a, 0.0)
		table.render(model)
		await Engine.get_main_loop().process_frame
		assert_eq(animation.get_child_count(), 2)
		await Engine.get_main_loop().create_timer(1.8).timeout
		assert_eq(hand.card_widget(&"dealt").modulate.a, 1.0)
		assert_eq(animation.get_child_count(), 0)
		assert_eq(cues, [&"draw", &"draw", &"deal", &"deal"])
	table.queue_free()
	await Engine.get_main_loop().process_frame


func test_skip_draws_reveals_new_cards_and_finishes_active_flights() -> void:
	var table := MATCH_SCENE.instantiate() as MatchScreen
	Engine.get_main_loop().root.add_child(table)
	if not table.has_method("set_draw_speed"):
		assert_true(false, "The match must allow skipping draw animations")
		table.queue_free()
		await Engine.get_main_loop().process_frame
		return
	var model := _draw_model()
	table.render(model)
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	var draw := table.get_node("DrawAnimation")
	var hand := table.get_node("PhaseControls") as PhaseControls
	assert_eq(draw.get_child_count(), 2)
	assert_eq(hand.card_widget(&"dealt").modulate.a, 0.0)

	table.call("set_draw_speed", 0)
	assert_eq(hand.card_widget(&"dealt").modulate.a, 1.0)
	model.private_hand.append({"card_id": "instant", "first": _half(1, 2), "second": _half(2, 5)})
	table.render(model)
	await Engine.get_main_loop().process_frame
	assert_eq(draw.get_child_count(), 0)
	assert_eq(hand.card_widget(&"instant").modulate.a, 1.0)
	table.queue_free()
	await Engine.get_main_loop().process_frame


func test_old_snapshots_and_spectators_do_not_replay_the_opening_deal() -> void:
	var table := MATCH_SCENE.instantiate() as MatchScreen
	Engine.get_main_loop().root.add_child(table)
	var model := _draw_model()
	model.server_now_msec = 20_000
	table.render(model)
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	var animation := table.get_node_or_null("DrawAnimation")
	assert_true(animation != null)
	if animation != null:
		assert_eq(animation.get_child_count(), 0)
		model.erase("private_player_id")
		table.render(model)
		await Engine.get_main_loop().process_frame
		assert_eq(animation.get_child_count(), 0)
	table.queue_free()
	await Engine.get_main_loop().process_frame


func test_new_inventory_animates_during_a_match_and_reconnect_unhides_it() -> void:
	var table := MATCH_SCENE.instantiate() as MatchScreen
	Engine.get_main_loop().root.add_child(table)
	var model := _draw_model()
	model.server_now_msec = 20_000
	table.render(model)
	var animation := table.get_node("DrawAnimation")
	var hand := table.get_node("PhaseControls") as PhaseControls
	model.round_number = 2
	model.private_hand.append({"card_id": "new-draw", "first": _half(0, 3), "second": _half(2, 5)})
	model.private_abilities.append({"copy_id": "new-ability", "ability_id": "reverse_cycle"})
	table.render(model)
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	assert_eq(animation.get_child_count(), 2)
	assert_eq(hand.card_widget(&"dealt").modulate.a, 1.0)
	assert_eq(hand.card_widget(&"new-draw").modulate.a, 0.0)
	model["frozen"] = true
	table.render(model)
	await Engine.get_main_loop().process_frame
	assert_eq(animation.get_child_count(), 0)
	assert_true(hand.card_widget(&"new-draw").modulate.a > 0.0)
	model.frozen = false
	table.render(model)
	await Engine.get_main_loop().process_frame
	assert_eq(animation.get_child_count(), 0)
	table.queue_free()
	await Engine.get_main_loop().process_frame


func _draw_model() -> Dictionary:
	return {
		"round_number": 1, "phase": 2, "phase_started_msec": 300, "server_now_msec": 350,
		"private_player_id": "p1", "active_context": 0,
		"private_hand": [{"card_id": "dealt", "first": _half(0, 2), "second": _half(1, 4)}],
		"private_abilities": [{"copy_id": "a1", "ability_id": "reverse_cycle"}],
		"pile_counts": {"0": {"draw_count": 60}, "1": {"draw_count": 57}},
		"ability_pile_count": {"draw_count": 85, "capacity": 90},
	}


func _half(context: int, rank: int) -> Dictionary:
	return {"kind": 0, "base_context": context, "effective_context": context, "effective_rank": rank, "effective_suit": 0}
