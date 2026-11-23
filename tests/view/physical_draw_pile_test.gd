extends "res://tests/test_case.gd"

const MatchScreen = preload("res://src/view/match/match_screen.tscn")


func test_scene_decks_show_count_and_raise_draw_origin_with_stack_height() -> void:
	var table = MatchScreen.instantiate()
	Engine.get_main_loop().root.add_child(table)
	await Engine.get_main_loop().process_frame
	for pile_name in ["PileRise", "PileFlourish", "PileFall", "PileAbility"]:
		var pile = table.get_node_or_null("Center/Piles/" + pile_name)
		assert_true(pile != null and pile.has_method("render"), pile_name + " renders a physical stack")
		if pile == null or not pile.has_method("render"):
			continue
		if pile_name == "PileAbility":
			assert_eq(pile.top_art, preload("res://assets/artwork/card/ability_card_back.png"))
		pile.render(100, 100)
		var full: Vector2 = pile.draw_origin()
		pile.render(50, 100)
		var half_full: Vector2 = pile.draw_origin()
		pile.render(0, 100)
		var empty: Vector2 = pile.draw_origin()
		assert_true(full.y < half_full.y and half_full.y < empty.y)
		assert_true(is_equal_approx(half_full.y, (full.y + empty.y) * 0.5))
		assert_eq(pile.get_node("Count").text, "0 left")
		pile.render(-1, 100)
		assert_eq(pile.get_node("Count").text, "Hidden")
	table.queue_free()
	await Engine.get_main_loop().process_frame
