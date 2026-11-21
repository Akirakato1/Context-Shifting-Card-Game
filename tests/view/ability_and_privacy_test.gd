extends "res://tests/test_case.gd"

const ABILITY_PANEL_PATH := "res://src/view/match/ability_panel.tscn"
const TARGETING_OVERLAY_PATH := "res://src/view/match/targeting_overlay.tscn"
const MATCH_SCREEN_PATH := "res://src/view/match/match_screen.tscn"


func test_ability_drawer_expands_upward_and_enforces_all_four_timings() -> void:
	var panel = await _mount(ABILITY_PANEL_PATH)
	if panel == null:
		return
	var activations: Array[StringName] = []
	panel.ability_activated.connect(func(copy_id: StringName, _ability: Dictionary): activations.append(copy_id))
	panel.render(_abilities(), 2, _catalog(), false)
	assert_false(panel.get_node("Drawer").visible)
	panel.get_node("ToggleButton").pressed.emit()
	assert_true(panel.get_node("Drawer").visible)
	assert_eq(panel.legal_ability_ids(), [&"field-copy", &"buff-copy", &"sabotage-copy"])
	panel.activate_ability(&"field-copy")
	panel.activate_ability(&"buff-copy")
	assert_eq(activations, [&"field-copy", &"buff-copy"])

	panel.render(_abilities(), 4, _catalog(), false)
	assert_eq(panel.legal_ability_ids(), [&"buff-copy"])
	panel.render(_abilities(), 3, _catalog(), false)
	assert_eq(panel.legal_ability_ids(), [&"manip-copy"])
	panel.render(_abilities(), 1, _catalog(), false)
	assert_true(panel.legal_ability_ids().is_empty())
	await _unmount(panel)


func test_targeting_overlay_collects_multistep_choices_dims_and_cancels_safely() -> void:
	var overlay = await _mount(TARGETING_OVERLAY_PATH)
	if overlay == null:
		return
	var commits: Array[Dictionary] = []
	var closes: Array[StringName] = []
	overlay.commit_requested.connect(func(choices: Dictionary): commits.append(choices))
	overlay.closed.connect(func(reason: StringName): closes.append(reason))
	overlay.begin({"steps": [
		{"key": "cards", "kind": "card", "count": 2, "eligible": ["c1", "c2", "c3"], "prompt": "Choose two cards"},
		{"key": "mode", "kind": "enum", "count": 1, "eligible": ["raise", "lower"], "prompt": "Choose a mode"},
	]})
	assert_true(overlay.visible)
	assert_true(overlay.get_node("Dimmer").visible)
	assert_true(overlay.get_node("Panel/Layout/Prompt").text.contains("two cards"))
	assert_true(overlay.get_node("Panel/Layout/CommitButton").disabled)
	overlay.select_value("not-eligible")
	assert_true(overlay.selected_values().is_empty())
	overlay.select_value("c1")
	overlay.select_value("c2")
	assert_eq(overlay.current_step_index(), 1)
	assert_eq(overlay.get_node("Panel/Layout/Prompt").text, "Choose a mode")
	overlay.select_value("raise")
	assert_eq(commits, [{"cards": ["c1", "c2"], "mode": ["raise"]}])
	assert_false(overlay.visible)

	overlay.begin({"steps": [{"key": "card", "kind": "card", "count": 1, "eligible": ["c1"]}]})
	overlay.get_node("Panel/Layout/CancelButton").pressed.emit()
	assert_eq(closes[-1], &"cancelled")
	assert_true(commits.size() == 1)
	await _unmount(overlay)


