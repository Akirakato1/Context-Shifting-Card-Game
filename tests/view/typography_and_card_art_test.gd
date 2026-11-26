extends "res://tests/test_case.gd"

const CARD_WIDGET_PATH := "res://src/view/match/card_widget.tscn"


func test_placeholder_theme_uses_mountain_king_as_default_font() -> void:
	var theme: Theme = load("res://themes/placeholder_theme.tres")
	assert_true(theme.default_font != null)
	assert_eq(theme.default_font.resource_path, "res://assets/fonts/mountain_king/MountainKingRegular.ttf")


func test_card_rank_uses_number_art_and_ten_composes_one_then_zero() -> void:
	var widget = await _mount_card()
	if widget == null: return
	widget.render({"card_id": "ten", "first": _half(0, 10, 0), "second": _half(1, 4, 1)}, 0)
	var digits = widget.get_node("Face/FirstRankArt").get_children()
	assert_eq(digits.size(), 2)
	assert_eq(digits[0].texture.resource_path, "res://assets/artwork/card_number/png/card_number_1.png")
	assert_eq(digits[1].texture.resource_path, "res://assets/artwork/card_number/png/card_number_0.png")
	assert_true(widget.get_node("Face/First") is TextureRect)
	await _unmount(widget)


func test_rank_and_suit_stay_upright_when_halves_swap() -> void:
	var widget = await _mount_card()
	widget.size = Vector2(175, 279)
	var card := {"card_id": "flip", "first": _half(0, 10, 0), "second": _half(1, 3, 1)}
	for flipped in [false, true]:
		widget.render(card, 0, false, {"orientation_flipped": flipped})
		await Engine.get_main_loop().process_frame
		var top := "Second" if flipped else "First"
		var bottom := "First" if flipped else "Second"
		var top_suit := widget.get_node("Face/" + top) as TextureRect
		var bottom_suit := widget.get_node("Face/" + bottom) as TextureRect
		assert_true(top_suit != null and bottom_suit != null)
		if top_suit == null or bottom_suit == null:
			await _unmount(widget)
			return
		var top_rank: Control = widget.get_node("Face/" + top + "RankArt")
		var bottom_rank: Control = widget.get_node("Face/" + bottom + "RankArt")
		assert_eq(_suit_asset(top_suit), "card_suit_cloud.png" if flipped else "card_suit_mountain.png")
		assert_eq(_suit_asset(bottom_suit), "card_suit_mountain.png" if flipped else "card_suit_cloud.png")
		assert_eq(top_rank.position.y, top_suit.position.y)
		assert_eq(bottom_rank.position.y, bottom_suit.position.y)
		assert_true(top_rank.position.y < bottom_rank.position.y)
		assert_true(top_rank.position.x + top_rank.size.x <= top_suit.position.x)
		assert_true(bottom_suit.position.x + bottom_suit.size.x <= bottom_rank.position.x)
		assert_eq(top_rank.modulate, Color.WHITE)
		assert_eq(bottom_rank.modulate, Color.WHITE)
		for marker: Control in [top_suit, bottom_suit, top_rank, bottom_rank]:
			assert_eq(marker.rotation, 0.0)
	var requested_flips: Array[StringName] = []
	widget.orientation_requested.connect(func(id: StringName): requested_flips.append(id))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.position = widget.get_global_rect().position + Vector2(25, 30)
	click.pressed = true
	widget.get_viewport().push_input(click, true)
	click.pressed = false
	widget.get_viewport().push_input(click, true)
	assert_eq(requested_flips, [&"flip"])
	await _unmount(widget)


func test_joker_rank_uses_zero_art_and_assigned_suit() -> void:
	var widget = await _mount_card()
	if widget == null: return
	widget.theme = load("res://themes/placeholder_theme.tres")
	widget.custom_minimum_size = Vector2(175, 279)
	widget.render({"card_id": "joker", "first": _joker(), "second": _half(1, 7, 2)}, 1, false, {
		"select_in_place": true,
		"staged": true,
		"joker_choices": [{"half_index": 0, "context": 1, "suit": 2}],
	})
	await Engine.get_main_loop().process_frame
	var digits = widget.get_node("Face/FirstRankArt").get_children()
	assert_eq(digits.size(), 1)
	assert_eq(digits[0].texture.resource_path, "res://assets/artwork/card_number/png/card_number_0.png")
	var joker_suit := widget.get_node("Face/First") as TextureRect
	assert_true(joker_suit != null)
	if joker_suit != null:
		assert_eq(_suit_asset(joker_suit), "card_suit_sea.png")
	assert_eq(widget.size, Vector2(175, 279))
	assert_true(widget.get_theme_stylebox("panel") is StyleBoxEmpty)
	var top := widget.get_node("Artwork/TopHalf") as TextureRect
	var bottom := widget.get_node("Artwork/BottomHalf") as TextureRect
	assert_eq((top.texture as AtlasTexture).atlas.resource_path.get_file(), "card_joker_green.png")
	assert_true(top.material is ShaderMaterial)
	assert_eq(bottom.material, null)
	widget.render({"card_id": "joker", "first": _joker(), "second": _half(1, 7, 2)}, 0)
	assert_eq((top.texture as AtlasTexture).atlas.resource_path.get_file(), "card_joker_white.png")
	assert_eq(top.material, null)
	widget.render({"selected_half_index": 1, "halves": [
		{"context": 2, "rank": 0, "suit": 1, "joker": true},
		{"context": 1, "rank": 7, "suit": 2, "joker": false},
	]})
	assert_eq((bottom.texture as AtlasTexture).atlas.resource_path.get_file(), "card_joker_red.png")
	assert_true(bottom.material is ShaderMaterial)
	assert_eq(top.material, null)
	await _unmount(widget)


