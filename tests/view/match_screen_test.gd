extends "res://tests/test_case.gd"

const MATCH_SCREEN_PATH := "res://src/view/match/match_screen.tscn"


func test_active_player_sees_compact_opponent_summaries_and_their_own_hand() -> void:
	var table = await _mount_match()
	if table == null:
		return
	table.render(_active_player_model())
	var clock: Control = table.get_node_or_null("TableScenery/ContextClock")
	assert_true(clock != null)
	if clock != null:
		assert_eq(clock.get("_context"), 1)
		assert_eq(clock.get("_direction"), 1)
	assert_eq(table.get_node("Center/Piles/PileRise/Name").text, "Rise")
	assert_eq(table.get_node("Center/Piles/PileFlourish/Name").text, "Flourish")
	assert_eq(table.get_node("Center/Piles/PileFall/Name").text, "Fall")
	assert_eq(table.get_node("TableLayer/TopSeat").seat_position, &"top")
	assert_eq(table.get_node("TableLayer/LeftSeat").seat_position, &"left")
	assert_eq(table.get_node("TableLayer/RightSeat").seat_position, &"right")
	assert_eq(table.get_node("TableLayer/BottomSeat").seat_position, &"bottom")
	assert_eq(table.get_node("PhaseControls/HandPlayControls/Hand/Cards").get_child_count(), 6)
	for position in ["TopSeat", "LeftSeat", "RightSeat"]:
		assert_eq(table.get_node("TableLayer/" + position + "/Hand").get_child_count(), 0)
	assert_eq(table.get_node("TableLayer/BottomSeat/Info/Name").text, "YOU  ·  Mira")
	assert_eq(table.get_node("TableLayer/TopSeat/Info/Name").text, "North")
	assert_true(table.get_node("TableLayer/TopSeat/Summary/SeatTally").text.contains("18 pts"))
	assert_true(table.get_node("TableLayer/TopSeat/Summary/SeatTally").text.contains("0 abilities"))
	await _unmount(table)


func test_main_two_submissions_stay_available_and_update_from_public_snapshots() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var model := _active_player_model()
	model.phase = 4
	model.private_hand = model.private_hand.slice(1)
	model.players[0]["revealed_submission"] = {
		"cards": [_revealed_card("c1", 2, 9, 1, 0, 4, 2, 1)], "provisional_score": 27,
	}
	model.players[1]["revealed_submission"] = {"cards": [], "provisional_score": 0}
	var opponent_cards: Array = []
	for index in 6:
		opponent_cards.append(_revealed_card("opp%d" % index, 1, 8, 1, 0, 6, 2, 0))
	model.players[2]["revealed_submission"] = {"cards": opponent_cards, "provisional_score": 55}
	model.players[3]["revealed_submission"] = {
		"cards": [_revealed_card("d1", 2, 9, 1, 0, 4, 2, 1)], "provisional_score": 27,
	}
	table.render(model)
	var reveal: Control = table.get_node("RoundReveal")
	var tabs: HBoxContainer = reveal.get_node("Content/Navigation/Players")
	var cards: HBoxContainer = reveal.get_node("Content/Cards")
	var score: Label = reveal.get_node("Content/Score")
	var timeline: Tween = reveal.get("_sequence")
	timeline.pause()
	timeline.custom_step(13.0)
	await Engine.get_main_loop().process_frame
	assert_true(reveal.visible)
	assert_eq(tabs.get_child_count(), 4)
	assert_eq(tabs.get_child(0).text, "Mira (You)")
	assert_eq(cards.get_child_count(), 1)
	assert_eq(cards.get_child(0).card_id, "c1")
	assert_eq(table.get_node("TableLayer/BottomSeat").card_at(0).card_id, "c1")
	assert_eq(table.get_node("TableLayer/LeftSeat/Hand").get_child_count(), 6)
	assert_eq(cards.get_child(0).active_half_index, 1)
	assert_true(cards.get_child(0).interaction_disabled)
	assert_eq(table.get_node("PhaseControls").card_widget(&"c1"), null)
	assert_true(reveal.get_global_rect().end.y < table.get_node("PhaseControls/MainControls").get_global_rect().position.y)
	tabs.get_child(1).pressed.emit()
	assert_eq(cards.get_child_count(), 0)
	assert_eq(score.text, "Passed · 0 points")
	tabs.get_child(2).pressed.emit()
	assert_true(tabs.get_child(2).button_pressed)
	assert_false(tabs.get_child(1).button_pressed)
	assert_eq(cards.get_child_count(), 6)
	assert_eq(score.text, "55 provisional points")
	var left_score := table.get_node("TableLayer/LeftSeat/Summary/ScoreSummary") as Label
	assert_true(left_score.is_visible_in_tree())
	assert_eq(left_score.text, "55 provisional points")
	model.players[2].revealed_submission.provisional_score = 88
	table.render(model)
	assert_eq(cards.get_child_count(), 6)
	assert_eq(score.text, "88 provisional points")
	assert_eq(left_score.text, "88 provisional points")
	model.erase("private_player_id")
	model.erase("private_hand")
	table.render(model)
	assert_true(reveal.visible)
	assert_false(table.get_node("PhaseControls").visible)
	assert_eq(tabs.get_child(0).text, "Mira")
	tabs.get_child(3).pressed.emit()
	assert_eq(cards.get_child(0).card_id, "d1")
	model.phase = 5
	table.render(model)
	assert_false(reveal.visible)
	await _unmount(table)