func test_fixed_targeting_auto_commits_after_final_required_choice() -> void:
	var overlay = await _mount(TARGETING_OVERLAY_PATH)
	if overlay == null:
		return
	var commits: Array[Dictionary] = []
	overlay.commit_requested.connect(func(choices: Dictionary): commits.append(choices))
	var hand := _private_cards(2)
	overlay.begin({"steps": [{
		"key": "cards", "kind": "full_card", "count": 1,
		"prompt": "Select 1 full card",
	}]}, hand)
	overlay.select_value("c1")
	assert_eq(commits, [{"cards": ["c1"]}])
	assert_false(overlay.visible)

	overlay.begin({"steps": [
		{"key": "cards", "kind": "full_card", "count": 1},
		{"key": "suit", "kind": "suit", "count": 1, "eligible": [0, 1, 2]},
	]}, hand)
	overlay.select_value("c2")
	assert_true(overlay.visible)
	assert_eq(overlay.current_step_index(), 1)
	overlay.select_value(2)
	assert_eq(commits[-1], {"cards": ["c2"], "suit": [2]})
	assert_false(overlay.visible)
	await _unmount(overlay)


func test_variable_targeting_toggles_one_to_max_and_requires_activate() -> void:
	var overlay = await _mount(TARGETING_OVERLAY_PATH)
	if overlay == null:
		return
	var commits: Array[Dictionary] = []
	overlay.commit_requested.connect(func(choices: Dictionary): commits.append(choices))
	var hand := _private_cards(7)
	overlay.begin({"steps": [{
		"key": "cards", "kind": "full_card", "min_count": 1, "max_count": 6,
	}]}, hand)
	overlay.select_value("c1")
	assert_true(overlay.visible, "minimum count must not auto-commit a variable workflow")
	assert_false(overlay.get_node("Panel/Layout/CommitButton").disabled)
	overlay.select_value("c1")
	assert_true(overlay.get_node("Panel/Layout/CommitButton").disabled)
	for index in range(1, 7):
		overlay.select_value("c%d" % index)
	overlay.select_value("c7")
	assert_eq(overlay.selected_values().size(), 6)
	overlay.get_node("Panel/Layout/CommitButton").pressed.emit()
	assert_eq(commits[-1].cards.size(), 6)

	overlay.begin({"steps": [{
		"key": "halves", "kind": "half_card", "min_count": 1, "max_count": 12,
	}]}, hand)
	for card_index in range(1, 8):
		for half_index in range(2):
			overlay.select_value({"card_id": "c%d" % card_index, "half_index": half_index})
	assert_eq(overlay.selected_values().size(), 12)
	await _unmount(overlay)


func test_targeting_cancel_before_activation_does_not_commit() -> void:
	var overlay = await _mount(TARGETING_OVERLAY_PATH)
	if overlay == null:
		return
	var commits: Array[Dictionary] = []
	overlay.commit_requested.connect(func(choices: Dictionary): commits.append(choices))
	overlay.begin({"steps": [{
		"key": "cards", "kind": "full_card", "min_count": 1, "max_count": 6,
	}]}, _private_cards(2))
	overlay.select_value("c1")
	overlay.get_node("Panel/Layout/CancelButton").pressed.emit()
	assert_true(commits.is_empty())
	assert_false(overlay.visible)
	await _unmount(overlay)


func test_ability_drawer_displays_name_and_rules_text() -> void:
	var panel = await _mount(ABILITY_PANEL_PATH)
	if panel == null:
		return
	panel.render(
		[{"copy_id": "mirror-copy", "ability_id": "mirror_rank"}], 3,
		{"mirror_rank": {
			"label": "Mirror Rank", "rules_text": "Mirror both ranks from 1 through 10.",
			"timing": 0, "choice_schema": {},
		}}, false
	)
	var button: Button = panel.get_node("Drawer/Layout/Cards").get_child(0)
	assert_true(button.text.contains("Mirror Rank"))
	assert_true(button.text.contains("Mirror both ranks"))
	await _unmount(panel)


