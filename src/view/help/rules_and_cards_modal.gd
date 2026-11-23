extends Control

signal closed

const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const AbilityCard = preload("res://src/view/match/ability_card.tscn")
const ScoringReference = preload("res://src/view/app/scoring_reference.gd")

const INK := Color("e4edf5")
const MUTED := Color("afc3d4")
const GOLD := Color("ffd166")
const BLUE := Color("8edcf0")
const ABILITY_TABS := ["Manipulation", "Field", "Buff/Nerf", "Sabotage"]

var _ability_catalog: Dictionary = {}
var _scoring_catalog: Dictionary = {}
var _catalog_dirty := true
var _previous_focus: Control
var _rules_pages: Array[ScrollContainer] = []
var _ability_pages: Array[ScrollContainer] = []
var _normal_rows: VBoxContainer
var _context_rows: VBoxContainer
var _ability_grids: Array[GridContainer] = []
var _ability_tabs: TabContainer

@onready var _tabs: TabContainer = $Panel/Layout/RulesTabs
@onready var _close_button: Button = $Panel/Layout/Header/Close


func _ready() -> void:
	_style_tabs(_tabs, 23)
	_build_how_to_play()
	_normal_rows = _build_scoring_page(
		"Hand Shapes",
		"Rank patterns use the chosen scoring half of each submitted card. The highest-priority rank pattern wins. When the ruleset includes a Flush, its multiplier adds to that pattern if all submitted scoring halves share a suit."
	)
	_context_rows = _build_scoring_page(
		"Context Hands",
		"Count the effective context on both halves of every submitted full card. Thresholds are minimums. If multiple patterns qualify, only the highest-priority one applies."
	)
	_build_ability_tabs()


func render(model: Dictionary) -> void:
	var abilities: Dictionary = model.get("ability_catalog", {})
	var scoring: Dictionary = model.get("scoring_catalog", {})
	if abilities == _ability_catalog and scoring == _scoring_catalog:
		return
	_ability_catalog = abilities.duplicate(true)
	_scoring_catalog = scoring.duplicate(true)
	_catalog_dirty = true
	if visible:
		_refresh_catalogs()


func open() -> void:
	if visible:
		return
	_previous_focus = get_viewport().gui_get_focus_owner()
	_refresh_catalogs()
	_tabs.current_tab = 0
	_ability_tabs.current_tab = 0
	show()
	for page in _rules_pages + _ability_pages:
		page.set_deferred("scroll_vertical", 0)
	_close_button.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	_previous_focus = null
	closed.emit()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_TAB:
		_move_modal_focus(-1 if event.shift_pressed else 1)
		get_viewport().set_input_as_handled()


func _move_modal_focus(direction: int) -> void:
	var stops: Array[Control] = [_close_button, _tabs.get_tab_bar()]
	if _tabs.current_tab == 3:
		stops.append(_ability_tabs.get_tab_bar())
		stops.append(_ability_pages[_ability_tabs.current_tab])
	else:
		stops.append(_rules_pages[_tabs.current_tab])
	var current := stops.find(get_viewport().gui_get_focus_owner())
	stops[posmod(current + direction, stops.size())].grab_focus()