func test_locked_card_is_marked_and_cannot_enter_a_preview() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var model := _active_player_model()
	var card: Dictionary = model.private_hand[0]
	var id := StringName(card.card_id)
	card["eligible_half_indexes"] = [0, 1]
	table.render(model)
	var controls = table.get_node("PhaseControls")
	controls.click_card(id)
	assert_true(controls.has_staged_card(id))
	card["submission_locked"] = true
	table.render(model)
	assert_false(controls.has_staged_card(id))
	var widget: Control = controls.card_widget(id)
	var marker := widget.get_node_or_null("Face/SubmissionLock") as Label
	assert_true(marker != null and marker.visible)
	controls.click_card(id)
	assert_false(controls.has_staged_card(id))
	assert_eq(controls.get_node("HandPlayControls/InvalidReason").text, "This card is locked for this round.")
	await _unmount(table)


func test_end_opens_and_focuses_tray_and_confirms_only_the_unkept_cards() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var model := _active_player_model()
	model.phase = 5
	model["private_abilities"] = [
		{"copy_id": "a1", "ability_id": "mirror_rank"},
		{"copy_id": "a2", "ability_id": "suit_imprint"},
		{"copy_id": "a3", "ability_id": "rise_resonance"},
	]
	model["required_ability_discards"] = 1
	model.players[1]["discard_complete"] = false
	var intents: Array = []
	table.intent_requested.connect(func(kind: StringName, payload: Dictionary): intents.append([kind, payload]))
	var drawer: Control = table.get_node("AbilityPanel/Drawer")
	assert_false(drawer.visible)
	table.render(model)
	assert_true(drawer.visible)
	assert_true(table.get_node("AbilityFocus").visible)
	assert_false(table.get_node("PhaseControls/EndControls").visible)
	var cards: Control = drawer.get_node("Layout/Scroll/Cards")
	var confirm := drawer.get_node_or_null("Layout/ConfirmKeep") as Button
	assert_true(confirm != null)
	if confirm == null:
		await _unmount(table)
		return
	assert_eq(cards.get_child_count(), 3)
	assert_true(confirm.disabled)
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	for card: Control in cards.get_children():
		var point := card.get_global_transform_with_canvas() * (card.size / 2.0)
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = point
			event.global_position = point
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			table.get_viewport().push_input(event, true)
	assert_false(confirm.disabled)
	assert_true(drawer.get_node("Layout/Heading").text.contains("2 / 2"))
	assert_true(table.get_node("TableLayer/TopSeat/Summary/SeatTally").text.contains("Discarding"))
	model.players[1]["discard_complete"] = true
	table.render(model)
	assert_false(confirm.disabled, "Another player's discard preserves the local choices")
	assert_true(table.get_node("TableLayer/TopSeat/Summary/SeatTally").text.contains("Ready"))
	confirm.pressed.emit()
	confirm.pressed.emit()
	assert_eq(intents, [[&"choose_ability_discards", {"copy_ids": ["a3"]}]])
	table.handle_command_result(&"choose_ability_discards", true, &"", 5)
	model["required_ability_discards"] = 0
	model.private_abilities.pop_back()
	table.render(model)
	assert_false(drawer.visible)
	assert_false(table.get_node("AbilityFocus").visible)
	await _unmount(table)


