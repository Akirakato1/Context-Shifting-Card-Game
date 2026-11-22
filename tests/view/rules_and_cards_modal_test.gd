extends "res://tests/test_case.gd"

const MODAL_PATH := "res://src/view/help/rules_and_cards_modal.tscn"


func test_modal_opens_to_rules_and_escape_closes_it() -> void:
	var modal = _create_modal()
	if modal == null:
		return
	assert_false(modal.visible)
	modal.open()
	assert_true(modal.visible)
	var tabs := modal.find_child("RulesTabs", true, false) as TabContainer
	assert_eq(tabs.get_tab_count(), 4)
	assert_eq(tabs.get_tab_title(tabs.current_tab), "How to Play")
	tabs.current_tab = 3
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	modal.get_viewport().push_input(escape)
	assert_false(modal.visible)
	modal.open()
	assert_eq(tabs.current_tab, 0)
	modal.free()


func test_catalog_uses_public_definitions_including_zero_copies() -> void:
	var modal = _create_modal()
	if modal == null:
		return
	modal.render({
		"private": {"display_name": "SECRET HAND", "card_id": "hidden-1"},
		"ability_catalog": {
			"sample_field": {
				"display_name": "Sample Field", "timing": 1, "field_duration": 3,
				"rules_text": "Public effect description.", "copies": 0,
			},
			"sample_buff": {
				"display_name": "Sample Buff", "timing": 2,
				"rules_text": "Public buff description.", "copies": 3,
			},
		},
		"scoring_catalog": {
			"normal": [{
				"display_name": "Custom Straight", "rules_text": "Exactly four consecutive ranks.",
				"priority": 99, "multiplier": {"numerator": 9, "denominator": 4},
				"rule_id": "straight", "subset_size": 4,
			}],
			"context": [{
				"display_name": "Custom Context", "rules_text": "Four Rise halves.",
				"priority": 9, "multiplier": {"numerator": 3, "denominator": 2},
			}],
		},
	})
	modal.open()
	var ability_tabs := modal.find_child("AbilityTabs", true, false) as TabContainer
	assert_eq(ability_tabs.get_tab_count(), 4)
	assert_eq(ability_tabs.get_tab_title(1), "Field")
	assert_eq(ability_tabs.get_tab_title(2), "Buff/Nerf")
	var field_text := _label_text(ability_tabs.get_tab_control(1))
	assert_true("Sample Field" in field_text and "0 copies" in field_text)
	assert_true("Main 1" in field_text and "Public effect description." in field_text)
	var field_card := ability_tabs.get_tab_control(1).find_child("AbilityCard", true, false) as Control
	assert_true(field_card != null and field_card.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var buff_text := _label_text(ability_tabs.get_tab_control(2))
	assert_true("Sample Buff" in buff_text and "3 copies" in buff_text)
	var rules_tabs := modal.find_child("RulesTabs", true, false) as TabContainer
	var hand_text := _label_text(rules_tabs.get_tab_control(1))
	assert_true("Custom Straight" in hand_text and "×2.25" in hand_text and "99" in hand_text)
	assert_true("3 · 4 · 5 · 6" in hand_text and "Flush" in hand_text)
	var context_text := _label_text(rules_tabs.get_tab_control(2))
	assert_true("both halves" in context_text and "Four Rise halves." in context_text)
	assert_false("SECRET HAND" in _label_text(modal))
	modal.free()


func test_ability_card_uses_supplied_category_backdrop_and_frame() -> void:
	var card = preload("res://src/view/match/ability_card.tscn").instantiate()
	var backdrop := PlaceholderTexture2D.new()
	var frame := StyleBoxTexture.new()
	card.field_background = backdrop
	card.field_frame = frame
	Engine.get_main_loop().root.add_child(card)
	card.render({"timing": 1}, "sample_field", true)
	assert_eq(card.get_node("Artwork").texture, backdrop)
	assert_eq(card.get_theme_stylebox("panel"), frame)
	card.render({"timing": 0}, "sample_manipulation", true)
	assert_true(card.get_node("Artwork").texture == null)
	assert_true(card.get_theme_stylebox("panel") is StyleBoxFlat)
	card.free()


func _create_modal() -> Control:
	if not ResourceLoader.exists(MODAL_PATH):
		assert_true(false, "The in-match help modal scene is missing")
		return null
	var scene := load(MODAL_PATH) as PackedScene
	if scene == null:
		assert_true(false, "The in-match help modal could not be loaded")
		return null
	var modal := scene.instantiate() as Control
	Engine.get_main_loop().root.add_child(modal)
	return modal


func _label_text(node: Node) -> String:
	var result: Array[String] = []
	for label in node.find_children("*", "Label", true, false):
		result.append(label.text)
	return "\n".join(result)