func test_rejected_manipulation_commit_restores_targeting_for_retry_or_cancel() -> void:
	var match_screen = await _mount(MATCH_SCREEN_PATH)
	if match_screen == null:
		return
	var intents: Array[Dictionary] = []
	match_screen.intent_requested.connect(func(kind: StringName, payload: Dictionary):
		intents.append({"kind": kind, "payload": payload})
	)
	var model := _active_model(3)
	model.private_abilities = [{"copy_id": "mirror-copy", "ability_id": "mirror_rank"}]
	model.ability_catalog = {
		"mirror_rank": {
			"label": "Mirror Rank", "rules_text": "Mirror both ranks.", "timing": 0,
			"choice_schema": {"steps": [{
				"key": "cards", "kind": "full_card", "count": 1,
			}]},
		},
	}
	match_screen.render(model)
	match_screen.get_node("AbilityPanel").activate_ability(&"mirror-copy")
	match_screen.get_node("TargetingOverlay").select_value("c1")
	assert_eq(intents[-1], {
		"kind": &"commit_manipulation", "payload": {"choices": {"cards": ["c1"]}},
	})
	match_screen.handle_command_result(
		&"commit_manipulation", false, &"card_not_in_hand", 3
	)
	var overlay = match_screen.get_node("TargetingOverlay")
	assert_true(overlay.visible)
	assert_eq(overlay.selected_values(), ["c1"])
	overlay.get_node("Panel/Layout/CancelButton").pressed.emit()
	assert_eq(intents[-1], {"kind": &"cancel_manipulation", "payload": {}})
	await _unmount(match_screen)


func test_match_ability_targeting_marks_eligible_cards_and_commits_manipulation() -> void:
	var match_screen = await _mount(MATCH_SCREEN_PATH)
	if match_screen == null:
		return
	var intents: Array[Dictionary] = []
	match_screen.intent_requested.connect(func(kind: StringName, payload: Dictionary):
		intents.append({"kind": kind, "payload": payload})
	)
	var model := _active_model(3)
	model["private_abilities"] = [{"copy_id": "manip-copy", "ability_id": "suit_imprint"}]
	model["ability_catalog"] = _catalog()
	match_screen.render(model)
	var panel = match_screen.get_node("AbilityPanel")
	panel.activate_ability(&"manip-copy")
	assert_eq(intents[0], {"kind": &"stage_manipulation", "payload": {"copy_id": "manip-copy"}})
	assert_true(match_screen.get_node("TargetingOverlay").visible)
	assert_true(match_screen.get_node("PhaseControls").card_widget(&"c1").targeting_eligible)
	match_screen.get_node("TargetingOverlay").select_value("c1")
	match_screen.get_node("TargetingOverlay").select_value(1)
	assert_eq(intents[-1].kind, &"commit_manipulation")
	assert_eq(intents[-1].payload, {
		"choices": {"cards": ["c1"], "suit": [1]},
	})
	assert_false(match_screen.get_node("TargetingOverlay").visible)
	panel.activate_ability(&"manip-copy")
	match_screen.get_node("TargetingOverlay/Panel/Layout/CancelButton").pressed.emit()
	assert_eq(intents[-1], {"kind": &"cancel_manipulation", "payload": {}})
	panel.activate_ability(&"manip-copy")
	var intent_count := intents.size()
	model["phase"] = 4
	match_screen.render(model)
	assert_false(match_screen.get_node("TargetingOverlay").visible)
	assert_eq(intents.size(), intent_count)
	await _unmount(match_screen)


func test_spectator_tree_contains_no_private_values_and_private_piles_stay_hidden() -> void:
	var match_screen = await _mount(MATCH_SCREEN_PATH)
	if match_screen == null:
		return
	var model := _active_model(2)
	model.erase("private_player_id")
	model.erase("private_hand")
	model.erase("private_abilities")
	model.erase("pile_counts")
	model["players"][0]["hand_count"] = 6
	model["recent_public_abilities"] = [{
		"ability_id": "sabotage", "source_player_id": "p2", "target_player_id": "p1",
	}]
	match_screen.render(model)
	var rendered_tree := _control_tree_text(match_screen)
	for secret in ["private-card-copy-991", "private-ability-copy-882", "base_identity_773", "removed_card_c5"]:
		assert_false(rendered_tree.contains(secret))
	assert_eq(match_screen.get_node("Center/Piles/PileRise/Count").text, "Hidden")
	assert_false(match_screen.get_node("AbilityPanel").visible)
	assert_true(rendered_tree.contains("Sabotage"))
	assert_true(rendered_tree.contains("p2 → p1"))
	await _unmount(match_screen)


