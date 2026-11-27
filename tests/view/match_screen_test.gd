extends "res://tests/test_case.gd"

const MATCH_SCREEN_PATH := "res://src/view/match/match_screen.tscn"


func test_ready_prompt_keeps_its_dark_panel_when_sketch_guides_are_hidden() -> void:
	var table := preload("res://src/view/match/match_screen.tscn").instantiate()
	table.show_placeholder_guides = false
	Engine.get_main_loop().root.add_child(table)
	var controls := table.get_node("PhaseControls")
	var backdrop := controls.get_node_or_null("ReadyBackdrop") as Panel
	assert_true(backdrop != null, "The Ready prompt has a production backdrop")
	if backdrop != null:
		var ready := controls.get_node("MainControls/ReadyButton") as Button
		var style := backdrop.get_theme_stylebox("panel") as StyleBoxFlat
		assert_true(style != null and style.bg_color.b > style.bg_color.r and style.bg_color.v < 0.3)
		for phase in [GameTypes.Phase.MAIN_1, GameTypes.Phase.MAIN_2]:
			table.render({"phase": phase, "private_player_id": "p1", "active_context": 0,
				"players": [{"player_id": "p1", "active": true}, {"player_id": "p2", "active": true}]})
			assert_true(backdrop.is_visible_in_tree())
			assert_true(backdrop.get_global_rect().encloses(ready.get_global_rect()))
			assert_eq(ready.get_theme_stylebox("disabled").texture.resource_path.get_file(), "button_4.png")
			var focus := ready.get_theme_stylebox("focus") as StyleBoxFlat
			assert_true(focus != null and not focus.draw_center and focus.border_color.r > focus.border_color.b)
			assert_true(focus != null and focus.border_width_top == 0
				and focus.border_width_left == 0 and focus.border_width_right == 0)
		table.render({"phase": GameTypes.Phase.HAND_PLAY, "private_player_id": "p1", "active_context": 0})
		assert_false(backdrop.visible)
	table.queue_free()
	await Engine.get_main_loop().process_frame

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