func test_round_reveal_showcases_the_full_named_hand_for_each_player() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var model := _active_player_model()
	model.phase = 4
	model["scoring_catalog"] = preload("res://src/view/app/scoring_reference.gd").default_catalog()
	var cards := [_revealed_card("showcase", 2, 9, 1, 0, 4, 2, 1)]
	model.players[0]["revealed_submission"] = {
		"cards": cards, "normal_category": "two_pair", "context_category": "rise_flourish_4",
		"provisional_score": 84, "score_breakdown": {"card_hand_components": [
			{"source_definition_id": "two_pair"}, {"source_definition_id": "flush_4"},
		]},
	}
	model.players[1]["revealed_submission"] = {
		"cards": cards, "normal_category": "full_house", "context_category": "all_contexts_2",
		"provisional_score": 63,
	}
	table.render(model)
	var reveal = table.get_node("RoundReveal")
	var title := reveal.get_node_or_null("Content/HandName") as Label
	assert_true(title != null)
	if title != null:
		assert_eq(title.text, "Two Pair + 4-card Flush  ×  Four Renaissance")
		var timeline: Tween = reveal._sequence
		timeline.pause()
		timeline.custom_step(1.2)
		assert_eq(title.text, "Two Pair + 4-card Flush  ×  Four Renaissance")
		assert_true(reveal._score_progress > 0.0 and reveal._score_progress < 1.0)
		timeline.custom_step(2.0)
		assert_eq(title.text, "Full House  ×  Two Full Cycle")
	await _unmount(table)


func test_local_and_revealed_cards_render_effective_faces_and_active_half() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var model := _active_player_model()
	model.players[1]["revealed_submission"] = {
		"cards": [_revealed_card("r1", 2, 9, 1, 0, 4, 2, 1)],
		"normal_category": "pair",
		"context_category": "all_contexts_1",
		"base_value": 18,
		"provisional_score": 27,
		"finalized_score": 31,
	}
	table.render(model)
	var local_card = table.get_node("PhaseControls").card_widget(&"c1")
	assert_eq(local_card.first_face_text(), "Rise  7  Mountain")
	assert_eq(local_card.second_face_text(), "Flourish  4  Sea")
	assert_eq(local_card.active_half_index, 1)
	model.phase = 5
	table.render(model)
	var revealed = table.get_node("TableLayer/TopSeat").card_at(0)
	assert_true(revealed != null)
	if revealed == null:
		await _unmount(table)
		return
	assert_eq(revealed.first_face_text(), "Fall  9  Cloud")
	assert_eq(revealed.second_face_text(), "Rise  4  Sea")
	assert_eq(table.get_node("TableLayer/TopSeat/Summary/ScoreSummary").text, "31 points this round")
	await _unmount(table)


func test_context_hand_names_and_exact_multipliers_are_readable() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var model := _active_player_model()
	model.phase = 5
	model["scoring_catalog"] = preload("res://src/view/app/scoring_reference.gd").default_catalog()
	var score: Label = table.get_node("TableLayer/TopSeat/Summary/ScoreSummary")
	for expected in [
		["all_contexts_2", "Two Full Cycle"],
		["fall_7", "Seven Descent"],
		["rise_flourish_5", "Five Renaissance"],
	]:
		model.players[1]["revealed_submission"] = {
			"normal_category": "pair", "context_category": expected[0],
			"finalized_score": 31,
		}
		table.render(model)
		assert_true(score.tooltip_text.contains(expected[1]))
	model.players[1]["revealed_submission"] = {
		"context_category": "rise_flourish_5",
		"score_breakdown": {
			"base_value": 10, "card_hand_components": [],
			"context_hand_components": [{
				"category_id": "two_context", "source_definition_id": "rise_flourish_5",
				"value": {"numerator": 5, "denominator": 2},
			}],
			"field_components": [], "applied_modifiers": [],
			"context_hand_unclamped": {"numerator": 5, "denominator": 2},
			"context_hand_factor": {"numerator": 5, "denominator": 2},
			"final_score": 25,
		},
	}
	table.render(model)
	assert_true(score.tooltip_text.contains("Five Renaissance 5/2"))
	await _unmount(table)


