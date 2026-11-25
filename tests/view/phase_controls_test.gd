extends "res://tests/test_case.gd"

const PHASE_CONTROLS_PATH := "res://src/view/match/phase_controls.tscn"
const MATCH_SCREEN_PATH := "res://src/view/match/match_screen.tscn"


func test_hand_action_changes_from_pass_to_submit_with_staging() -> void:
	var controls = await _mount_controls()
	var intents: Array[Dictionary] = []
	controls.intent_requested.connect(func(kind: StringName, payload: Dictionary):
		intents.append({"kind": kind, "payload": payload})
	)
	controls.render(_model(3, _hand(), {}))
	var actions: Control = controls.get_node("HandPlayControls/ActionRow")
	var buttons := actions.find_children("*", "Button", false, false)
	assert_eq(buttons.size(), 1)
	if buttons.size() != 1:
		await _unmount(controls)
		return
	var action: Button = buttons[0]
	assert_eq(action.text, "PASS")
	controls.click_card(&"c1")
	assert_eq(action.text, "SUBMIT HAND")
	controls.click_card(&"c1")
	assert_eq(action.text, "PASS")
	action.pressed.emit()
	controls.handle_command_result(&"stage_hand", true, &"", 3)
	controls.handle_command_result(&"lock_hand", true, &"", 3)
	action.pressed.emit()
	assert_true(action.disabled)
	assert_eq(intents, [{"kind": &"stage_hand", "payload": {"cards": []}}, {"kind": &"lock_hand", "payload": {}}])
	await _unmount(controls)


func test_ready_shortcut_respects_phase_focus_pending_and_host_readiness() -> void:
	var controls = await _mount_controls()
	var intents: Array[StringName] = []
	controls.intent_requested.connect(func(kind: StringName, _payload: Dictionary): intents.append(kind))
	if not controls.has_method("trigger_ready_shortcut"):
		assert_true(false, "The table needs a way to invoke the active Ready action")
		await _unmount(controls)
		return
	controls.render(_model(1, [], {"required_half_count": 2}))
	assert_false(controls.trigger_ready_shortcut())
	controls.render(_model(3, _hand(), {}))
	assert_false(controls.trigger_ready_shortcut())
	var main := _model(2, _hand(), {"private_player_id": "p1", "players": [{"player_id": "p1", "ready": false}]})
	controls.render(main)
	controls.set_inputs_locked(true)
	assert_false(controls.trigger_ready_shortcut())
	controls.set_inputs_locked(false)
	controls.set_ability_focus_held(true)
	controls.render(main)
	assert_false(controls.trigger_ready_shortcut())
	controls.set_ability_focus_held(false)
	assert_true(controls.trigger_ready_shortcut())
	assert_false(controls.trigger_ready_shortcut())
	controls.handle_command_result(&"set_ready", true, &"", 2)
	assert_false(controls.trigger_ready_shortcut())
	var ready_button: Button = controls.get_node("MainControls/ReadyButton")
	assert_true(ready_button.disabled)
	assert_eq(ready_button.text, "READY ✓")
	main.players[0].ready = true
	controls.render(main)
	ready_button.pressed.emit()
	assert_eq(intents, [&"set_ready"])
	main.players[0].ready = false
	controls.render(main)
	assert_true(controls.trigger_ready_shortcut())
	assert_eq(intents, [&"set_ready", &"set_ready"])
	await _unmount(controls)


func test_pending_hand_draw_keeps_its_slot_across_render_and_reorder() -> void:
	var controls = await _mount_controls()
	if controls == null:
		return
	if not controls.has_method("set_draw_pending"):
		assert_true(false, "Hand draws need a pending state")
		await _unmount(controls)
		return
	controls.set_draw_pending(&"c2", true)
	controls.set_draw_pending(&"c3", true)
	controls.render(_model(3, _hand(), {}))
	await Engine.get_main_loop().process_frame
	var widget: Control = controls.card_widget(&"c2")
	assert_true(widget.is_visible_in_tree() and widget.size.x > 0, "Pending draws occupy their normal slots")
	assert_eq(widget.modulate.a, 0.0)
	assert_eq(controls.card_widget(&"c1").modulate.a, 1.0)

	controls.reorder_hand(&"c2", 0)
	controls.render(_model(3, _hand(), {}))
	assert_eq(controls.local_hand_order()[0], &"c2")
	assert_eq(controls.card_widget(&"c2").modulate.a, 0.0)
	controls.set_draw_pending(&"c2", false)
	assert_eq(controls.card_widget(&"c2").modulate.a, 1.0)
	assert_eq(controls.card_widget(&"c3").modulate.a, 0.0)
	controls.clear_pending_draws()
	assert_eq(controls.card_widget(&"c3").modulate.a, 1.0)
	await _unmount(controls)