func _build_how_to_play() -> void:
	var content := _new_page(_tabs, "How to Play")
	_label(
		content,
		"Submit up to six full cards. Use the round’s active context to score now and save useful cards for later rounds.",
		24, BLUE
	)
	var steps := VBoxContainer.new()
	steps.add_theme_constant_override("separation", 10)
	content.add_child(steps)
	_add_phase(steps, "Start",
		"The first round opens in Main 1 with three abilities. From round two, draw three abilities and choose the contexts of the halves needed to refill your hand. The game pairs them into full cards.")
	_add_phase(steps, "Main 1",
		"Play Field, Sabotage, or Buff/Nerf abilities. Ready when you’re done.")
	_add_phase(steps, "Hand Play",
		"Use Manipulation abilities, then choose cards with a half that matches an active context. Choose which half scores and submit or pass. Submitted cards leave your hand immediately.")
	_add_phase(steps, "Main 2",
		"Review the revealed hands and provisional scores. Play any final Buff/Nerf abilities and ready.")
	_add_phase(steps, "End",
		"Round scores are finalized and submitted cards are discarded. Discard down to two abilities. The context clock then advances.")
	_label(
		content,
		"In the Abilities drawer, right-click an available card to focus it, then left-click that card to play it. Drag cards to reorder them.",
		20, INK
	)
	_label(content, "Scoring", 27, GOLD)
	_label(
		content,
		"Add the ranks of all chosen scoring halves, then multiply by the Hand Shape, Context Hand, and Field factors. Round the result up. A Joker half has rank 0. Choose its context and suit directly on the card. It keeps those choices while it stays in your hand, even when unstaged.",
		20, INK
	)
	_label(
		content,
		"The host chooses whether the match ends at a total score or a total number of round wins.",
		20, MUTED
	)


func _add_phase(parent: Control, title: String, description: String) -> void:
	var panel := _panel(parent, Color("304556"), 12)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	var heading := _label(row, title, 23, GOLD)
	heading.custom_minimum_size.x = 130
	var detail := _label(row, description, 20, INK)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _build_scoring_page(title: String, intro: String) -> VBoxContainer:
	var content := _new_page(_tabs, title)
	_label(content, intro, 21, BLUE)
	var column_labels := HBoxContainer.new()
	column_labels.add_theme_constant_override("separation", 18)
	content.add_child(column_labels)
	var pattern := _label(column_labels, "Pattern and requirements", 18, MUTED)
	pattern.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_centered_label(column_labels, "Multiplier", 18, MUTED, 102)
	_centered_label(column_labels, "Priority", 18, MUTED, 82)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 7)
	content.add_child(rows)
	return rows


func _build_ability_tabs() -> void:
	_ability_tabs = TabContainer.new()
	_ability_tabs.name = "AbilityTabs"
	_ability_tabs.clip_tabs = false
	_style_tabs(_ability_tabs, 20)
	_tabs.add_child(_ability_tabs)
	_tabs.set_tab_title(3, "Ability Cards")
	for category: String in ABILITY_TABS:
		var content := _new_page(_ability_tabs, category)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 15)
		grid.add_theme_constant_override("v_separation", 15)
		content.add_child(grid)
		_ability_grids.append(grid)


func _style_tabs(tabs: TabContainer, font_size: int) -> void:
	tabs.add_theme_font_override("font", ThemeDB.fallback_font)
	tabs.add_theme_font_size_override("font_size", font_size)
	tabs.add_theme_color_override("font_selected_color", GOLD)
	tabs.add_theme_color_override("font_unselected_color", MUTED)
	tabs.add_theme_color_override("font_hovered_color", INK)
	tabs.add_theme_stylebox_override("tab_selected", _tab_style(Color("22374a"), BLUE))
	tabs.add_theme_stylebox_override("tab_unselected", _tab_style(Color("132332"), Color("344c5e")))
	tabs.add_theme_stylebox_override("tab_hovered", _tab_style(Color("1d3346"), BLUE))
	var background := StyleBoxFlat.new()
	background.bg_color = Color("0c151f")
	background.set_corner_radius_all(5)
	tabs.add_theme_stylebox_override("panel", background)


