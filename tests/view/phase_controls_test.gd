extends "res://tests/test_case.gd"

const PHASE_CONTROLS_PATH := "res://src/view/match/phase_controls.tscn"
const MATCH_SCREEN_PATH := "res://src/view/match/match_screen.tscn"


func test_start_request_enforces_caps_exact_total_and_duplicate_ready_lock() -> void:
	var controls = await _mount_controls()
	if controls == null:
		return
	var intents: Array[Dictionary] = []
	controls.intent_requested.connect(func(kind: StringName, payload: Dictionary):
		intents.append({"kind": kind, "payload": payload})
	)
	controls.render(_model(1, [], {"required_half_count": 6}))
	var rise: SpinBox = controls.get_node("StartControls/RequestGrid/Rise")
	var flourish: SpinBox = controls.get_node("StartControls/RequestGrid/Flourish")
	var fall: SpinBox = controls.get_node("StartControls/RequestGrid/Fall")
	assert_eq(rise.max_value, 5.0)
	assert_eq(rise.suffix, " Rise")
	assert_eq(flourish.suffix, " Flourish")
	assert_eq(fall.suffix, " Fall")
	rise.value = 2
	flourish.value = 1
	assert_eq(controls.get_node("StartControls/Total").text, "3 / 6 selected")
	assert_false(controls.get_node("StartControls/ConfirmButton").disabled)
	controls.get_node("StartControls/ConfirmButton").pressed.emit()
	assert_eq(intents, [{"kind": &"set_replenishment_request", "payload": {"request": {0: 2, 1: 1, 2: 0}}}])
	controls.handle_command_result(&"set_replenishment_request", true, &"", 1)
	assert_true(controls.get_node("StartControls/ReadyButton").disabled)
	rise.value = 5
	flourish.value = 1
	fall.value = 1
	assert_eq(controls.get_node("StartControls/Total").text, "7 / 6 selected")
	assert_true(controls.get_node("StartControls/ConfirmButton").disabled)
	fall.value = 0
	assert_false(controls.get_node("StartControls/ConfirmButton").disabled)
	controls.get_node("StartControls/ConfirmButton").pressed.emit()
	controls.get_node("StartControls/ConfirmButton").pressed.emit()
	assert_eq(intents[1], {"kind": &"set_replenishment_request", "payload": {"request": {0: 5, 1: 1, 2: 0}}})
	controls.handle_command_result(&"set_replenishment_request", true, &"", 1)
	controls.get_node("StartControls/ReadyButton").pressed.emit()
	controls.get_node("StartControls/ReadyButton").pressed.emit()
	assert_eq(intents.size(), 3)
	assert_eq(intents[2], {"kind": &"set_ready", "payload": {"ready": true}})
	await _unmount(controls)


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
	assert_false(controls.get_node("HandPlayControls/ActionRow/LockButton").disabled)
	assert_eq(controls.staged_selection(&"c2").half_index, 0)
	controls.choose_half(&"c2", 1)
	assert_eq(controls.staged_selection(&"c2").half_index, 1)
	controls.click_card(&"c4")
	var joker_choices: Array = controls.staged_selection(&"c4").joker_choices
	assert_eq(joker_choices, [{"half_index": 0, "context": 0, "suit": 0}])
	assert_true(controls.card_widget(&"c4").joker_prompts_visible())
	var joker_context: OptionButton = controls.card_widget(&"c4").get_node("Face/FirstChoices/Context")
	assert_eq([
		joker_context.get_item_text(0),
		joker_context.get_item_text(1),
		joker_context.get_item_text(2),
	], ["Rise", "Flourish", "Fall"])
	assert_true(controls.get_node("HandPlayControls/Preview/Heading").text.contains("PREVIEW"))
	assert_true(controls.get_node("HandPlayControls/Preview/Authority").text.contains("host validates"))
	controls.set_joker_choice(&"c4", 0, 2, 1)
	assert_eq(controls.staged_selection(&"c4").joker_choices[0], {"half_index": 0, "context": 2, "suit": 1})
	controls.click_card(&"c4")
	assert_false(controls.has_staged_card(&"c4"))
	controls.click_card(&"c4")
	assert_eq(controls.staged_selection(&"c4").joker_choices[0], {"half_index": 0, "context": 0, "suit": 0})
	controls.render(_model(4, _hand(), {}))
	controls.render(_model(3, _hand(), {}))
	assert_false(controls.has_staged_card(&"c4"))
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
	controls.get_node("HandPlayControls/ActionRow/LockButton").pressed.emit()
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
	controls.get_node("HandPlayControls/ActionRow/PassButton").pressed.emit()
	controls.get_node("HandPlayControls/ActionRow/PassButton").pressed.emit()
	assert_eq(intents, [{"kind": &"stage_hand", "payload": {"cards": []}}])
	controls.render(_model(4, _hand(), {}))
	assert_false(controls.get_node("HandPlayControls").visible)
	controls.handle_command_result(&"stage_hand", true, &"", 4)
	assert_eq(intents.size(), 1)

	controls.render(_model(3, _hand(), {}))
	controls.get_node("HandPlayControls/ActionRow/PassButton").pressed.emit()
	controls.handle_command_result(&"stage_hand", false, &"invalid_normal_hand", 3)
	assert_false(controls.get_node("HandPlayControls/ActionRow/PassButton").disabled)
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
		"timeout_notice": "Timer expired: 2 ability cards were discarded at random.",
	}))
	assert_eq(controls.get_node("EndControls/Required").text, "Choose 2 to discard")
	assert_eq(controls.get_node("EndControls/AbilityChoices").get_child_count(), 5)
	controls.toggle_ability_discard(&"a2", true)
	assert_true(controls.get_node("EndControls/ConfirmButton").disabled)
	controls.toggle_ability_discard(&"a4", true)
	assert_false(controls.get_node("EndControls/ConfirmButton").disabled)
	controls.get_node("EndControls/ConfirmButton").pressed.emit()
	controls.get_node("EndControls/ConfirmButton").pressed.emit()
	assert_eq(intents, [{"kind": &"choose_ability_discards", "payload": {"copy_ids": ["a2", "a4"]}}])
	assert_eq(controls.get_node("TimeoutNotice").text, "Timer expired: 2 ability cards were discarded at random.")
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
	phase_controls.get_node("HandPlayControls/ActionRow/PassButton").pressed.emit()
	assert_eq(intents, [{"kind": &"stage_hand", "payload": {"cards": []}}])
	await _unmount(match_screen)


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