func test_start_request_autosaves_partial_counts_and_readies_only_the_latest_selection() -> void:
	var controls = await _mount_controls()
	if controls == null:
		return
	var intents: Array[Dictionary] = []
	controls.intent_requested.connect(func(kind: StringName, payload: Dictionary):
		intents.append({"kind": kind, "payload": payload})
	)
	controls.render(_model(1, [], {"required_half_count": 6}))
	var keypads: Array = controls.get_node("StartControls/RequestGrid").get_children()
	for keypad in keypads:
		assert_eq(keypad.find_children("Count*", "Button", true, false).size(), 5)
	if keypads[0].find_child("Count2", true, false) == null:
		await _unmount(controls)
		return
	var rise_two: Button = keypads[0].find_child("Count2", true, false)
	var rise_five: Button = keypads[0].find_child("Count5", true, false)
	var flourish_one: Button = keypads[1].find_child("Count1", true, false)
	var fall_one: Button = keypads[2].find_child("Count1", true, false)
	var ready_button: Button = controls.get_node("StartControls/ReadyButton")
	assert_false(controls.has_node("StartControls/ConfirmButton"))
	rise_two.pressed.emit()
	flourish_one.pressed.emit()
	assert_true(rise_two.button_pressed)
	assert_true(keypads[2].find_child("Count4", true, false).disabled)
	assert_eq(controls.get_node("StartControls/Total").text, "3 / 6 selected")
	assert_eq(intents, [{"kind": &"set_replenishment_request", "payload": {"request": {0: 2}}}])
	if intents.is_empty():
		await _unmount(controls)
		return
	assert_true(ready_button.disabled)
	controls.handle_command_result(&"set_replenishment_request", true, &"", 1)
	assert_eq(intents[-1].payload.request, {0: 2, 1: 1})
	rise_five.pressed.emit()
	assert_false(rise_two.button_pressed)
	assert_true(fall_one.disabled)
	fall_one.pressed.emit()
	assert_eq(controls.get_node("StartControls/Total").text, "6 / 6 selected")
	controls.handle_command_result(&"set_replenishment_request", true, &"", 1)
	assert_eq(intents[-1].payload.request, {0: 5, 1: 1})
	flourish_one.pressed.emit()
	assert_false(flourish_one.button_pressed)
	assert_false(fall_one.disabled)
	assert_true(ready_button.disabled)
	fall_one.pressed.emit()
	assert_false(ready_button.disabled)
	ready_button.pressed.emit()
	ready_button.pressed.emit()
	assert_eq(intents.size(), 3, "Ready waits for the save in flight")
	controls.handle_command_result(&"set_replenishment_request", true, &"", 1)
	assert_eq(intents.slice(3), [{"kind": &"set_replenishment_request", "payload": {"request": {0: 5, 2: 1}}}])
	controls.handle_command_result(&"set_replenishment_request", true, &"", 1)
	assert_eq(intents.slice(4), [{"kind": &"set_ready", "payload": {"ready": true}}])
	controls.handle_command_result(&"set_ready", true, &"", 1)
	assert_true(ready_button.disabled)
	assert_true(fall_one.disabled)
	await _unmount(controls)