func test_reconnect_freezes_inputs_and_failure_reasons_offer_distinct_actions() -> void:
	var match_screen = await _mount(MATCH_SCREEN_PATH)
	if match_screen == null:
		return
	var model := _active_model(2)
	model["frozen"] = true
	model["connection_state"] = {"status": "reconnecting", "deadline_msec": 15000, "now_msec": 10000}
	match_screen.render(model)
	assert_true(match_screen.get_node("ConnectionOverlay").visible)
	assert_true(match_screen.get_node("ConnectionOverlay/Panel/Layout/Message").text.contains("paused"))
	assert_true(match_screen.get_node("ConnectionOverlay/Panel/Layout/Message").text.contains("5.0s"))
	assert_true(match_screen.get_node("PhaseControls").inputs_locked())
	assert_true(match_screen.get_node("AbilityPanel").inputs_locked())

	model["frozen"] = false
	model["connection_state"] = {"status": "connected"}
	match_screen.render(model)
	assert_false(match_screen.get_node("ConnectionOverlay").visible)
	assert_false(match_screen.get_node("PhaseControls").inputs_locked())

	var expectations := {
		&"forfeit": ["forfeited", "RETURN TO LOBBY"],
		&"host_lost": ["host connection", "TRY RECONNECT"],
		&"direct_connection_failed": ["direct and relay", "TRY AGAIN"],
		&"relay_unavailable": ["relay fallback", "TRY AGAIN"],
		&"room_closed": ["closed", "RETURN TO MENU"],
	}
	for reason in expectations:
		match_screen.show_connection_failure(reason)
		var message: String = match_screen.get_node("ConnectionOverlay/Panel/Layout/Message").text.to_lower()
		var action: String = match_screen.get_node("ConnectionOverlay/Panel/Layout/ActionButton").text
		assert_true(message.contains(expectations[reason][0]))
		assert_eq(action, expectations[reason][1])
	await _unmount(match_screen)


func test_public_ability_reaction_window_is_visible_without_revealing_private_effect_data() -> void:
	var match_screen = await _mount(MATCH_SCREEN_PATH)
	if match_screen == null:
		return
	var model := _active_model(2)
	model["reaction_deadline_msec"] = 5000
	model["now_msec"] = 3000
	model["recent_public_abilities"] = [{
		"ability_id": "pair_breaker", "source_player_id": "p2", "target_player_id": "p1",
	}]
	match_screen.render(model)
	assert_eq(match_screen.get_node("PhaseControls/MainControls/ReactionNotice").text, "Response window  2.0s")
	var history: String = _control_tree_text(match_screen.get_node("AbilityHistory"))
	assert_true(history.contains("Pair Breaker"))
	assert_false(history.contains("removed_card"))
	await _unmount(match_screen)


func test_public_ability_preserves_every_completed_choice_in_command_payload() -> void:
	var match_screen = await _mount(MATCH_SCREEN_PATH)
	if match_screen == null:
		return
	var intents: Array[Dictionary] = []
	match_screen.intent_requested.connect(func(kind: StringName, payload: Dictionary):
		intents.append({"kind": kind, "payload": payload})
	)
	var model := _active_model(2)
	model["ability_catalog"]["pair_breaker"]["choice_schema"] = {"steps": [
		{"key": "target_player_id", "kind": "player", "count": 1, "eligible": ["p2"]},
		{"key": "severity", "kind": "enum", "count": 1, "eligible": ["low", "high"]},
	]}
	match_screen.render(model)
	match_screen.get_node("AbilityPanel").activate_ability(&"sabotage-copy")
	var overlay = match_screen.get_node("TargetingOverlay")
	overlay.select_value("p2")
	overlay.select_value("high")
	overlay.get_node("Panel/Layout/CommitButton").pressed.emit()
	assert_eq(intents[-1], {
		"kind": &"play_public_ability",
		"payload": {
			"copy_id": "sabotage-copy", "target_player_id": "p2",
			"choices": {"target_player_id": ["p2"], "severity": ["high"]},
		},
	})
	await _unmount(match_screen)


