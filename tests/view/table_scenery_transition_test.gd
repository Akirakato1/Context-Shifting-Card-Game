extends "res://tests/test_case.gd"

const GameIcons := preload("res://src/view/common/game_icons.gd")
const GameTypes := preload("res://src/core/common/game_types.gd")


func test_context_art_is_wired_and_crossfades_with_the_board_shade() -> void:
	var scene := load("res://src/view/match/match_screen.tscn") as PackedScene
	var table := scene.instantiate()
	Engine.get_main_loop().root.add_child(table)
	var scenery := table.get_node("TableScenery")
	var context_textures: Array = [
		scenery.get("rise_background"), scenery.get("flourish_background"), scenery.get("fall_background"),
	]
	assert_eq(context_textures.map(func(texture: Texture2D) -> String:
		return texture.resource_path.get_file() if texture != null else ""
	), ["background_rise.png", "background_flourish.png", "background_fall.png"])
	var background := scenery.get_node_or_null("ContextBackground") as ColorRect
	var shade := scenery.get_node_or_null("ContextShade") as ColorRect
	assert_true(background != null and shade != null, "Scenery has separate crossfaded backdrop and shade layers")
	if background != null and shade != null:
		var background_material := background.material as ShaderMaterial
		var shade_material := shade.material as ShaderMaterial
		scenery.render(0, 1, [0])
		assert_eq(background_material.get_shader_parameter("weights"), Vector3(1, 0, 0))
		assert_eq(shade_material.get_shader_parameter("opacity"), 0.5)
		scenery.render(1, 1, [1])
		var transition: Tween = scenery.get("_transition")
		transition.pause()
		transition.custom_step(0.21)
		var middle: Vector3 = background_material.get_shader_parameter("weights")
		assert_true(middle.x > 0.0 and middle.y > 0.0)
		assert_true(is_equal_approx(middle.x + middle.y + middle.z, 1.0))
		assert_eq(shade_material.get_shader_parameter("weights"), middle)
		scenery.render(1, -1, [1, 2])
		assert_eq(scenery.get("_transition"), transition, "Direction or an added context does not restart the fade")
		scenery.render(2, -1, [2])
		assert_eq(background_material.get_shader_parameter("weights"), middle, "A new context starts from the current blend")
		transition = scenery.get("_transition")
		transition.pause()
		transition.custom_step(1.0)
		assert_eq(background_material.get_shader_parameter("weights"), Vector3(0, 0, 1))
		assert_eq(shade_material.get_shader_parameter("weights"), Vector3(0, 0, 1))
	table.queue_free()
	await Engine.get_main_loop().process_frame


func test_suit_clock_keeps_a_fixed_clockwise_order_in_the_dashboard_corner() -> void:
	var scene := load("res://src/view/match/match_screen.tscn") as PackedScene
	var table := scene.instantiate()
	Engine.get_main_loop().root.add_child(table)
	var scenery := table.get_node("TableScenery") as Control
	var context_clock := scenery.get_node("ContextClock") as Control
	var suit_clock := scenery.get_node_or_null("SuitClock") as Control
	assert_true(suit_clock != null, "The dashboard has a suit cycle reference")
	if suit_clock != null:
		var mountain := suit_clock.get_node("Mountain") as TextureRect
		var cloud := suit_clock.get_node("Cloud") as TextureRect
		var sea := suit_clock.get_node("Sea") as TextureRect
		var direction := suit_clock.get_node("Direction") as TextureRect
		var dial := suit_clock.get_node("Dial") as TextureRect
		assert_eq(dial.texture.resource_path.get_file(), "suit_compass.png")
		assert_eq(mountain.texture, GameIcons.suit(GameTypes.Suit.MOUNTAIN))
		assert_eq(cloud.texture, GameIcons.suit(GameTypes.Suit.CLOUD))
		assert_eq(sea.texture, GameIcons.suit(GameTypes.Suit.SEA))
		assert_true(mountain.anchor_top < cloud.anchor_top)
		assert_true(cloud.anchor_left > mountain.anchor_left)
		assert_true(sea.anchor_left < mountain.anchor_left)
		assert_eq(suit_clock.tooltip_text, "Suit clock\nMountain → Cloud → Sea → Mountain")
		for emblem in [mountain, cloud, sea]:
			assert_eq(emblem.self_modulate, Color(1, 0.81, 0.27, 1))
		var tray := scenery.get_node("HandTrayArt") as Control
		scenery.set_anchors_preset(Control.PRESET_TOP_LEFT)
		for view_size: Vector2 in [Vector2(1920, 1080), Vector2(1280, 720)]:
			scenery.size = view_size
			var context_bounds := context_clock.get_global_rect()
			var suit_bounds := suit_clock.get_global_rect()
			assert_true(suit_bounds.get_center().x < context_bounds.get_center().x)
			assert_true(suit_bounds.get_center().y < context_bounds.get_center().y)
			var centers_distance := suit_bounds.get_center().distance_to(context_bounds.get_center())
			assert_true(centers_distance > (context_bounds.size.x + suit_bounds.size.x) * 0.5)
			assert_true(suit_bounds.end.x < tray.get_global_rect().position.x)
			assert_true(suit_bounds.size.x < context_bounds.size.x)
			assert_true(is_equal_approx(suit_bounds.size.x, suit_bounds.size.y))
		scenery.render(0, 1, [0])
		scenery.render(2, -1, [1, 2])
		assert_eq(direction.texture.resource_path.get_file(), "clock_directionarrow_1.png")
		assert_eq(suit_clock.rotation, 0.0)
	table.queue_free()
	await Engine.get_main_loop().process_frame


