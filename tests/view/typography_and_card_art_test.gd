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
	assert_false(widget.get_node("Face/First").text.contains("10"))
	await _unmount(widget)


func test_joker_rank_uses_zero_art_while_other_card_text_uses_theme_font() -> void:
	var widget = await _mount_card()
	if widget == null: return
	widget.render({"card_id": "joker", "first": _joker(), "second": _half(1, 7, 2)}, 0)
	var digits = widget.get_node("Face/FirstRankArt").get_children()
	assert_eq(digits.size(), 1)
	assert_eq(digits[0].texture.resource_path, "res://assets/artwork/card_number/png/card_number_0.png")
	assert_true(widget.get_node("Face/First").text.contains("JOKER"))
	assert_true(widget.get_node("Face/First").get_theme_font("font") != null)
	await _unmount(widget)


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
