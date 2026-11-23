extends "res://tests/test_case.gd"


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