func test_start_request_rejection_keeps_the_player_unready_and_allows_a_retry() -> void:
	var controls = await _mount_controls()
	var intents: Array[StringName] = []
	controls.intent_requested.connect(func(kind: StringName, _payload: Dictionary): intents.append(kind))
	controls.render(_model(1, [], {"required_half_count": 2}))
	var rise_two: Button = controls.find_child("Rise", true, false).find_child("Count2", true, false)
	var ready_button: Button = controls.get_node("StartControls/ReadyButton")
	rise_two.pressed.emit()
	ready_button.pressed.emit()
	controls.handle_command_result(&"set_replenishment_request", false, &"send_failed", 1)
	assert_eq(intents, [&"set_replenishment_request"])
	assert_false(ready_button.disabled)
	assert_false(rise_two.disabled)
	ready_button.pressed.emit()
	controls.handle_command_result(&"set_replenishment_request", true, &"", 1)
	assert_eq(intents, [&"set_replenishment_request", &"set_replenishment_request", &"set_ready"])
	await _unmount(controls)


func test_start_keypads_appear_directly_below_the_context_piles() -> void:
	var scene: PackedScene = load(MATCH_SCREEN_PATH)
	var match_view = scene.instantiate()
	Engine.get_main_loop().root.add_child(match_view)
	var model := _model(1, [], {"required_half_count": 12})
	model["private_player_id"] = "p1"
	match_view.render(model)
	await Engine.get_main_loop().process_frame
	for context in ["Rise", "Flourish", "Fall"]:
		var keypad: Control = match_view.get_node_or_null("PhaseControls/" + context)
		assert_true(keypad != null, "Expected a keypad on %s" % context)
		if keypad == null:
			continue
		var pile: Control = match_view.get_node("Center/Piles/Pile" + context)
		var keys := keypad.get_global_rect()
		var stack := pile.get_global_rect()
		assert_true(keypad.is_visible_in_tree() and keys.position.y >= stack.end.y)
		assert_true(absf(keys.get_center().x - stack.get_center().x) < 2.0)
		assert_true(keypad.find_child("Count1", true, false).disabled)
		assert_false(keypad.find_child("Count2", true, false).disabled)
		var key: Button = keypad.find_child("Count2", true, false)
		var point := key.get_global_transform_with_canvas() * (key.size / 2.0)
		for pressed in [true, false]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = pressed
			click.position = point
			click.global_position = point
			key.get_viewport().push_input(click, true)
		assert_true(key.button_pressed, "Mouse input should reach the %s draw keypad" % context)
	match_view.render(model.merged({"phase": 2}, true))
	assert_true(match_view.find_children("Count1", "Button", true, false).all(
		func(button: Button): return not button.is_visible_in_tree()
	))
	await _unmount(match_view)


func test_draw_timeout_notice_uses_only_the_local_players_unselected_count() -> void:
	var table = await _mount_path(MATCH_SCREEN_PATH)
	var start := _model(1, [], {"private_player_id": "p1", "round_number": 2})
	table.render(start)
	table.present_ability_events([{
		"kind": "hand_replenished",
		"payload": {"player_id": "p2", "round_number": 2, "automatic_halves": 12},
	}, {
		"kind": "hand_replenished",
		"payload": {"player_id": "p1", "round_number": 2, "automatic_halves": 3},
	}])
	table.render(start.merged({"phase": 2}, true))
	var notice: Label = table.get_node("PhaseControls/TimeoutNotice")
	assert_true(notice.visible)
	assert_true(notice.text.contains("3 unselected half-cards"))
	table.render(start.merged({"phase": 3}, true))
	assert_false(notice.visible)
	await _unmount(table)