func _tab_style(fill: Color, line: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = line
	style.border_width_bottom = 2
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _new_page(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	tabs.set_tab_title(tabs.get_tab_count() - 1, title)
	if tabs == _tabs:
		_rules_pages.append(scroll)
	else:
		_ability_pages.append(scroll)
	var margins := MarginContainer.new()
	margins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margins.add_theme_constant_override("margin_top", 18)
	margins.add_theme_constant_override("margin_left", 15)
	margins.add_theme_constant_override("margin_right", 17)
	margins.add_theme_constant_override("margin_bottom", 15)
	scroll.add_child(margins)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	margins.add_child(content)
	return content


func _refresh_catalogs() -> void:
	if not _catalog_dirty:
		return
	_catalog_dirty = false
	var scoring := _scoring_catalog
	if scoring.is_empty():
		scoring = ScoringReference.default_catalog()
	_fill_scoring_rows(_normal_rows, scoring.get("normal", []), true)
	_fill_scoring_rows(_context_rows, scoring.get("context", []), false)
	var abilities := _ability_catalog
	if abilities.is_empty():
		abilities = AbilityCatalog.public_catalog(AbilityCatalog.provisional_deck_recipe())
	_fill_ability_grids(abilities)


func _fill_scoring_rows(rows: VBoxContainer, entries: Array, show_example: bool) -> void:
	for child in rows.get_children():
		child.free()
	if entries.is_empty():
		_label(rows, "No patterns are configured.", 21, MUTED)
	for entry: Dictionary in entries:
		var panel := _panel(rows, Color("304556"), 9)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		panel.add_child(row)
		var detail := VBoxContainer.new()
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.add_theme_constant_override("separation", 3)
		row.add_child(detail)
		_label(detail, _display_name(entry), 22, INK)
		_label(detail, str(entry.get("rules_text", "")), 18, MUTED)
		if show_example:
			var example := _shape_example(entry)
			if not example.is_empty():
				_label(detail, "Example  %s" % example, 18, BLUE)
		_centered_label(row, _multiplier(entry.get("multiplier", {})), 22, GOLD, 102)
		_centered_label(row, str(entry.get("priority", "")), 20, MUTED, 82)


func _shape_example(entry: Dictionary) -> String:
	var size_needed := int(entry.get("subset_size", 0))
	var parameters: Dictionary = entry.get("rule_parameters", {})
	var faces: Array[String] = []
	match str(entry.get("rule_id", "")):
		"high_card":
			faces.append("10")
		"straight":
			for index in range(size_needed):
				faces.append(str(3 + index))
		"grouped_ranks":
			var rank := 8
			for count: int in parameters.get("group_sizes", []):
				for _index in range(count):
					faces.append(str(rank))
				rank -= 2
		"flush":
			for index in range(size_needed):
				faces.append("%d Mountain" % (index + 2))
	return " · ".join(faces)


func _multiplier(value: Dictionary) -> String:
	var numerator := int(value.get("numerator", 1))
	var denominator := maxi(1, int(value.get("denominator", 1)))
	var remainder := absi(numerator) % denominator
	if remainder == 0:
		return "×%d" % (float(numerator) / denominator)
	if (remainder * 100) % denominator == 0:
		return "×%s" % str(float(numerator) / denominator)
	return "×%d/%d" % [numerator, denominator]


func _fill_ability_grids(catalog: Dictionary) -> void:
	for grid in _ability_grids:
		for child in grid.get_children():
			child.free()
	var ids := catalog.keys()
	ids.sort_custom(func(left, right):
		return _display_name(catalog[left], str(left)).nocasecmp_to(
			_display_name(catalog[right], str(right))
		) < 0
	)
	for id in ids:
		var entry: Dictionary = catalog[id]
		var timing := int(entry.get("timing", -1))
		if timing >= 0 and timing < _ability_grids.size():
			var grid := _ability_grids[timing]
			var card = AbilityCard.instantiate()
			grid.add_child(card, true)
			card.render(entry, str(id), true)
	for grid in _ability_grids:
		if grid.get_child_count() == 0:
			_label(grid, "No abilities are configured in this category.", 21, MUTED)


func _display_name(entry: Dictionary, fallback_id: String = "") -> String:
	var id := str(entry.get("id", fallback_id))
	return str(entry.get("display_name", entry.get("label", id.capitalize())))


func _panel(parent: Control, border: Color, padding: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("152333")
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, padding)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _label(parent: Control, words: String, size_px: int, ink: Color) -> Label:
	var label := Label.new()
	label.text = words
	label.add_theme_font_override("font", ThemeDB.fallback_font)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", ink)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _centered_label(
	parent: Control, words: String, size_px: int, ink: Color, width: int
) -> void:
	var label := _label(parent, words, size_px, ink)
	label.custom_minimum_size.x = width
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