func test_public_information_shows_piles_requests_and_spectator_has_no_local_hand() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var public_model := _active_player_model()
	public_model["replacement_requests"] = {"p2": {"0": 2, "1": 1, "2": 3}}
	table.render(public_model)
	assert_eq(table.get_node("Center/Piles/PileRise/Count").text, "68 left")
	assert_false(table.get_node("TableLayer/TopSeat/Request").visible)

	var private_model := _active_player_model()
	private_model.erase("pile_counts")
	private_model.erase("replacement_requests")
	table.render(private_model)
	assert_eq(table.get_node("Center/Piles/PileRise/Count").text, "Hidden")
	assert_false(table.get_node("TableLayer/TopSeat/Request").visible)

	var spectator_model := public_model
	spectator_model.erase("private_player_id")
	spectator_model.erase("private_hand")
	table.render(spectator_model)
	assert_true(table.get_node("TableLayer/TopSeat/Request").visible)
	assert_eq(table.get_node("TableLayer/TopSeat/Request").text, "DRAW  Rise 2 · Flourish 1 · Fall 3")
	for position in ["TopSeat", "BottomSeat"]:
		var hand = table.get_node("TableLayer/" + position + "/Hand")
		assert_true(hand.visible)
		assert_eq(hand.get_child_count(), 6)
		for card in hand.get_children():
			assert_true(card.face_down)
			assert_true(card.interaction_disabled)
	var watched_cards: Array = []
	for index in 6:
		watched_cards.append({
			"view_id": "watched-%d" % index,
			"first": _half(2, 9, 1), "second": _half(0, 4, 2),
		})
	spectator_model.players[1]["spectator_hand"] = watched_cards
	table.render(spectator_model)
	var watched_hand: Control = table.get_node("TableLayer/TopSeat/Hand")
	assert_eq(watched_hand.get_child_count(), 6)
	assert_false(watched_hand.get_child(0).face_down)
	assert_true(watched_hand.get_child(0).interaction_disabled)
	assert_eq(watched_hand.get_child(0).first_face_text(), "Fall  9  Cloud")
	spectator_model.players[1].erase("spectator_hand")
	spectator_model.phase = 4
	spectator_model.players[1].hand_count = 5
	spectator_model.players[1]["revealed_submission"] = {
		"cards": [_revealed_card("public", 2, 9, 1, 0, 4, 2, 1)], "provisional_score": 8,
	}
	table.render(spectator_model)
	var revealed_hand = table.get_node("TableLayer/TopSeat/Hand")
	assert_eq(revealed_hand.get_child_count(), 6)
	var public_cards = revealed_hand.get_children().filter(func(card): return not card.face_down)
	assert_eq(public_cards.size(), 1)
	if public_cards.size() == 1:
		assert_eq(public_cards[0].card_id, "public")
	assert_eq(table.get_node("Header/Spectators").text, "SPECTATORS  2 / 4")
	await _unmount(table)


func test_context_score_progress_fields_and_nil_round_render_clearly() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var model := _active_player_model()
	model["context_direction"] = -1
	model["victory_mode"] = 0
	model["victory_target"] = 100
	model["last_round_nil"] = true
	model["active_fields"] = [
		{"ability_id": "reverse_cycle", "source_player_id": "p3", "remaining_rounds": -1, "persistent": true},
		{"ability_id": "fall_resonance", "source_player_id": "p2", "remaining_rounds": 1, "persistent": false,
			"effect_parameters": {"field_rule": "additional_context", "context": 2}},
	]
	model["ability_catalog"] = {
		"reverse_cycle": {"display_name": "Reverse Cycle", "rules_text": "Reverse the direction in which contexts cycle."},
		"fall_resonance": {"display_name": "Fall Resonance", "rules_text": "Fall is also active this round."},
	}
	model["active_contexts"] = [1, 2]
	model.players[0]["provisional_score"] = {
		"score_breakdown": {
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
			"field_unclamped": {"numerator": 1, "denominator": 1}, "field_factor": {"numerator": 1, "denominator": 1},
			"final_score": 550,
		},
	}
	table.render(model)
	assert_eq(table.get_node("PhaseBadge/Phase").text, "HAND PLAY")
	assert_eq(table.get_node("Header/Round").text, "ROUND 4")
	assert_eq(table.get_node("Header/Timer").text, "12.4s")
	var clock: Control = table.get_node_or_null("TableScenery/ContextClock")
	assert_true(clock != null)
	if clock != null:
		assert_eq(clock.get("_context"), 1)
		assert_eq(clock.get("_direction"), -1)
		assert_eq(clock.get("_light_target"), Vector3(0, 0, 1))
	assert_false(table.get_node("TableLayer/BottomSeat").visible)
	assert_eq(table.get_node("MatchScore/Progress").text, "SCORE RACE  ·  36 / 100")
	var field_rows: Container = table.get_node("Center/Fields/FieldScroll/FieldRows")
	assert_eq(field_rows.get_child_count(), 2)
	var reverse: Button = field_rows.get_child(0)
	var reverse_duration := reverse.get_node_or_null("Display/Duration") as Label
	assert_true(reverse_duration != null and reverse_duration.text == "∞")
	var field_info: Button = field_rows.get_child(1)
	var field_duration := field_info.get_node_or_null("Display/Duration") as Label
	var field_icon := field_info.get_node_or_null("Display/Icon") as TextureRect
	assert_true(field_duration != null and field_duration.text == "◷1")
	assert_true(field_icon != null and field_icon.texture.resource_path.ends_with("context_emblem_fall.png"))
	assert_true(field_info.tooltip_text.contains("Fall is also active this round."))
	assert_true(field_info.tooltip_text.contains(model.players[1].name))
	field_info.pressed.emit()
	assert_true(table._field_details.dialog_text.contains("Fall is also active this round."))
	assert_eq(table.get_node("Center/RoundResult").text, "NIL ROUND  ·  no progress awarded")

	model["victory_mode"] = 1
	model["victory_target"] = 5
	table.render(model)
	assert_eq(table.get_node("MatchScore/Progress").text, "ROUND-WIN RACE  ·  2 / 5")
	await _unmount(table)