func _abilities() -> Array:
	return [
		{"copy_id": "manip-copy", "ability_id": "suit_imprint"},
		{"copy_id": "field-copy", "ability_id": "reverse_clock"},
		{"copy_id": "buff-copy", "ability_id": "pair_boost"},
		{"copy_id": "sabotage-copy", "ability_id": "pair_breaker"},
	]


func _catalog() -> Dictionary:
	return {
		"suit_imprint": {
			"label": "Suit Imprint", "rules_text": "Change both ordinary halves to the chosen suit.", "timing": 0,
			"choice_schema": {"steps": [
				{"key": "cards", "kind": "full_card", "count": 1, "prompt": "Choose a card"},
				{"key": "suit", "kind": "suit", "count": 1, "eligible": [0, 1, 2], "prompt": "Choose suit"},
			]},
		},
		"reverse_clock": {"label": "Reverse Clock", "timing": 1, "choice_schema": {}},
		"pair_boost": {"label": "Pair Boost", "timing": 2, "choice_schema": {}},
		"pair_breaker": {"label": "Pair Breaker", "timing": 3, "choice_schema": {}},
	}


func _active_model(phase: int) -> Dictionary:
	return {
		"phase": phase, "round_number": 2, "active_context": 0, "context_direction": 1,
		"phase_deadline_msec": 10000, "now_msec": 0, "reaction_deadline_msec": -1,
		"private_player_id": "p1",
		"private_hand": [
			{"card_id": "c1", "first": _half(0, 7, 0), "second": _half(1, 4, 2)},
			{"card_id": "c2", "first": _half(0, 2, 1), "second": _half(0, 8, 0)},
		],
		"private_abilities": _abilities(), "ability_catalog": _catalog(),
		"private_staging": {"pending_manipulation": {}, "staged_submission": [], "hand_locked": false},
		"players": [
			{"player_id": "p1", "name": "Mira", "seat_index": 0, "spectator": false, "active": true, "connected": true, "ready": false, "hand_count": 2, "ability_count": 4, "match_score": 4, "round_wins": 0},
			{"player_id": "p2", "name": "North", "seat_index": 1, "spectator": false, "active": true, "connected": true, "ready": false, "hand_count": 6, "ability_count": 2, "match_score": 8, "round_wins": 1},
		],
		"active_fields": [], "frozen": false,
		"victory_mode": 0, "victory_target": 20,
		"pile_counts": {"0": {"draw_count": 70}, "1": {"draw_count": 71}, "2": {"draw_count": 72}},
	}


func _half(context: int, rank: int, suit: int) -> Dictionary:
	return {"effective_context": context, "effective_rank": rank, "effective_suit": suit, "kind": 0}


func _private_cards(count: int) -> Array:
	var result: Array = []
	for index in range(1, count + 1):
		result.append({
			"card_id": "c%d" % index,
			"first": _half(0, index, 0),
			"second": _half(1, index, 1),
		})
	return result


func _control_tree_text(root: Node) -> String:
	var parts: Array[String] = []
	for node in root.find_children("*", "Control", true, false):
		if node is Label or node is Button or node is RichTextLabel:
			parts.append(str(node.text))
		parts.append(str(node.tooltip_text))
		for metadata_key in node.get_meta_list():
			parts.append(str(node.get_meta(metadata_key)))
	return "\n".join(parts)


func _mount(path: String) -> Variant:
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