func test_sabotage_marks_only_private_affected_cards_through_snapshot_and_redraw() -> void:
	var table = await _mount_match()
	var model := _active_player_model()
	model.phase = 2
	table.render(model)
	var controls = table.get_node("PhaseControls")
	var changed := StringName(model.private_hand[0].card_id)
	var untouched := StringName(model.private_hand[1].card_id)
	var before: Dictionary = model.private_hand[0].duplicate(true)
	var after := before.duplicate(true)
	after.first.rank = 8
	var event := {"kind": "sabotage_resolved", "payload": {
		"source_player_id": "p2", "target_player_id": "p1", "card_changes": [
			{"card_id": str(changed), "before": before, "after": after},
			{"card_id": str(untouched), "before": {}, "after": {}},
		],
	}}
	table.present_ability_events([event])
	assert_eq(controls.card_widget(changed).tooltip_text, "Recently sabotaged")
	assert_true(controls.card_widget(untouched).tooltip_text.is_empty())
	var highlight: Tween = controls._sabotage_highlights[changed]
	highlight.pause()
	highlight.custom_step(3.0)
	model.private_hand[0] = after
	table.render(model)
	assert_eq(controls.card_widget(changed).tooltip_text, "Recently sabotaged")
	highlight.custom_step(2.0)
	assert_true(controls.card_widget(changed).tooltip_text.is_empty())

	var replacement := &"new-card"
	event.payload["card_changes"] = [{"before": after, "after": before}]
	event.payload["replacement_card_ids"] = [str(replacement)]
	table.present_ability_events([event])
	model.private_hand[0].card_id = str(replacement)
	table.render(model)
	assert_eq(controls.card_widget(replacement).tooltip_text, "Recently sabotaged")
	event.payload["target_player_id"] = "p2"
	event.payload["replacement_card_ids"] = [str(untouched)]
	table.present_ability_events([event])
	assert_true(controls.card_widget(untouched).tooltip_text.is_empty())
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
	var score: Label = reveal.get_node("Content/ScoreLine/ValueSlot/Value")
	var status: Label = reveal.get_node("Content/ScoreLine/Prefix")
	var timeline: Tween = reveal.get("_sequence")
	timeline.pause()
	timeline.custom_step(13.0)
	await Engine.get_main_loop().process_frame
	assert_true(reveal.visible)
	assert_eq(tabs.get_child_count(), 4)
	assert_eq(tabs.get_child(0).text, "Mira (You)")
	assert_eq(cards.get_child_count(), 1)
	assert_eq(cards.get_child(0).card_id, "c1")
	for seat in ["BottomSeat", "TopSeat", "LeftSeat", "RightSeat"]:
		var seat_hand: Control = table.get_node("TableLayer/" + seat + "/Hand")
		assert_false(seat_hand.visible)
		assert_eq(seat_hand.get_child_count(), 0)
	assert_eq(cards.get_child(0).active_half_index, 1)
	assert_true(cards.get_child(0).interaction_disabled)
	assert_eq(table.get_node("PhaseControls").card_widget(&"c1"), null)
	assert_true(reveal.get_global_rect().end.y < table.get_node("PhaseControls/MainControls").get_global_rect().position.y)
	tabs.get_child(1).pressed.emit()
	assert_eq(cards.get_child_count(), 0)
	assert_eq(status.text, "Passed · 0 points")
	assert_false(score.is_visible_in_tree())
	tabs.get_child(2).pressed.emit()
	assert_true(tabs.get_child(2).button_pressed)
	assert_false(tabs.get_child(1).button_pressed)
	assert_eq(cards.get_child_count(), 6)
	assert_eq(score.text, "55")
	var left_score := table.get_node("TableLayer/LeftSeat/Summary/ScoreSummary") as Label
	assert_true(left_score.is_visible_in_tree())
	assert_eq(left_score.text, "55 provisional points")
	model.players[2].revealed_submission.provisional_score = 88
	table.render(model)
	assert_eq(cards.get_child_count(), 6)
	assert_eq(score.text, "88")
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


func test_main_phase_surfaces_ready_status_and_ability_controls() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var model := _active_player_model()
	model.phase = 2
	table.render(model)
	assert_eq(table.get_node("PhaseBadge/Phase").text, "MAIN PHASE 1")
	var hint := table.get_node_or_null("PhaseInstruction") as Label
	assert_true(hint != null and not hint.visible and hint.text.is_empty(), "Regular matches have no idle ability instructions")
	assert_true(table.get_node("Header/Timer").get_theme_font_size("font_size") >= 32)
	var ready: Button = table.get_node("PhaseControls/MainControls/ReadyButton")
	assert_true(ready.custom_minimum_size.y >= 52)
	assert_true(table.get_node("PhaseControls/HandPlayControls/Hand/Cards").modulate != Color.WHITE)
	var other := table.get_node_or_null("TableLayer/TopSeat/Summary/ReadyStatus") as Label
	assert_true(other != null and other.text == "READY" and other.is_visible_in_tree())
	if other != null:
		model.phase = 4
		model.players[1].ready = false
		table.render(model)
		var phase_motion: Tween = table.get_node("PhaseBadge").get("_motion")
		phase_motion.custom_step(1.0)
		assert_eq(table.get_node("PhaseBadge/Phase").text, "MAIN PHASE 2")
		assert_eq(other.text, "DECIDING")
		assert_true(other.is_visible_in_tree())
		model.phase = 3
		table.render(model)
		assert_false(other.visible)
		assert_eq(table.get_node("PhaseControls/HandPlayControls/Hand/Cards").modulate, Color.WHITE)
	await _unmount(table)