func test_active_effect_rows_show_signed_amounts_conditions_and_targets() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var model := _active_player_model()
	model["active_fields"] = [{
		"ability_id": "mountain_favor", "remaining_rounds": 3,
		"effect_parameters": {"field_rule": "per_selected_suit", "suit": 0, "numerator": 1, "denominator": 10},
	}, {
		"ability_id": "fall_ascendancy", "remaining_rounds": 1,
		"effect_parameters": {"field_rule": "leading_context", "context": 2, "numerator": 1, "denominator": 4},
	}]
	model["active_score_modifiers"] = [{
		"target_player_id": model.players[0].player_id, "source_definition_id": "family_nerf",
		"factor_id": "card_hand", "category_id": "family", "delta": {"numerator": -3, "denominator": 1},
	}]
	table.render(model)
	var rows: Container = table.get_node("Center/Fields/FieldScroll/FieldRows")
	assert_eq(rows.get_child_count(), 3)
	var suit_effect := rows.get_child(0).get_node_or_null("Display/Effect") as Label
	var suit_icon := rows.get_child(0).get_node_or_null("Display/Icon") as TextureRect
	var context_effect := rows.get_child(1).get_node_or_null("Display/Effect") as Label
	var nerf_effect := rows.get_child(2).get_node_or_null("Display/Effect") as Label
	assert_true(suit_effect != null and suit_effect.text == "+0.1 /")
	assert_true(suit_icon != null and suit_icon.texture.atlas.resource_path.ends_with("card_suit_mountain.png"))
	assert_true(context_effect != null and context_effect.text == "≥ +0.25")
	assert_true(nerf_effect != null and nerf_effect.text.contains("-3") and nerf_effect.text.contains("Family"))
	assert_true(rows.get_child(0).tooltip_text.contains("Mountain"))
	assert_true(rows.get_child(1).tooltip_text.contains("ties"))
	assert_true(rows.get_child(2).tooltip_text.contains(model.players[0].name))
	model.active_score_modifiers = []
	model.active_fields = []
	model["active_contexts"] = [model.active_context]
	table.render(model)
	assert_eq(rows.get_child_count(), 0)
	assert_false(rows.is_visible_in_tree())
	await _unmount(table)


