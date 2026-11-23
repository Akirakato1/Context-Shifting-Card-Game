extends "res://tests/test_case.gd"

const HAND_CARD := preload("res://src/view/match/card_widget.tscn")
const INVENTORY_CARD := preload("res://src/view/match/ability_inventory_card.tscn")
const REFERENCE_CARD := preload("res://src/view/match/ability_card.tscn")
const CARD_AUDIO := preload("res://src/view/match/card_interaction_audio.gd")


func test_hover_cue_keeps_display_cards_silent_and_rearms_on_mouse_exit() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var container := Control.new()
	tree.root.add_child(container)
	var hand := HAND_CARD.instantiate()
	var inventory := INVENTORY_CARD.instantiate()
	var reference := REFERENCE_CARD.instantiate()
	for card in [hand, inventory, reference]:
		container.add_child(card)
		assert_true(card.has_signal("card_hovered"), "Missing the card hover signal")
	if not hand.has_signal("card_hovered") or not inventory.has_signal("card_hovered"):
		container.free()
		return

	var cues: Array[String] = []
	hand.connect("card_hovered", func(): cues.append("hand"))
	inventory.connect("card_hovered", func(): cues.append("inventory"))
	reference.connect("card_hovered", func(): cues.append("reference"))
	hand.render({"card_id": "test"}, 0)
	hand.mouse_entered.emit()
	hand.mouse_exited.emit()
	reference.render({"timing": 0}, "ability", true, true)
	reference.mouse_entered.emit()
	assert_true(cues.is_empty(), "Display cards should stay quiet")

	hand.render({"card_id": "test"}, 0, false, {"hover_enabled": true, "interaction_disabled": true})
	inventory.render({"timing": 0}, "ability", false, true)
	hand.mouse_entered.emit()
	hand.mouse_entered.emit()
	inventory.mouse_entered.emit()
	inventory.mouse_entered.emit()
	hand.mouse_exited.emit()
	hand.mouse_entered.emit()
	assert_eq(cues, ["hand", "inventory", "hand"], "Local cards should cue once per hover")
	container.free()


func test_hover_cue_follows_the_uppermost_card_and_its_child_controls() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var container := Control.new()
	tree.root.add_child(container)
	var hand := HAND_CARD.instantiate()
	var inventory := INVENTORY_CARD.instantiate()
	container.add_child(hand)
	container.add_child(inventory)
	hand.position = Vector2(30, 30)
	hand.size = Vector2(150, 250)
	inventory.position = Vector2(45, 45)
	inventory.size = Vector2(245, 125)
	hand.render({"card_id": "test"}, 0, false, {"hover_enabled": true})
	inventory.render({"timing": 0}, "ability", false, true)
	var cues: Array[String] = []
	hand.connect("card_hovered", func(): cues.append("hand"))
	inventory.connect("card_hovered", func(): cues.append("inventory"))
	await tree.process_frame

	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(80, 80)
	tree.root.push_input(motion, true)
	motion.position = Vector2(80, 208)
	tree.root.push_input(motion, true)
	assert_eq(cues, ["inventory", "hand"], "Only the card directly under the pointer should cue")
	container.free()


func test_hand_pointer_tells_selectable_and_blocked_halves_apart() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var hand := HAND_CARD.instantiate()
	tree.root.add_child(hand)
	hand.render({"card_id": "test"}, 0, false, {"hover_enabled": true})
	assert_eq(hand.mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND)
	hand.render({"card_id": "test"}, 0, false, {
		"targeting_kind": &"half_card", "targeting_half_eligible": [false, true],
	})
	assert_eq(hand.get_node("Face/FirstHit").mouse_default_cursor_shape, Control.CURSOR_FORBIDDEN)
	assert_eq(hand.get_node("Face/SecondHit").mouse_default_cursor_shape, Control.CURSOR_CROSS)
	hand.render({"card_id": "test"}, 0, true)
	assert_eq(hand.mouse_default_cursor_shape, Control.CURSOR_ARROW)
	hand.free()


func test_audio_cues_use_distinct_clips_and_a_short_placeholder_buzz() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var audio := CARD_AUDIO.new()
	tree.root.add_child(audio)
	var clip_paths: Array[String] = []
	for cue in ["hover", "select", "flip", "shuffle", "drag", "drop", "prime", "unprime", "play"]:
		var path: String = CARD_AUDIO.CUES[StringName(cue)][0]
		assert_false(path in clip_paths, "%s should use a distinct clip" % cue)
		clip_paths.append(path)
		var player := audio.get_node_or_null(cue) as AudioStreamPlayer
		assert_eq(player != null, ResourceLoader.exists(path), cue)
		if player != null:
			assert_eq(player.stream.resource_path, path, cue)
			assert_eq(player.bus, &"Sound Effects")
		else:
			audio.play(StringName(cue))
	var invalid := audio.get_node("invalid") as AudioStreamPlayer
	assert_true(invalid.stream is AudioStreamWAV and invalid.stream.get_length() < 0.15)
	assert_true(invalid.volume_db < -10.0)
	audio.free()


func test_match_audio_uses_the_optional_pack_and_loops_quietly() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var audio := CARD_AUDIO.new()
	tree.root.add_child(audio)
	for cue in ["hover", "select", "flip", "shuffle", "drag", "drop", "draw", "deal", "score"]:
		var path: String = CARD_AUDIO.CUES[StringName(cue)][0]
		assert_true("Card Game SFX Lite" in path, cue)
		var player := audio.get_node_or_null(cue) as AudioStreamPlayer
		assert_eq(player != null, ResourceLoader.exists(path), cue)
	var ambient := audio.get_node_or_null("Ambient") as AudioStreamPlayer
	assert_eq(ambient != null, ResourceLoader.exists(CARD_AUDIO.TABLE_LOOP))
	if ambient != null:
		assert_eq(ambient.bus, &"Ambient")
		var stream := ambient.stream as AudioStreamWAV
		assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
		assert_eq(stream.loop_end, roundi(stream.get_length() * stream.mix_rate))
		assert_true(ambient.volume_db <= -12.0)
		assert_true(ambient.playing)
	audio.free()