func test_hand_builder_stages_eligible_cards_requires_half_choice_and_defaults_joker() -> void:
	var controls = await _mount_controls()
	if controls == null:
		return
	controls.render(_model(3, _hand(), {
		"submission_preview": {
			"valid": true, "base_value": 7, "normal_category": "High Card",
			"normal_multiplier": "×1", "context_category": "Rise ×2",
			"context_multiplier": "×2", "projected_score": 14,
		},
	}))
	assert_false(controls.card_widget(&"c1").interaction_disabled)
	assert_true(controls.card_widget(&"c3").interaction_disabled)
	controls.click_card(&"c2")
	assert_false(controls.get_node("HandPlayControls/ActionRow/SubmitButton").disabled)
	assert_eq(controls.staged_selection(&"c2").half_index, 0)
	controls.choose_half(&"c2", 1)
	assert_eq(controls.staged_selection(&"c2").half_index, 1)
	controls.click_card(&"c4")
	var joker_choices: Array = controls.staged_selection(&"c4").joker_choices
	assert_eq(joker_choices, [{"half_index": 0, "context": 0, "suit": 0}])
	assert_true(controls.card_widget(&"c4").joker_prompts_visible())
	var joker_context: OptionButton = controls.card_widget(&"c4").get_node("Face/FirstChoices/Context")
	var joker_suit: OptionButton = controls.card_widget(&"c4").get_node("Face/FirstChoices/Suit")
	assert_eq([
		joker_context.get_item_text(0),
		joker_context.get_item_text(1),
		joker_context.get_item_text(2),
	], ["Rise", "Flourish", "Fall"])
	assert_eq([
		joker_suit.get_item_text(0),
		joker_suit.get_item_text(1),
		joker_suit.get_item_text(2),
	], ["Mountain", "Cloud", "Sea"])
	assert_true(controls.get_node("HandPlayControls/Preview/Heading").text.contains("PREVIEW"))
	assert_true(controls.get_node("HandPlayControls/Preview/Authority").text.contains("host validates"))
	controls.click_card(&"c4")
	assert_false(controls.has_staged_card(&"c4"))
	assert_true(controls.card_widget(&"c4").joker_prompts_visible())
	var intents: Array = []
	controls.intent_requested.connect(func(kind, payload): intents.append([kind, payload]))
	var hand := _hand()
	hand[3].first["joker_context"] = 2
	hand[3].first["joker_suit"] = 1
	hand[3].first["joker_rank"] = 5
	controls.render(_model(3, hand, {}))
	var joker_rank: OptionButton = controls.card_widget(&"c4").get_node("Face/FirstChoices/Rank")
	assert_eq(joker_rank.item_count, 11)
	joker_rank.item_selected.emit(7)
	assert_true(intents.is_empty(), "Changing a Joker never sends a standalone command")
	assert_true(controls.card_widget(&"c4").has_node("Face/FirstRankArt/Digit7"))
	var joker_suit_picker: OptionButton = controls.card_widget(&"c4").get_node("Face/FirstChoices/Suit")
	joker_suit_picker.item_selected.emit(2)
	controls.set_joker_choice(&"c4", 0, 2, 2, 11)
	controls.render(_model(3, hand, {}))
	assert_true(controls.card_widget(&"c4").has_node("Face/FirstRankArt/Digit7"))
	controls.click_card(&"c4")
	assert_eq(controls.staged_selection(&"c4").get("joker_choices", []), [{"half_index": 0, "context": 2, "suit": 2, "rank": 7}])
	controls.render(_model(4, hand, {}))
	controls.render(_model(3, hand, {}))
	assert_false(controls.has_staged_card(&"c4"))
	controls.click_card(&"c4")
	assert_eq(controls.staged_selection(&"c4").get("joker_choices", []), [{"half_index": 0, "context": 2, "suit": 2, "rank": 7}])
	controls.card_widget(&"c4").get_node("Face/FirstChoices/Rank").item_selected.emit(0)
	controls.get_node("HandPlayControls/ActionRow/SubmitButton").pressed.emit()
	assert_eq(intents, [[&"stage_hand", {"cards": [{
		"card_id": "c4", "half_index": 0,
		"joker_choices": [{"half_index": 0, "context": 2, "suit": 2, "rank": 0}],
	}]}]])
	await _unmount(controls)


func test_resonance_context_half_is_highlighted_and_selectable() -> void:
	var controls = await _mount_controls()
	if controls == null:
		return
	var hand := _hand()
	hand[0]["first"]["effective_context"] = 1
	hand[0]["second"]["effective_context"] = 2
	hand[0]["eligible_half_indexes"] = [0]
	var model := _model(3, hand, {})
	model["active_context"] = 0
	model["active_contexts"] = [0, 1]
	controls.render(model)
	var widget = controls.card_widget(&"c1")
	assert_eq(widget.active_half_index, 0)
	controls.click_card(&"c1")
	assert_true(controls.has_staged_card(&"c1"))
	assert_eq(controls.staged_selection(&"c1").half_index, 0)
	await _unmount(controls)


