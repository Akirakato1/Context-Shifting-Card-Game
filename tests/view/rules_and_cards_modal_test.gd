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
	assert_eq(card.get_node("Artwork").texture, preload("res://assets/artwork/card/card_ability_manipulation.png"))
	card.render({}, "unconfigured_sample", true)
	assert_true(card.get_node("Artwork").texture == null)
	assert_true(card.get_theme_stylebox("panel") is StyleBoxFlat)
	card.free()


func test_help_lists_named_context_tiers_alongside_the_required_counts() -> void:
	var modal := _create_modal()
	if modal == null:
		return
	modal.open()
	var tabs := modal.find_child("RulesTabs", true, false) as TabContainer
	var context_text := _label_text(tabs.get_tab_control(2))
	assert_true("Four Renaissance" in context_text)
	assert_true("Submit at least 4 Rise and 4 Flourish halves." in context_text)
	assert_true("Twelve Golden Age" in context_text)
	modal.free()


func test_hand_tabs_sort_by_exact_multiplier_and_group_independently() -> void:
	var modal := _create_modal()
	var entries := [
		{"id": "weak", "display_name": "Weak", "priority": 50,
			"broad_category_id": "family", "multiplier": {"numerator": 1, "denominator": 1}},
		{"id": "medium", "display_name": "Medium", "priority": 30,
			"broad_category_id": "family", "multiplier": {"numerator": 9, "denominator": 8}},
		{"id": "strong", "display_name": "Strong", "priority": 10,
			"broad_category_id": "flush", "multiplier": {"numerator": 3, "denominator": 2}},
	]
	modal.render({"scoring_catalog": {"normal": entries, "context": entries}})
	modal.open()
	var tabs := modal.find_child("RulesTabs", true, false) as TabContainer
	var normal := tabs.get_tab_control(1)
	var context := tabs.get_tab_control(2)
	var normal_rows := normal.find_child("HandRows", true, false)
	var context_rows := context.find_child("HandRows", true, false)
	assert_true("Weak" in _label_text(normal_rows.get_child(0)))
	var sort := normal.find_child("HandSort", true, false) as OptionButton
	sort.select(1)
	sort.item_selected.emit(1)
	assert_true("Strong" in _label_text(normal_rows.get_child(0)))
	assert_true("Medium" in _label_text(normal_rows.get_child(1)))
	assert_true("Weak" in _label_text(context_rows.get_child(0)))
	var group := normal.find_child("GroupHandTypes", true, false) as CheckButton
	group.set_pressed(true)
	assert_eq(normal_rows.get_child(0).text, "Flush")
	assert_eq(normal_rows.get_child(2).text, "Family")
	assert_true("Medium" in _label_text(normal_rows.get_child(3)))
	assert_true("Weak" in _label_text(normal_rows.get_child(4)))
	assert_eq(context_rows.get_child_count(), 3)
	sort.select(2)
	sort.item_selected.emit(2)
	assert_eq(normal_rows.get_child(0).text, "Family")
	assert_true("Weak" in _label_text(normal_rows.get_child(1)))
	modal.free()


func test_ability_search_updates_across_categories_with_name_and_rules_terms() -> void:
	var modal := _create_modal()
	modal.render({"ability_catalog": {
		"suit_imprint": {
			"display_name": "Suit Imprint", "rules_text": "Choose mountain.", "timing": 0, "copies": 4,
		},
		"mountain_favor": {
			"display_name": "Mountain Favor", "rules_text": "Boost the field.", "timing": 1, "copies": 1,
		},
	}})
	modal.open()
	var search := modal.find_child("AbilitySearch", true, false) as LineEdit
	var tabs := modal.find_child("AbilityTabs", true, false) as TabContainer
	var results := modal.find_child("AbilitySearchResults", true, false) as ScrollContainer
	search.text_changed.emit("MOUNTAIN")
	assert_false(tabs.visible)
	assert_true(results.visible)
	assert_true("Suit Imprint" in _label_text(results) and "Mountain Favor" in _label_text(results))
	search.text_changed.emit("imprint mountain")
	assert_true("Suit Imprint" in _label_text(results) and not "Mountain Favor" in _label_text(results))
	search.text_changed.emit("unmatched")
	assert_true("No abilities match" in _label_text(results))
	search.text_changed.emit("")
	assert_true(tabs.visible)
	assert_false(results.visible)
	modal.free()


func test_filters_stay_above_the_scrolling_rows_and_search_fits_smaller_widths() -> void:
	var modal := _create_modal()
	modal.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	modal.size = Vector2(900, 720)
	modal.open()
	var tabs := modal.find_child("RulesTabs", true, false) as TabContainer
	tabs.current_tab = 1
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	var scoring := tabs.get_tab_control(1)
	var scroll := scoring.find_child("ScoringScroll", true, false) as ScrollContainer
	var sort := scoring.find_child("HandSort", true, false) as OptionButton
	assert_false(scroll.is_ancestor_of(sort))
	assert_true(sort.get_global_rect().end.y <= scroll.get_global_rect().position.y)
	tabs.current_tab = 3
	var search := modal.find_child("AbilitySearch", true, false) as LineEdit
	search.text = "suit"
	search.text_changed.emit(search.text)
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	var results := modal.find_child("AbilitySearchResults", true, false) as ScrollContainer
	var grid := results.find_children("*", "GridContainer", true, false)[0] as GridContainer
	assert_eq(grid.columns, 1)
	assert_true(search.get_global_rect().end.y <= results.get_global_rect().position.y)
	assert_true(modal.get_global_rect().encloses(search.get_global_rect()))
	modal.size = Vector2(1920, 1080)
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	assert_eq(grid.columns, 2)
	modal.free()


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
	for label: RichTextLabel in node.find_children("*", "RichTextLabel", true, false):
		result.append(label.tooltip_text if not label.tooltip_text.is_empty() else label.get_parsed_text())
	return "\n".join(result)