func test_context_clock_animates_art_and_distinguishes_primary_and_extra_contexts() -> void:
	var scene := load("res://src/view/match/match_screen.tscn") as PackedScene
	var table := scene.instantiate()
	Engine.get_main_loop().root.add_child(table)
	var scenery := table.get_node("TableScenery")
	var clock := scenery.get_node_or_null("ContextClock") as Control
	assert_true(clock != null, "The clock uses the authored dial and pointer")
	if clock != null:
		var cues: Array[StringName] = []
		clock.transition_sound.connect(func(cue: StringName): cues.append(cue))
		scenery.show_placeholder_guides = false
		scenery.render(0, 1, [0])
		var pointer := clock.get_node("Pointer") as TextureRect
		var forward := clock.get_node("ForwardCycle") as TextureRect
		var reverse := clock.get_node("ReverseCycle") as TextureRect
		var names := clock.get_node("Names") as TextureRect
		assert_eq(pointer.texture.resource_path.get_file(), "clock_arow.png")
		assert_eq(names.texture.resource_path.get_file(), "clock_text.png")
		assert_eq(forward.texture.resource_path.get_file(), "clock_directionarrow_1.png")
		assert_eq(reverse.texture.resource_path.get_file(), "clock_directionarrow_2.png")
		assert_eq(reverse.self_modulate.a, 0.0)
		assert_true(is_equal_approx(names.material.get_shader_parameter("backlight").x, 0.42))
		assert_true(cues.is_empty())
		var initial_angle := pointer.rotation
		scenery.render(0, -1, [0, 2])
		var fade: Tween = clock.get("_light_tween")
		fade.pause()
		fade.custom_step(1.0)
		assert_true(names.material.get_shader_parameter("backlight").is_equal_approx(Vector3(0.42, 0, 1)))
		assert_eq(pointer.rotation, initial_angle)
		var flip: Tween = clock.get("_direction_tween")
		flip.pause()
		flip.custom_step(1.0)
		assert_eq(reverse.self_modulate.a, 1.0)
		scenery.render(2, -1, [2])
		var sweep: Tween = clock.get("_pointer_tween")
		sweep.pause()
		sweep.custom_step(0.19)
		assert_true(pointer.rotation < initial_angle)
		var intermediate := pointer.rotation
		scenery.render(2, -1, [2])
		assert_eq(clock.get("_pointer_tween"), sweep)
		sweep.custom_step(1.0)
		assert_true(pointer.rotation < intermediate)
		fade = clock.get("_light_tween")
		fade.pause()
		fade.custom_step(1.0)
		assert_true(names.material.get_shader_parameter("backlight").is_equal_approx(Vector3(0, 0, 0.42)))
		assert_eq(cues, [&"clock_reverse", &"clock_tick"])
	table.queue_free()
	await Engine.get_main_loop().process_frame