func test_score_preview_renders_additive_components_adjustments_and_factor_floor() -> void:
	var controls = await _mount_controls()
	if controls == null: return
	controls.render(_model(3, _hand(), {"submission_preview": {"score_breakdown": {
		"base_value": 10,
		"card_hand_components": [
			{"category_id": "straight", "value": {"numerator": 6, "denominator": 1}},
			{"category_id": "flush", "value": {"numerator": 4, "denominator": 1}},
		],
		"context_hand_components": [{"category_id": "three_context", "value": {"numerator": 5, "denominator": 1}}],
		"field_components": [],
		"applied_modifiers": [
			{"factor_id": "card_hand", "category_id": "straight", "delta": {"numerator": 3, "denominator": 1}},
			{"factor_id": "card_hand", "category_id": "flush", "delta": {"numerator": -2, "denominator": 1}},
		],
		"card_hand_unclamped": {"numerator": 11, "denominator": 1}, "card_hand_factor": {"numerator": 11, "denominator": 1},
		"context_hand_unclamped": {"numerator": 5, "denominator": 1}, "context_hand_factor": {"numerator": 5, "denominator": 1},
		"field_unclamped": {"numerator": 0, "denominator": 1}, "field_factor": {"numerator": 1, "denominator": 1},
		"final_score": 550,
	}}}))
	var details: String = controls.get_node("HandPlayControls/Preview/Details").text
	for expected in ["Straight 6", "Flush 4", "Straight +3", "Flush -2", "floor 1", "projected 550"]:
		assert_true(details.contains(expected), "missing additive detail: %s" % expected)
	await _unmount(controls)


func test_orientation_and_reorder_stay_local_while_lock_payload_is_canonical() -> void:
	var controls = await _mount_controls()
	if controls == null:
		return
	var intents: Array[Dictionary] = []
	controls.intent_requested.connect(func(kind: StringName, payload: Dictionary):
		intents.append({"kind": kind, "payload": payload})
	)
	controls.render(_model(3, _hand(), {}))
	controls.right_click_card(&"c1")
	controls.card_widget(&"c6").get_node("Face/OrderControls/MoveLeft").pressed.emit()
	assert_true(controls.card_widget(&"c1").orientation_flipped)
	assert_eq(controls.local_hand_order(), [&"c1", &"c2", &"c3", &"c4", &"c6", &"c5"])
	controls.click_card(&"c1")
	controls.click_card(&"c2")
	controls.card_widget(&"c2").get_node("Face/OrderControls/MoveLeft").pressed.emit()
	assert_eq(controls.staged_order(), [&"c2", &"c1"])
	controls.get_node("HandPlayControls/ActionRow/SubmitButton").pressed.emit()
	assert_eq(intents.size(), 1)
	assert_eq(intents[0].kind, &"stage_hand")
	assert_eq(intents[0].payload.cards, [
		{"card_id": "c2", "half_index": 0, "joker_choices": []},
		{"card_id": "c1", "half_index": 0, "joker_choices": []},
	])
	assert_false(str(intents[0].payload).contains("orientation"))
	controls.handle_command_result(&"stage_hand", true, &"", 3)
	assert_eq(intents.size(), 2)
	assert_eq(intents[1], {"kind": &"lock_hand", "payload": {}})
	await _unmount(controls)


func test_phase_change_cancels_stale_actions_and_pass_waits_for_stage_ack() -> void:
	var controls = await _mount_controls()
	if controls == null:
		return
	var intents: Array[Dictionary] = []
	controls.intent_requested.connect(func(kind: StringName, payload: Dictionary):
		intents.append({"kind": kind, "payload": payload})
	)
	controls.render(_model(3, _hand(), {}))
	controls.get_node("HandPlayControls/ActionRow/SubmitButton").pressed.emit()
	controls.get_node("HandPlayControls/ActionRow/SubmitButton").pressed.emit()
	assert_eq(intents, [{"kind": &"stage_hand", "payload": {"cards": []}}])
	controls.render(_model(4, _hand(), {}))
	assert_false(controls.get_node("HandPlayControls").visible)
	controls.handle_command_result(&"stage_hand", true, &"", 4)
	assert_eq(intents.size(), 1)

	controls.render(_model(3, _hand(), {}))
	controls.get_node("HandPlayControls/ActionRow/SubmitButton").pressed.emit()
	controls.handle_command_result(&"stage_hand", false, &"invalid_normal_hand", 3)
	assert_false(controls.get_node("HandPlayControls/ActionRow/SubmitButton").disabled)
	assert_true(controls.get_node("Status").text.contains("invalid"))
	await _unmount(controls)