func test_hand_play_submission_adds_ready_aura_and_check_to_the_players_portrait() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var model := _active_player_model()
	var local: Control = table.get_node("TableLayer/BottomSeat")
	var top: Control = table.get_node("TableLayer/TopSeat")
	var left: Control = table.get_node("TableLayer/LeftSeat")
	table.render(model)
	assert_true(_visible_ready_portrait(top))
	assert_false(_visible_ready_portrait(left))
	assert_false(local.visible)
	model.players[0].ready = true
	model.players[2].ready = true
	table.render(model)
	await Engine.get_main_loop().process_frame
	assert_true(_visible_ready_portrait(local))
	assert_true(_visible_ready_portrait(left))
	assert_true(local.get_global_rect().end.y <= table.get_node("PhaseControls").get_global_rect().position.y)
	var check := left.get_node_or_null("Info/Name/ReadyCheck") as Label
	if check != null:
		assert_eq(check.text, "✓")
		assert_true(check.get_global_rect().end.x < left.get_node("Info/Name").get_global_rect().get_center().x)
	model.players[2].ready = false
	model.players[0].ready = false
	table.render(model)
	assert_false(_visible_ready_portrait(left))
	assert_false(local.visible)
	model.phase = GameTypes.Phase.MAIN_2
	table.render(model)
	assert_false(_visible_ready_portrait(top))
	assert_false(_visible_ready_portrait(local))
	await _unmount(table)


func _visible_ready_portrait(seat: Control) -> bool:
	var aura := seat.get_node_or_null("Avatar/ReadyAura") as TextureRect
	var check := seat.get_node_or_null("Info/Name/ReadyCheck") as Label
	return aura != null and aura.is_visible_in_tree() and aura.show_behind_parent and (
		check != null and check.is_visible_in_tree()
	)


func test_phase_sign_retracts_before_changing_label_and_lands_once_per_phase() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var sign: Control = table.get_node("PhaseBadge")
	assert_true(sign.has_signal("landed"), "A hanging phase sign signals when it settles")
	if not sign.has_signal("landed"):
		await _unmount(table)
		return
	var landings: Array[String] = []
	var chain_cues: Array[String] = []
	var title: Label = sign.get_node("Phase")
	sign.connect("landed", func(): landings.append(title.text))
	sign.connect("dropping", func(): chain_cues.append("drop"))
	sign.connect("pulling", func(): chain_cues.append("pull"))
	assert_true(sign.get_index() < table.get_node("Header").get_index())
	assert_true(sign.get_index() < table.get_node("MenuButton").get_index())
	var sign_art := (sign.get_node("Art") as TextureRect).texture as AtlasTexture
	assert_eq(sign_art.atlas.resource_path.get_file(), "phase_sign.png")
	var model := _active_player_model()
	model.phase = 2
	table.render(model)
	var motion: Tween = sign.get("_motion")
	var round_badge: PhaseSign = table.get_node("RoundBadge")
	var round_motion: Tween = round_badge.get("_motion")
	round_motion.custom_step(0.5)
	assert_true(round_badge.get_global_rect().end.y > sign.size.y)
	motion.pause()
	assert_true(sign.position.y + sign.size.y < 0.0)
	table.render(model)
	assert_eq(sign.get("_motion"), motion, "Repeated snapshots do not replay the drop")
	motion.custom_step(0.27)
	assert_eq(landings, ["MAIN PHASE 1"])
	assert_true(absf(sign.rotation_degrees) > 1.0)
	assert_true(absf(sign.position.y) > 0.0 and absf(sign.position.y) < 4.0, "The landing briefly shakes the sign")
	motion.custom_step(0.25)
	assert_eq(sign.position.y, 0.0)
	model.phase = 3
	table.render(model)
	assert_eq(round_badge.get("_motion"), round_motion, "A phase change leaves the round sign in place")
	motion = sign.get("_motion")
	motion.pause()
	motion.custom_step(0.07)
	assert_true(sign.position.y < 0.0)
	assert_eq(title.text, "MAIN PHASE 1")
	motion.custom_step(0.08)
	assert_eq(title.text, "HAND PLAY")
	assert_true(sign.position.y + sign.size.y < 0.0, "The text swaps while the wood is off screen")
	motion.custom_step(0.5)
	assert_eq(landings, ["MAIN PHASE 1", "HAND PLAY"])
	assert_eq(chain_cues, ["drop", "pull", "drop"])
	assert_eq(sign.position.y, 0.0)
	model.round_number += 1
	table.render(model)
	assert_true(round_badge.get("_motion") != round_motion)
	await _unmount(table)