func test_commit_payload_contains_only_structured_choices() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var intents: Array[Dictionary] = []
	table.intent_requested.connect(func(kind: StringName, payload: Dictionary):
		intents.append({"kind": kind, "payload": payload})
	)
	var model := _active_player_model()
	model.private_abilities = [{"copy_id": "mirror-copy", "ability_id": "mirror_rank"}]
	model.ability_catalog = {
		"mirror_rank": {
			"label": "Mirror Rank", "rules_text": "Mirror both ranks.", "timing": 0,
			"choice_schema": {"steps": [{
				"key": "cards", "kind": "full_card", "count": 1,
			}]},
		},
	}
	model.private_staging = {
		"pending_manipulation": {}, "completed_manipulation_ids": [],
		"staged_submission": [], "hand_locked": false,
	}
	table.render(model)
	table.get_node("AbilityPanel").activate_ability(&"mirror-copy")
	table.get_node("TargetingOverlay").select_value("c1")

	assert_eq(intents[-1], {
		"kind": &"commit_manipulation",
		"payload": {"choices": {"cards": ["c1"]}},
	})
	assert_eq(intents[-1].payload.keys(), ["choices"])
	await _unmount(table)


func _active_player_model() -> Dictionary:
	return {
		"round_number": 4,
		"phase": 3,
		"active_context": 1,
		"context_direction": 1,
		"phase_deadline_msec": 12400,
		"now_msec": 0,
		"private_player_id": "p1",
		"private_hand": [
			_private_card("c1", 0, 7, 0, 1, 4, 2),
			_private_card("c2", 0, 2, 1, 2, 8, 0),
			_private_card("c3", 0, 5, 2, 1, 1, 0),
			_private_card("c4", 1, 9, 1, 2, 3, 2),
			_private_card("c5", 2, 6, 0, 0, 10, 1),
			_private_card("c6", 1, 4, 2, 2, 7, 1),
		],
		"players": [
			{"player_id": "p1", "name": "Mira", "seat_index": 0, "active": true, "spectator": false, "connected": true, "ready": false, "hand_count": 6, "match_score": 36, "round_wins": 2},
			{"player_id": "p2", "name": "North", "seat_index": 1, "active": true, "spectator": false, "connected": true, "ready": true, "hand_count": 6, "match_score": 18, "round_wins": 1},
			{"player_id": "p3", "name": "West", "seat_index": 2, "active": true, "spectator": false, "connected": true, "ready": false, "hand_count": 4, "match_score": 9, "round_wins": 0},
			{"player_id": "p4", "name": "East", "seat_index": 3, "active": true, "spectator": false, "connected": false, "ready": false, "hand_count": 5, "match_score": 6, "round_wins": 0},
			{"player_id": "s1", "name": "Watcher", "seat_index": -1, "active": false, "spectator": true, "connected": true, "ready": false, "hand_count": 0, "match_score": 0, "round_wins": 0},
			{"player_id": "s2", "name": "Viewer", "seat_index": -1, "active": false, "spectator": true, "connected": true, "ready": false, "hand_count": 0, "match_score": 0, "round_wins": 0},
		],
		"pile_counts": {
			"0": {"draw_count": 68, "used_count": 23},
			"1": {"draw_count": 71, "used_count": 20},
			"2": {"draw_count": 65, "used_count": 26},
		},
		"active_fields": [],
		"victory_mode": 0,
		"victory_target": 100,
	}


func _private_card(
	card_id: String,
	first_context: int,
	first_rank: int,
	first_suit: int,
	second_context: int,
	second_rank: int,
	second_suit: int
) -> Dictionary:
	return {
		"card_id": card_id,
		"first": _half(first_context, first_rank, first_suit),
		"second": _half(second_context, second_rank, second_suit),
	}


func _revealed_card(
	card_id: String,
	first_context: int,
	first_rank: int,
	first_suit: int,
	second_context: int,
	second_rank: int,
	second_suit: int,
	selected_half_index: int
) -> Dictionary:
	return {
		"card_id": card_id,
		"selected_half_index": selected_half_index,
		"halves": [
			{"context": first_context, "rank": first_rank, "suit": first_suit, "joker": false},
			{"context": second_context, "rank": second_rank, "suit": second_suit, "joker": false},
		],
	}


func _half(context: int, rank: int, suit: int) -> Dictionary:
	return {
		"effective_context": context,
		"effective_rank": rank,
		"effective_suit": suit,
		"kind": 0,
	}


func _mount_match() -> Variant:
	if not ResourceLoader.exists(MATCH_SCREEN_PATH):
		assert_true(false, "%s must exist" % MATCH_SCREEN_PATH)
		return null
	var node = load(MATCH_SCREEN_PATH).instantiate()
	Engine.get_main_loop().root.add_child(node)
	await Engine.get_main_loop().process_frame
	return node


func _unmount(node: Node) -> void:
	node.queue_free()
	await Engine.get_main_loop().process_frame