func test_same_phase_snapshot_reconciles_only_when_authoritative_staging_changes() -> void:
	var controls = await _mount_controls()
	if controls == null:
		return
	controls.render(_model(3, _hand(), {}))
	controls.click_card(&"c1")
	controls.render(_model(3, _hand(), {}))
	assert_true(controls.has_staged_card(&"c1"))

	var staged_c2 := [{"card_id": "c2", "half_index": 0, "joker_choices": []}]
	controls.render(_model(3, _hand(), {
		"private_staging": {
			"staged_submission": staged_c2, "hand_locked": false,
			"pending_manipulation": {},
		},
	}))
	assert_false(controls.has_staged_card(&"c1"))
	assert_true(controls.has_staged_card(&"c2"))

	controls.render(_model(3, _hand(), {
		"private_staging": {
			"staged_submission": [], "hand_locked": false,
			"pending_manipulation": {},
		},
	}))
	assert_true(controls.staged_order().is_empty())
	await _unmount(controls)


func test_undo_submit_waits_for_the_restored_hand_and_preserves_staging() -> void:
	var controls = await _mount_controls()
	var intents: Array[StringName] = []
	controls.intent_requested.connect(func(kind: StringName, _payload: Dictionary):
		intents.append(kind)
	)
	var action: Button = controls.get_node("HandPlayControls/ActionRow/SubmitButton")
	var selected := [{"card_id": "c1", "half_index": 0, "joker_choices": []}]
	var model := _model(3, _hand(), {
		"private_staging": {"staged_submission": selected, "hand_locked": false},
	})
	controls.render(model)
	assert_true(controls.has_staged_card(&"c1"))
	controls.reorder_hand(&"c1", 2)
	var order: Array = controls.local_hand_order().duplicate()
	var locked := model.duplicate(true)
	locked.private_staging.hand_locked = true
	locked.private_hand.pop_front()
	controls.render(locked)
	assert_eq(action.text, "UNDO SUBMIT")
	assert_false(action.disabled)
	action.pressed.emit()
	assert_eq(intents, [&"unlock_hand"])
	controls.handle_command_result(&"unlock_hand", true, &"", 3)
	assert_true(action.disabled)
	controls.render(model)
	assert_true(controls.has_staged_card(&"c1"))
	assert_eq(controls.local_hand_order(), order)
	assert_eq(action.text, "SUBMIT HAND")
	assert_false(action.disabled)
	controls.click_card(&"c1")
	assert_false(controls.has_staged_card(&"c1"))
	await _unmount(controls)


func test_full_card_targeting_includes_hand_row_and_submission_shelf() -> void:
	var controls = await _mount_controls()
	if controls == null:
		return
	var targets: Array[StringName] = []
	controls.card_target_requested.connect(func(card_id: StringName): targets.append(card_id))
	controls.render(_model(3, _hand(), {}))
	controls.click_card(&"c1")
	controls.set_targeting(&"full_card", ["c1", "c2"])

	assert_true(controls.has_staged_card(&"c1"))
	assert_true(controls.card_widget(&"c1").targeting_eligible)
	assert_true(controls.card_widget(&"c2").targeting_eligible)
	controls.click_card(&"c1")
	controls.click_card(&"c2")
	assert_eq(targets, [&"c1", &"c2"])
	await _unmount(controls)


func test_half_targeting_selects_individual_halves_without_changing_staged_half_choice() -> void:
	var controls = await _mount_controls()
	if controls == null:
		return
	var targets: Array[Dictionary] = []
	controls.half_target_requested.connect(func(card_id: StringName, half_index: int):
		targets.append({"card_id": str(card_id), "half_index": half_index})
	)
	controls.render(_model(3, _hand(), {}))
	controls.click_card(&"c2")
	var staged_before: Dictionary = controls.staged_selection(&"c2")
	controls.set_targeting(&"half_card", [
		{"card_id": "c2", "half_index": 0},
		{"card_id": "c2", "half_index": 1},
	])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	controls.card_widget(&"c2")._handle_half_gui_input(click, 0)
	controls.card_widget(&"c2")._handle_half_gui_input(click, 1)

	assert_eq(targets, [
		{"card_id": "c2", "half_index": 0},
		{"card_id": "c2", "half_index": 1},
	])
	assert_eq(controls.staged_selection(&"c2"), staged_before)
	await _unmount(controls)