func test_timer_glows_red_and_counts_down_each_final_second_once() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var timer: MatchTimer = table.get_node("Header/Timer")
	assert_eq(timer.get_node("Stone").texture.resource_path.get_file(), "timer_tablet.png")
	var ticks: Array[int] = []
	timer.countdown_tick.connect(func(seconds: int): ticks.append(seconds))
	timer.set_period(1, 2)
	timer.show_remaining(10001, false, true)
	assert_eq(timer.get_theme_color("font_shadow_color"), MatchTimer.NORMAL_GLOW)
	timer.show_remaining(10000, false, true)
	assert_eq(timer.get_theme_color("font_shadow_color"), MatchTimer.URGENT_GLOW)
	for remaining in [5001, 5000, 4800, 5300, 4200, 4000, 3000, 2000, 1000, 0]:
		timer.show_remaining(remaining, false, true)
	assert_eq(ticks, [5, 4, 3, 2, 1])
	timer.set_period(1, 3)
	timer.show_remaining(5000, false, false)
	assert_eq(ticks.size(), 5)
	timer.show_remaining(5000, false, true)
	assert_eq(ticks, [5, 4, 3, 2, 1, 5])
	timer.show_remaining(-1, true, true)
	assert_eq(timer.text, "UNTIMED")
	assert_eq(timer.get_theme_color("font_shadow_color"), MatchTimer.NORMAL_GLOW)
	await _unmount(table)