func test_card_can_use_supplied_frame_art_and_has_no_default_blue_panel() -> void:
	var widget = await _mount_card()
	if widget == null:
		return
	var data := {"card_id": "framed", "first": _half(0, 2, 1), "second": _half(1, 7, 2)}
	widget.render(data, 0)
	assert_true(widget.get_theme_stylebox("panel") is StyleBoxEmpty)
	var frame := widget.get_node_or_null("Frame") as TextureRect
	assert_true(frame != null, "The front should support transparent replacement frame art")
	if frame != null:
		assert_false(frame.visible)
		var normal := GradientTexture2D.new()
		var selected := GradientTexture2D.new()
		widget.frame_art = normal
		widget.selected_frame_art = selected
		widget.render(data, 0)
		assert_eq(frame.texture, normal)
		widget.render(data, 0, false, {"select_in_place": true, "staged": true})
		assert_eq(frame.texture, selected)
		widget.render(data, 0, true)
		assert_false(frame.visible)
		var back := widget.get_node("Back") as TextureRect
		var back_atlas := back.texture as AtlasTexture
		assert_eq(back_atlas.atlas.resource_path.get_file(), "card_back.png")
	await _unmount(widget)


func _suit_asset(icon: TextureRect) -> String:
	var texture: Texture2D = icon.texture
	if texture is AtlasTexture:
		texture = texture.atlas
	return texture.resource_path.get_file() if texture != null else ""


func test_card_context_art_meets_the_divider_and_follows_orientation() -> void:
	var widget = await _mount_card()
	var artwork := widget.get_node_or_null("Artwork") as Control
	assert_true(artwork != null, "Card face should have a shared layer for its three art assets.")
	if artwork == null:
		await _unmount(widget)
		return
	var top := artwork.get_node("TopHalf") as TextureRect
	var bottom := artwork.get_node("BottomHalf") as TextureRect
	var divider := artwork.get_node("Divider") as TextureRect
	var card := {"card_id": "art", "first": _half(0, 10, 0), "second": _half(2, 4, 1)}
	widget.render(card, 0)
	assert_eq((top.texture as AtlasTexture).atlas.resource_path.get_file(), "card_half_context_rise.png")
	assert_eq((bottom.texture as AtlasTexture).atlas.resource_path.get_file(), "card_half_context_fall.png")
	assert_eq((divider.texture as AtlasTexture).atlas.resource_path.get_file(), "card_divider.png")
	assert_eq((top.texture as AtlasTexture).region, (divider.texture as AtlasTexture).region)
	assert_eq((bottom.texture as AtlasTexture).region, (divider.texture as AtlasTexture).region)
	assert_true(bottom.flip_h and bottom.flip_v)
	widget.render(card, 0, false, {
		"orientation_flipped": true,
		"interaction_disabled": true,
		"display_only": true,
	})
	assert_true(widget.interaction_disabled)
	assert_eq(widget.modulate, Color.WHITE)
	assert_eq((top.texture as AtlasTexture).atlas.resource_path.get_file(), "card_half_context_fall.png")
	assert_eq((bottom.texture as AtlasTexture).atlas.resource_path.get_file(), "card_half_context_rise.png")
	widget.render(card, 0, true)
	assert_false(artwork.visible)
	await _unmount(widget)


func test_half_target_clicks_follow_the_artwork_diagonal_in_both_orientations() -> void:
	var widget: CardWidget = await _mount_card()
	widget.position = Vector2(100, 80)
	widget.size = Vector2(175, 279)
	widget.scale = Vector2(1.2, 0.9)
	var card := {"card_id": "diagonal", "first": _half(0, 10, 0), "second": _half(2, 4, 1)}
	var targets: Array[int] = []
	widget.half_target_requested.connect(func(_id: StringName, index: int): targets.append(index))

	# These points are on opposite sides of the artwork's diagonal and the card's midpoint.
	var top_point := Vector2(0.16, 0.53)
	var bottom_point := Vector2(0.84, 0.47)
	for flipped: bool in [false, true]:
		targets.clear()
		widget.render(card, 0, false, {
			"orientation_flipped": flipped,
			"targeting_kind": &"half_card",
			"targeting_half_eligible": [true, false],
			"targeting_half_selected": [true, false],
		})
		await Engine.get_main_loop().process_frame
		_click_card_point(widget, top_point)
		assert_eq(targets, [] if flipped else [0], "Click through the lower left of the top artwork.")
		_click_card_point(widget, bottom_point)
		assert_eq(targets, [0], "Only the eligible half should be targeted in either orientation.")
	await _unmount(widget)


func _click_card_point(widget: CardWidget, normalized_point: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = widget.get_global_transform() * (normalized_point * widget.size)
	click.pressed = true
	widget.get_viewport().push_input(click, true)
	click.pressed = false
	widget.get_viewport().push_input(click, true)


func _half(context: int, rank: int, suit: int) -> Dictionary:
	return {"effective_context": context, "effective_rank": rank, "effective_suit": suit, "kind": 0}


func _joker() -> Dictionary:
	return {"effective_context": 0, "effective_rank": 0, "effective_suit": -1, "kind": 1}


func _mount_card():
	var node = load(CARD_WIDGET_PATH).instantiate()
	Engine.get_main_loop().root.add_child(node)
	await Engine.get_main_loop().process_frame
	return node


func _unmount(node: Node) -> void:
	node.queue_free()
	await Engine.get_main_loop().process_frame