func test_targeting_marks_selected_halves_and_dims_non_targets() -> void:
	var controls = await _mount_controls()
	if controls == null:
		return
	controls.render(_model(3, _hand(), {}))
	controls.set_targeting(&"half_card", [
		{"card_id": "c1", "half_index": 0},
		{"card_id": "c1", "half_index": 1},
	], [{"card_id": "c1", "half_index": 1}])
	var target_widget = controls.card_widget(&"c1")
	var dimmed_widget = controls.card_widget(&"c2")
	assert_eq(target_widget.targeting_half_eligible, [true, true])
	assert_eq(target_widget.targeting_half_selected, [false, true])
	assert_false(target_widget.interaction_disabled)
	assert_true(dimmed_widget.interaction_disabled)
	assert_ne(target_widget.get_node("Face/Second").modulate, target_widget.get_node("Face/First").modulate)
	await _unmount(controls)


func test_end_discard_requires_exact_excess_and_timeout_notice_is_authoritative() -> void:
	var controls = await _mount_controls()
	if controls == null:
		return
	var intents: Array[Dictionary] = []
	controls.intent_requested.connect(func(kind: StringName, payload: Dictionary):
		intents.append({"kind": kind, "payload": payload})
	)
	controls.render(_model(5, _hand(), {
		"private_abilities": [
			{"copy_id": "a1", "ability_id": "field_a"},
			{"copy_id": "a2", "ability_id": "buff_pair"},
			{"copy_id": "a3", "ability_id": "sabotage"},
			{"copy_id": "a4", "ability_id": "manipulate"},
			{"copy_id": "a5", "ability_id": "field_b"},
		],
		"timeout_notice": "Timer expired: 3 ability cards were discarded at random.",
	}))
	assert_eq(controls.get_node("EndControls/Required").text, "Choose 3 to discard")
	assert_eq(controls.get_node("EndControls/AbilityChoices").get_child_count(), 5)
	controls.toggle_ability_discard(&"a2", true)
	assert_true(controls.get_node("EndControls/ConfirmButton").disabled)
	controls.toggle_ability_discard(&"a4", true)
	assert_true(controls.get_node("EndControls/ConfirmButton").disabled)
	controls.toggle_ability_discard(&"a5", true)
	assert_false(controls.get_node("EndControls/ConfirmButton").disabled)
	controls.get_node("EndControls/ConfirmButton").pressed.emit()
	controls.get_node("EndControls/ConfirmButton").pressed.emit()
	assert_eq(intents, [{"kind": &"choose_ability_discards", "payload": {"copy_ids": ["a2", "a4", "a5"]}}])
	assert_eq(controls.get_node("TimeoutNotice").text, "Timer expired: 3 ability cards were discarded at random.")
	await _unmount(controls)


func test_end_discard_uses_authoritative_required_count() -> void:
	var controls = await _mount_controls()
	if controls == null:
		return
	controls.render(_model(5, _hand(), {
		"private_abilities": [
			{"copy_id": "a1", "ability_id": "field_a"},
			{"copy_id": "a2", "ability_id": "buff_pair"},
			{"copy_id": "a3", "ability_id": "sabotage"},
			{"copy_id": "a4", "ability_id": "manipulate"},
			{"copy_id": "a5", "ability_id": "field_b"},
		],
		"required_ability_discards": 1,
	}))

	assert_eq(controls.get_node("EndControls/Required").text, "Choose 1 to discard")
	controls.toggle_ability_discard(&"a3", true)
	assert_false(controls.get_node("EndControls/ConfirmButton").disabled)
	await _unmount(controls)


