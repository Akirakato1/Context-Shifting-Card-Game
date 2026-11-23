extends "res://tests/test_case.gd"

const ANIMATION_PATH := "res://src/view/match/draw_animation.gd"


func test_hand_halves_start_at_their_sources_and_land_on_the_current_slot() -> void:
	var fixture := _mount()
	if fixture.is_empty():
		return
	var renderer: Control = fixture.renderer
	var stage: Control = fixture.stage
	var original_slot := _slot(stage, Vector2(240, 270))
	var replacement := _slot(stage, Vector2(420, 310))
	var target := [original_slot]
	var landed: Array[Control] = []
	renderer.connect(&"landed", func(slot: Control): landed.append(slot))
	var sources: Array[Vector2] = [Vector2(110, 160), Vector2(250, 76)]
	var flight: Control = renderer.call("play_hand_draw", {
		"card_id": "drawn",
		"first": {"base_context": 0, "rank": 5, "suit": 0},
		"second": {"base_context": 2, "rank": 7, "suit": 2},
	}, sources, func() -> Control: return target[0])
	assert_true(flight != null, "the hand draw creates a transient flight")
	if flight != null:
		var impact: Array[bool] = []
		flight.connect(&"landed", func(): impact.append(true))
		assert_eq(flight.mouse_filter, Control.MOUSE_FILTER_IGNORE)
		var halves := flight.find_children("Half*", "TextureRect", false, false)
		assert_eq(halves.size(), 2)
		for i in halves.size():
			var half: TextureRect = halves[i]
			assert_true(half.texture != null)
			var center := half.get_global_transform_with_canvas() * (half.size * 0.5)
			assert_true(center.is_equal_approx(sources[i]))
		original_slot.queue_free()
		target[0] = replacement
		await flight.tree_exited
		assert_eq(impact, [true])
		assert_eq(landed, [replacement])
		assert_true(replacement.visible)
		assert_eq(replacement.modulate, Color.WHITE)
	fixture.canvas.queue_free()
	await Engine.get_main_loop().process_frame


func test_ability_draw_tracks_the_toggle_and_cancels_delayed_work() -> void:
	var fixture := _mount()
	if fixture.is_empty():
		return
	var renderer: Control = fixture.renderer
	var stage: Control = fixture.stage
	var slot := _slot(stage, Vector2(570, 180))
	var toggle := Button.new()
	stage.add_child(toggle)
	toggle.position = Vector2(550, 420)
	toggle.size = Vector2(210, 48)
	var target := [slot]
	var landed: Array[Control] = []
	renderer.connect(&"landed", func(destination: Control): landed.append(destination))
	var card := {"ability_id": "boost", "display_name": "Boost", "timing": 2}
	var flight: Control = renderer.call("play_ability_draw", card, Vector2(130, 160), func() -> Control: return target[0])
	var delayed: Control = renderer.call("play_ability_draw", card, Vector2(130, 160), toggle, 2.0)
	assert_true(flight != null and delayed != null)
	if flight != null and delayed != null:
		assert_false(delayed.visible)
		target[0] = toggle
		slot.hide()
		await flight.tree_exited
		assert_eq(landed, [toggle])
		renderer.call("cancel")
		await Engine.get_main_loop().process_frame
		await Engine.get_main_loop().process_frame
		assert_false(is_instance_valid(delayed))
		assert_eq(landed, [toggle])
	fixture.canvas.queue_free()
	await Engine.get_main_loop().process_frame


func test_speed_change_applies_to_both_running_draws() -> void:
	var fixture := _mount()
	if fixture.is_empty():
		return
	var renderer: Control = fixture.renderer
	var slot := _slot(fixture.stage, Vector2(420, 310))
	var sources: Array[Vector2] = [Vector2(110, 160), Vector2(250, 76)]
	var hand: Control = renderer.call("play_hand_draw", {"card_id": "drawn"}, sources, slot)
	var ability: Control = renderer.call("play_ability_draw", {"ability_id": "boost"}, sources[0], slot)
	var hand_animation: Tween = hand.get("timeline")
	var ability_animation: Tween = ability.get("timeline")
	hand_animation.pause()
	ability_animation.pause()
	var landings: Array[String] = []
	hand.connect(&"landed", func(): landings.append("hand"))
	ability.connect(&"landed", func(): landings.append("ability"))
	hand_animation.custom_step(0.55)
	ability_animation.custom_step(0.55)
	assert_eq(landings, [])

	renderer.call("set_playback_speed", 2.0)
	hand_animation.custom_step(0.15)
	ability_animation.custom_step(0.15)
	assert_eq(landings, ["ability"])
	hand_animation.custom_step(0.15)
	assert_eq(landings, ["ability", "hand"])
	fixture.canvas.queue_free()
	await Engine.get_main_loop().process_frame


func _mount() -> Dictionary:
	assert_true(ResourceLoader.exists(ANIMATION_PATH), "the draw animation renderer exists")
	if not ResourceLoader.exists(ANIMATION_PATH):
		return {}
	var animation_script := load(ANIMATION_PATH)
	if animation_script == null or not animation_script.can_instantiate():
		assert_true(false, "the draw animation renderer can be instantiated")
		return {}
	var canvas := CanvasLayer.new()
	Engine.get_main_loop().root.add_child(canvas)
	canvas.offset = Vector2(15, 24)
	var stage := Control.new()
	canvas.add_child(stage)
	stage.position = Vector2(62, 35)
	stage.scale = Vector2(0.8, 0.8)
	var renderer: Control = animation_script.new()
	stage.add_child(renderer)
	return {"stage": stage, "renderer": renderer, "canvas": canvas}


func _slot(stage: Control, position: Vector2) -> Control:
	var slot := Control.new()
	stage.add_child(slot)
	slot.position = position
	slot.size = Vector2(120, 180)
	return slot