func test_replacement_sounds_load_as_short_one_shots() -> void:
	var table = await _mount_match()
	var sounds: Node = table.get_node("CardInteractionAudio")
	var filenames := {
		"phase_chain_drop": "phase_chain_drop.wav", "phase_chain_pull": "phase_chain_pull.wav",
		"match_countdown": "match_countdown.wav", "invalid": "invalid_action.wav",
	}
	for cue: String in filenames:
		var player := sounds.get_node_or_null(cue) as AudioStreamPlayer
		assert_true(player != null and player.stream is AudioStreamWAV, "%s has a WAV source" % cue)
		if player != null and player.stream is AudioStreamWAV:
			assert_eq(player.stream.resource_path.get_file(), filenames[cue])
			assert_true(player.stream.get_length() > 0.08 and player.stream.get_length() <= 0.26)
			assert_eq((player.stream as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_DISABLED)
			assert_eq(player.bus, &"Sound Effects")
	await _unmount(table)


func test_ability_tray_explains_phase_timing_and_ability_seal() -> void:
	var table = await _mount_match()
	var model := _active_player_model()
	model.phase = GameTypes.Phase.MAIN_1
	model["is_practice"] = true
	model["private_abilities"] = [{"copy_id": "mirror", "ability_id": "mirror_rank", "legal": false}]
	model["ability_catalog"] = {"mirror_rank": {"display_name": "Mirror Rank", "timing": 0}}
	table.render(model)
	var tray: Control = table.get_node("AbilityPanel")
	var status := tray.get_node_or_null("Drawer/Layout/PlayStatus") as Label
	assert_true(status != null and status.visible and status.text.contains("Hand Play"))
	if status != null:
		model.phase = GameTypes.Phase.HAND_PLAY
		model["private_abilities_disabled"] = true
		table.render(model)
		assert_true(status.visible and status.text.contains("Ability Seal"))
		var toggle := tray.get_node("ToggleButton") as Button
		toggle.pressed.emit()
		assert_true(toggle.tooltip_text.contains("Ability Seal"))
		toggle.pressed.emit()
		model.private_abilities_disabled = false
		model.private_abilities[0].legal = true
		table.render(model)
		assert_false(status.visible)
	await _unmount(table)


func test_main_phase_one_opens_the_tray_and_highlights_legal_abilities() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var model := _active_player_model()
	model.phase = 1
	model["private_abilities"] = [
		{"copy_id": "field", "ability_id": "reverse_cycle", "legal": false},
		{"copy_id": "manipulation", "ability_id": "mirror_rank", "legal": false},
		{"copy_id": "unavailable-field", "ability_id": "reverse_cycle", "legal": false},
	]
	model["ability_catalog"] = {
		"reverse_cycle": {"timing": 1}, "mirror_rank": {"timing": 0},
	}
	var drawer: Control = table.get_node("AbilityPanel/Drawer")
	var toggle: Button = table.get_node("AbilityPanel/ToggleButton")
	table.render(model)
	assert_false(drawer.visible)
	model.phase = 2
	model.private_abilities[0].legal = true
	table.render(model)
	assert_true(drawer.visible, "The local player's tray opens on entry to Main Phase 1")
	var cards: Control = drawer.get_node("Layout/Scroll/Cards")
	assert_eq(cards.get_child(0).get("_inventory_playable_highlight"), true)
	assert_eq(cards.get_child(1).get("_inventory_playable_highlight"), false)
	assert_eq(cards.get_child(2).get("_inventory_playable_highlight"), false)
	assert_ne(table.get_node("PhaseControls/HandPlayControls/Hand/Cards").modulate, Color.WHITE)
	toggle.pressed.emit()
	table.render(model)
	assert_false(drawer.visible, "Regular snapshot updates preserve a manual close")
	model.round_number += 1
	table.render(model)
	assert_true(drawer.visible, "A new round opens the tray again")
	model["frozen"] = true
	table.render(model)
	assert_eq(cards.get_child(0).get("_inventory_playable_highlight"), false)
	model.frozen = false
	model.phase = 3
	model.private_abilities[0].legal = false
	model.private_abilities[1].legal = true
	table.render(model)
	assert_eq(cards.get_child(0).get("_inventory_playable_highlight"), false)
	assert_true(cards.get_child(1).get("_inventory_playable_highlight"), "Hand Play highlights its legal manipulation ability")
	model["private_staging"] = {"hand_locked": true}
	table.render(model)
	assert_false(cards.get_child(1).get("_inventory_playable_highlight"), "Submission locks ability play")
	model.private_staging.hand_locked = false
	table.render(model)
	assert_true(cards.get_child(1).get("_inventory_playable_highlight"), "Unlocking restores ability play")
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
	var notice := table.get_node_or_null("DiscardNotice") as PanelContainer
	assert_true(notice != null and notice.visible, "Required discards have a central notice")
	if notice != null:
		assert_eq(notice.get_node("Title").text, "Select 2 cards to keep")
		assert_true(notice.get_theme_stylebox("panel") is StyleBoxFlat)
		assert_eq(notice.get_global_rect().get_center(), table.get_global_rect().get_center())
		assert_eq(notice.mouse_filter, Control.MOUSE_FILTER_IGNORE)
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
	var click := func(control: Control):
		var point := control.get_global_transform_with_canvas() * (control.size / 2.0)
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = point
			event.global_position = point
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			table.get_viewport().push_input(event, true)
	var first_card: Control = cards.get_child(0)
	click.call(first_card.get_node("Face/DetailsButton"))
	assert_true(first_card.find_child("Rules").visible)
	assert_true(drawer.get_node("Layout/DiscardPrompt").text.contains("0 / 2"))
	await Engine.get_main_loop().process_frame
	for card: Control in cards.get_children():
		click.call(card)
	assert_false(confirm.disabled)
	assert_true(drawer.get_node("Layout/DiscardPrompt").text.contains("2 / 2"))
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
	if notice != null:
		assert_false(notice.visible)
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
		assert_eq(title.text, "Two-Pair + Four-card Flush  ×  Four Renaissance")
		var timeline: Tween = reveal._sequence
		timeline.pause()
		timeline.custom_step(1.2)
		assert_eq(title.text, "Two-Pair + Four-card Flush  ×  Four Renaissance")
		assert_true(reveal._score_progress > 0.0 and reveal._score_progress < 1.0)
		timeline.custom_step(2.0)
		assert_eq(title.text, "Full House  ×  Two Full Cycle")
	await _unmount(table)


func test_round_reveal_powers_up_at_every_hundred_and_resets_for_the_next_hand() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var model := _active_player_model()
	model.phase = 4
	var cards := [_revealed_card("milestone", 2, 9, 1, 0, 4, 2, 1)]
	model.players[0]["revealed_submission"] = {"cards": cards, "provisional_score": 315}
	model.players[1]["revealed_submission"] = {"cards": cards, "provisional_score": 115}
	var reveal = table.get_node("RoundReveal")
	var cues: Array[StringName] = []
	reveal.sound_requested.connect(func(cue: StringName):
		if cue == &"score_milestone":
			cues.append(cue)
	)
	table.render(model)
	reveal._sequence.pause()
	reveal._count_score(99.0 / 315)
	assert_eq(cues.size(), 0)
	reveal._count_score(100.0 / 315)
	assert_eq(cues.size(), 1)
	reveal._count_score(199.0 / 315)
	assert_eq(cues.size(), 1)
	reveal._count_score(300.0 / 315)
	assert_eq(cues.size(), 3, "A skipped frame still crosses both milestones")
	var value := reveal.get_node_or_null("Content/ScoreLine/ValueSlot/Value") as Label
	assert_true(value != null)
	if value != null:
		assert_eq(value.text, "300")
		assert_true(value.scale.x > 1.0)
		var powered_color := value.self_modulate
		reveal._select_player("p2", true)
		assert_eq(value.scale, Vector2.ONE)
		assert_false(value.self_modulate == powered_color)
		reveal._count_score(100.0 / 115)
		assert_eq(cues.size(), 4)
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
	model.phase = 4
	table.render(model)
	var reveal_cards: Control = table.get_node("RoundReveal/Content/Cards")
	var revealed = reveal_cards.get_child(0) if reveal_cards.get_child_count() > 0 else null
	assert_true(revealed != null)
	if revealed == null:
		await _unmount(table)
		return
	assert_eq(revealed.first_face_text(), "Fall  9  Cloud")
	assert_eq(revealed.second_face_text(), "Rise  4  Sea")
	assert_eq(revealed.active_half_index, 1)
	model.phase = 5
	table.render(model)
	assert_false(table.get_node("TableLayer/TopSeat/Hand").visible)
	assert_eq(table.get_node("TableLayer/TopSeat/Hand").get_child_count(), 0)
	assert_eq(table.get_node("TableLayer/TopSeat/Summary/ScoreSummary").text, "Hand score 31")
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
	assert_eq(revealed_hand.get_child_count(), 5)
	assert_true(revealed_hand.get_children().all(func(card): return card.face_down))
	var review: Control = table.get_node("RoundReveal/Content/Cards")
	assert_eq(review.get_child_count(), 1)
	if review.get_child_count() == 1:
		assert_eq(review.get_child(0).card_id, "public")
	assert_eq(table.get_node("Header/Spectators").text, "SPECTATORS  2 / 4")
	await _unmount(table)


func test_spectator_switches_between_read_only_live_cockpits() -> void:
	var table = await _mount_match()
	var model := _active_player_model()
	model["round_number"] = 3
	model["phase"] = GameTypes.Phase.HAND_PLAY
	model["local_role"] = "spectator"
	model["ability_catalog"] = {"imprint": {"display_name": "Suit Imprint", "timing": 0}}
	for index in 2:
		var row: Dictionary = model.players[index]
		row["spectator_abilities"] = [{"view_id": "ability-%d" % index, "ability_id": "imprint", "legal": true}]
		row["spectator_hand"] = [
			{"view_id": "%d-a" % index, "first": _half(1, 6, 1), "second": _half(1, 8, 2)},
			{"view_id": "%d-b" % index, "first": _half(1, 9, 1), "second": _half(1, 7, 2)},
		]
	model.erase("private_player_id")
	model.erase("private_hand")
	var intents: Array = []
	table.intent_requested.connect(func(kind: StringName, _payload: Dictionary): intents.append(kind))
	table.render(model)
	var controls: Control = table.get_node("PhaseControls")
	var ability_panel: Control = table.get_node("AbilityPanel")
	var switcher: Control = table.get_node("SpectatorSwitcher")
	assert_eq(switcher.get_node("Watching").text, "Watching Mira")
	assert_eq(switcher.get_node("Players").get_child_count(), 2)
	assert_true(controls.inputs_locked() and ability_panel.inputs_locked())
	assert_true(table.get_node("SortControls/Rank").disabled)
	assert_eq(controls.local_hand_order(), [&"0-a", &"0-b"])

	var live := {
		"round_number": 3, "phase": GameTypes.Phase.HAND_PLAY, "revision": 1,
		"hand_order": ["1-b", "1-a"], "flipped": ["1-b"],
		"staged": [{"view_id": "1-b", "half_index": 1}], "focus": "ability-1",
	}
	table.update_spectator_views({"p2": live})
	assert_eq(controls.local_hand_order(), [&"0-a", &"0-b"])
	# Exercise portrait input as well as the switcher's name buttons.
	var portrait: Control = table.get_node("TableLayer/TopSeat")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = portrait.get_node("Avatar").get_rect().get_center()
	assert_true(portrait._has_point(click.position))
	portrait._gui_input(click)
	assert_eq(switcher.get_node("Watching").text, "Watching North  ·  Primed Suit Imprint")
	assert_eq(controls.local_hand_order(), [&"1-b", &"1-a"])
	assert_eq(controls.staged_order(), [&"1-b"])
	assert_true(controls.card_widget(&"1-b").orientation_flipped)
	assert_true(controls.card_widget(&"1-b").interaction_disabled)
	assert_eq(ability_panel.get("_focused_id"), &"ability-1")
	var toggle: Button = ability_panel.get_node("ToggleButton")
	toggle.pressed.emit()
	assert_true(ability_panel.get_node("Drawer").visible)
	toggle.pressed.emit()
	assert_false(ability_panel.get_node("Drawer").visible)
	controls.click_card(&"1-a")
	assert_eq(controls.staged_order(), [&"1-b"])
	table.render(model)
	assert_eq(controls.local_hand_order(), [&"1-b", &"1-a"], "An older snapshot preserves the current live layout")
	switcher.get_node("Players").get_child(0).pressed.emit()
	assert_eq(controls.local_hand_order(), [&"0-a", &"0-b"])
	assert_eq(intents, [])
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
	assert_eq(table.get_node("RoundBadge/Phase").text, "ROUND 4")
	assert_eq(table.get_node("Header/Timer").text, "12.4s")
	var clock: Control = table.get_node_or_null("TableScenery/ContextClock")
	assert_true(clock != null)
	if clock != null:
		assert_eq(clock.get("_context"), 1)
		assert_eq(clock.get("_direction"), -1)
		assert_true(clock.get("_light_target").is_equal_approx(Vector3(0, 0.42, 1)))
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
	assert_true(table._field_detail_text.tooltip_text.contains("Fall is also active this round."))
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