func test_match_screen_hosts_phase_controls_and_bubbles_intents() -> void:
	var match_screen = await _mount_path(MATCH_SCREEN_PATH)
	if match_screen == null:
		return
	var intents: Array[Dictionary] = []
	match_screen.intent_requested.connect(func(kind: StringName, payload: Dictionary):
		intents.append({"kind": kind, "payload": payload})
	)
	var model := _model(3, _hand(), {})
	model["private_player_id"] = "p1"
	model["players"] = [{
		"player_id": "p1", "name": "Mira", "seat_index": 0,
		"spectator": false, "active": true, "connected": true,
		"ready": false, "hand_count": 6, "match_score": 0, "round_wins": 0,
	}]
	model["round_number"] = 1
	model["context_direction"] = 1
	model["phase_deadline_msec"] = 10000
	model["now_msec"] = 0
	model["active_fields"] = []
	match_screen.render(model)
	var phase_controls = match_screen.get_node("PhaseControls")
	assert_true(phase_controls.visible)
	assert_eq(phase_controls.get_node("HandPlayControls/Hand/Cards").get_child_count(), 6)
	phase_controls.get_node("HandPlayControls/ActionRow/SubmitButton").pressed.emit()
	assert_eq(intents, [{"kind": &"stage_hand", "payload": {"cards": []}}])
	await _unmount(match_screen)


func test_timed_staging_sends_each_new_draft_without_locking_edits() -> void:
	var controls = await _mount_controls()
	var intents: Array[Dictionary] = []
	controls.intent_requested.connect(func(kind, payload): intents.append({"kind": kind, "payload": payload}))
	var model := _model(3, _hand(), {"round_number": 4, "phase_deadline_msec": 10000})
	controls.render(model)
	assert_true(intents.is_empty())
	controls.click_card(&"c2")
	controls.choose_half(&"c2", 1)
	controls.render(model)
	controls.click_card(&"c2")
	assert_eq(intents, [
		{"kind": &"update_hand_draft", "payload": {"round_number": 4, "cards": [{"card_id": "c2", "half_index": 0, "joker_choices": []}]}},
		{"kind": &"update_hand_draft", "payload": {"round_number": 4, "cards": [{"card_id": "c2", "half_index": 1, "joker_choices": []}]}},
		{"kind": &"update_hand_draft", "payload": {"round_number": 4, "cards": []}},
	])
	controls.click_card(&"c2")
	model["round_number"] = 5
	controls.render(model)
	assert_false(controls.has_staged_card(&"c2"))
	assert_eq(intents[-1].payload.round_number, 4)
	await _unmount(controls)


func _model(phase: int, hand: Array, extra: Dictionary) -> Dictionary:
	var model := {
		"phase": phase,
		"active_context": 0,
		"private_hand": hand,
		"private_abilities": [],
		"private_staging": {
			"staged_submission": [], "hand_locked": false,
			"pending_manipulation": {},
		},
	}
	for key in extra:
		model[key] = extra[key]
	return model


func _hand() -> Array:
	return [
		_card("c1", _half(0, 7, 0), _half(1, 4, 2)),
		_card("c2", _half(0, 2, 1), _half(0, 8, 0)),
		_card("c3", _half(1, 5, 2), _half(2, 1, 0)),
		_card("c4", _joker(), _half(1, 9, 1)),
		_card("c5", _half(0, 6, 0), _half(2, 10, 1)),
		_card("c6", _half(0, 4, 2), _half(1, 7, 1)),
	]


func _card(id: String, first: Dictionary, second: Dictionary) -> Dictionary:
	return {"card_id": id, "first": first, "second": second}


func _half(context: int, rank: int, suit: int) -> Dictionary:
	return {"effective_context": context, "effective_rank": rank, "effective_suit": suit, "kind": 0}


func _joker() -> Dictionary:
	return {"effective_context": 0, "effective_rank": 0, "effective_suit": -1, "kind": 1}


func _mount_controls() -> Variant:
	return await _mount_path(PHASE_CONTROLS_PATH)


func _mount_path(path: String) -> Variant:
	if not ResourceLoader.exists(path):
		assert_true(false, "%s must exist" % path)
		return null
	var node = load(path).instantiate()
	Engine.get_main_loop().root.add_child(node)
	await Engine.get_main_loop().process_frame
	return node


func _unmount(node: Node) -> void:
	node.queue_free()
	await Engine.get_main_loop().process_frame
