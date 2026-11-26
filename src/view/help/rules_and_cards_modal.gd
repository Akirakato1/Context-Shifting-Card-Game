extends Control

const GameIcons := preload("res://src/view/common/game_icons.gd")

signal closed

const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const AbilityCard = preload("res://src/view/match/ability_card.tscn")
const ScoringReference = preload("res://src/view/app/scoring_reference.gd")

const INK := Color("e4edf5")
const MUTED := Color("afc3d4")
const GOLD := Color("ffd166")
const BLUE := Color("8edcf0")
const ABILITY_TABS := ["Manipulation", "Field", "Buff/Nerf", "Sabotage"]
const CARD_GRID_GAP := 15
const CARD_COLUMN_WIDTH := 378
const PAGE_SIDE_INSETS := 32
const HAND_TYPES := {
	"high_card": "High Card",
	"family": "Family",
	"group": "Group",
	"straight": "Straight",
	"flush": "Flush",
	"single_context": "Single Context",
	"two_context": "Two Contexts",
	"three_context": "Three Contexts",
}

enum HandSort { PRIORITY, MULTIPLIER_HIGH, MULTIPLIER_LOW }

var _ability_catalog: Dictionary = {}
var _scoring_catalog: Dictionary = {}
var _catalog_dirty := true
var _previous_focus: Control
var _rules_pages: Array[ScrollContainer] = []
var _ability_pages: Array[ScrollContainer] = []
var _hand_pages: Dictionary = {}
var _ability_grids: Array[GridContainer] = []
var _ability_tabs: TabContainer
var _ability_search: LineEdit
var _search_scroll: ScrollContainer
var _search_grid: GridContainer
var _ability_index: Array[Dictionary] = []

@onready var _tabs: TabContainer = $Panel/Layout/RulesTabs
@onready var _close_button: Button = $Panel/Layout/Header/Close


func _ready() -> void:
	_style_tabs(_tabs, 23)
	_build_how_to_play()
	_build_scoring_page(
		"normal", "Hand Shapes",
		"Rank patterns use the chosen scoring half of each submitted card. The highest-priority rank pattern wins. When the ruleset includes a Flush, its multiplier adds to that pattern if all submitted scoring halves share a suit."
	)
	_build_scoring_page(
		"context", "Context Hands",
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
		stops.append(_ability_search)
		if _search_scroll.visible:
			stops.append(_search_scroll)
		else:
			stops.append(_ability_tabs.get_tab_bar())
			stops.append(_ability_pages[_ability_tabs.current_tab])
	else:
		if _tabs.current_tab in [1, 2]:
			var page: Dictionary = _hand_pages["normal" if _tabs.current_tab == 1 else "context"]
			stops.append(page.sort)
			stops.append(page.group)
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
		"Use Manipulation abilities, then choose cards with a half that matches an active context. Choose which half scores and submit or pass. If time runs out, the game submits your staged cards. Use Undo Submit to edit while other players are still choosing.")
	_add_phase(steps, "Main 2",
		"Review the revealed hands and provisional scores. Play any final Buff/Nerf abilities and ready.")
	_add_phase(steps, "End",
		"Round scores are finalized. If someone wins the match, go straight to Results. Otherwise, anyone holding more than two abilities selects two to keep in their ability tray. Everyone can choose at the same time.")
	_label(
		content,
		"Open Abilities and right-click a playable card to begin. Use a card’s eye to read its description, or use the eye beside Abilities to show all descriptions. Drag cards to reorder them.",
		20, INK
	)
	_label(content, "Scoring", 27, GOLD)
	_label(
		content,
		"Base Score adds the ranks of your selected scoring halves. Multiply that base by the Hand Shape, Context Hand, and Field factors, then round up. Choose a Joker half’s context, suit, and optional rank directly on the card. A Joker can use any currently active context, including one added by Resonance. If its choice becomes inactive, it uses the context on the clock. Its rank can form hand shapes and contributes zero to Base Score.",
		20, INK
	)
	_label(
		content,
		"In Score Race, the round winner earns the highest hand score minus the lowest. A pass counts as zero, and a tie for highest awards no points. In Round-Win Race, each outright win counts once.",
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


func _build_scoring_page(key: String, title: String, intro: String) -> void:
	var page := VBoxContainer.new()
	_tabs.add_child(page)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, title)
	var toolbar := _panel(page, Color("304556"), 13)
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 9)
	toolbar.add_child(header)
	_label(header, intro, 20, BLUE)
	var filters := HFlowContainer.new()
	filters.add_theme_constant_override("h_separation", 16)
	filters.add_theme_constant_override("v_separation", 6)
	header.add_child(filters)
	var sort_label := _label(filters, "Sort by", 18, MUTED)
	sort_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	sort_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var sort := OptionButton.new()
	sort.name = "HandSort"
	sort.add_item("Priority", HandSort.PRIORITY)
	sort.add_item("Highest multiplier", HandSort.MULTIPLIER_HIGH)
	sort.add_item("Lowest multiplier", HandSort.MULTIPLIER_LOW)
	sort.custom_minimum_size.y = 38
	sort.add_theme_font_override("font", ThemeDB.fallback_font)
	sort.add_theme_font_size_override("font_size", 18)
	sort.get_popup().add_theme_font_override("font", ThemeDB.fallback_font)
	sort.get_popup().add_theme_font_size_override("font_size", 18)
	filters.add_child(sort)
	var group := CheckButton.new()
	group.name = "GroupHandTypes"
	group.text = "Group by hand type"
	group.custom_minimum_size.y = 38
	group.add_theme_font_override("font", ThemeDB.fallback_font)
	group.add_theme_font_size_override("font_size", 18)
	filters.add_child(group)
	var scroll := ScrollContainer.new()
	scroll.name = "ScoringScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	_rules_pages.append(scroll)
	var content := _scroll_content(scroll)
	var column_labels := HBoxContainer.new()
	column_labels.add_theme_constant_override("separation", 18)
	_panel(content, Color("304556"), 9).add_child(column_labels)
	var pattern := _label(column_labels, "Pattern and requirements", 18, MUTED)
	pattern.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_centered_label(column_labels, "Multiplier", 18, MUTED, 102)
	_centered_label(column_labels, "Priority", 18, MUTED, 82)
	var rows := VBoxContainer.new()
	rows.name = "HandRows"
	rows.add_theme_constant_override("separation", 7)
	content.add_child(rows)
	_hand_pages[key] = {"rows": rows, "sort": sort, "group": group, "entries": []}
	sort.item_selected.connect(func(_index: int): _fill_scoring_rows(key))
	group.toggled.connect(func(_pressed: bool): _fill_scoring_rows(key))


func _build_ability_tabs() -> void:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	_tabs.add_child(page)
	_tabs.set_tab_title(3, "Ability Cards")
	_ability_search = LineEdit.new()
	_ability_search.name = "AbilitySearch"
	_ability_search.placeholder_text = "Search ability names and card text"
	_ability_search.clear_button_enabled = true
	_ability_search.custom_minimum_size.y = 42
	_ability_search.add_theme_font_override("font", ThemeDB.fallback_font)
	_ability_search.add_theme_font_size_override("font_size", 20)
	for state in ["normal", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("152333")
		style.border_color = BLUE if state == "focus" else Color("344c5e")
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		style.content_margin_left = 12
		style.content_margin_right = 12
		_ability_search.add_theme_stylebox_override(state, style)
	_ability_search.text_changed.connect(_filter_abilities)
	page.add_child(_ability_search)
	_ability_tabs = TabContainer.new()
	_ability_tabs.name = "AbilityTabs"
	_ability_tabs.clip_tabs = true
	_ability_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_tabs(_ability_tabs, 20)
	page.add_child(_ability_tabs)
	for category: String in ABILITY_TABS:
		var content := _new_page(_ability_tabs, category)
		_ability_grids.append(_ability_grid(content, _ability_pages.back()))
	_search_scroll = ScrollContainer.new()
	_search_scroll.name = "AbilitySearchResults"
	_search_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_search_scroll.hide()
	page.add_child(_search_scroll)
	_search_grid = _ability_grid(_scroll_content(_search_scroll), _search_scroll)


func _ability_grid(content: VBoxContainer, scroll: ScrollContainer) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", CARD_GRID_GAP)
	grid.add_theme_constant_override("v_separation", CARD_GRID_GAP)
	content.add_child(grid)
	scroll.resized.connect(_fit_ability_grid.bind(scroll, grid))
	scroll.visibility_changed.connect(_fit_ability_grid.bind(scroll, grid))
	return grid


func _fit_ability_grid(scroll: ScrollContainer, grid: GridContainer) -> void:
	var usable := scroll.size.x - PAGE_SIDE_INSETS - scroll.get_v_scroll_bar().get_combined_minimum_size().x
	grid.columns = 2 if usable >= 2 * CARD_COLUMN_WIDTH + CARD_GRID_GAP else 1


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
	tabs.add_child(scroll)
	tabs.set_tab_title(tabs.get_tab_count() - 1, title)
	if tabs == _tabs:
		_rules_pages.append(scroll)
	else:
		_ability_pages.append(scroll)
	return _scroll_content(scroll)


func _scroll_content(scroll: ScrollContainer) -> VBoxContainer:
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
	for key: String in _hand_pages:
		_hand_pages[key].entries = scoring.get(key, [])
		_fill_scoring_rows(key)
	var abilities := _ability_catalog
	if abilities.is_empty():
		abilities = AbilityCatalog.public_catalog(AbilityCatalog.provisional_deck_recipe())
	_fill_ability_grids(abilities)


func _fill_scoring_rows(key: String) -> void:
	var page: Dictionary = _hand_pages[key]
	var rows: VBoxContainer = page.rows
	for child in rows.get_children():
		child.free()
	var entries: Array = page.entries.duplicate()
	if entries.is_empty():
		_label(rows, "No patterns are configured.", 21, MUTED)
		return
	entries.sort_custom(_hand_comes_first.bind(page.sort.get_selected_id()))
	var group_by_type: bool = page.group.button_pressed
	var sections := {}
	for entry: Dictionary in entries:
		var type := str(entry.get("broad_category_id", ""))
		var section: String = HAND_TYPES.get(type, "Other") if group_by_type else ""
		if not sections.has(section):
			sections[section] = []
		sections[section].append(entry)
	for section: String in sections:
		if not section.is_empty():
			var heading := _label(rows, section, 22, BLUE)
			heading.name = "HandTypeHeading"
		_add_hand_rows(rows, sections[section], key == "normal")


func _hand_comes_first(left: Dictionary, right: Dictionary, order: int) -> bool:
	if order != HandSort.PRIORITY:
		var lhs: Dictionary = left.get("multiplier", {})
		var rhs: Dictionary = right.get("multiplier", {})
		var left_value := int(lhs.get("numerator", 1)) * maxi(1, int(rhs.get("denominator", 1)))
		var right_value := int(rhs.get("numerator", 1)) * maxi(1, int(lhs.get("denominator", 1)))
		if left_value != right_value:
			return left_value > right_value if order == HandSort.MULTIPLIER_HIGH else left_value < right_value
	var left_priority := int(left.get("priority", 0))
	var right_priority := int(right.get("priority", 0))
	if left_priority != right_priority:
		return left_priority > right_priority
	return str(left.get("id", "")) < str(right.get("id", ""))


func _add_hand_rows(rows: VBoxContainer, entries: Array, show_example: bool) -> void:
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
		_scoring_text(detail, str(entry.get("rules_text", "")), MUTED)
		if show_example:
			var example := _shape_example(entry)
			if not example.is_empty():
				_scoring_text(detail, "Example  %s" % example, BLUE)
		_centered_label(row, _multiplier(entry.get("multiplier", {})), 22, GOLD, 102)
		_centered_label(row, str(entry.get("priority", "")), 20, MUTED, 82)


func _scoring_text(parent: Control, words: String, ink: Color) -> void:
	if not GameIcons.has_mentions(words):
		_label(parent, words, 18, ink)
		return
	var detail := GameIcons.label(ThemeDB.fallback_font, 18, ink)
	parent.add_child(detail)
	GameIcons.write(detail, words)


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
	_ability_index.clear()
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
			_add_ability_card(_ability_grids[timing], entry, str(id))
			var text := "%s %s" % [_display_name(entry, str(id)), str(entry.get("rules_text", ""))]
			_ability_index.append({"id": str(id), "entry": entry, "text": text.to_lower()})
	for grid in _ability_grids:
		if grid.get_child_count() == 0:
			_label(grid, "No abilities are configured in this category.", 21, MUTED)
	_filter_abilities(_ability_search.text)


func _filter_abilities(query: String) -> void:
	var terms := query.to_lower().split(" ", false)
	_ability_tabs.visible = terms.is_empty()
	_search_scroll.visible = not terms.is_empty()
	for child in _search_grid.get_children():
		child.free()
	if terms.is_empty():
		return
	for item in _ability_index:
		var indexed_text: String = item.text
		if Array(terms).all(func(term: String) -> bool: return term in indexed_text):
			_add_ability_card(_search_grid, item.entry, item.id)
	if _search_grid.get_child_count() == 0:
		_label(_search_grid, "No abilities match your search.", 21, MUTED)
	_search_scroll.scroll_vertical = 0


func _add_ability_card(grid: GridContainer, entry: Dictionary, id: String) -> void:
	var card = AbilityCard.instantiate()
	grid.add_child(card, true)
	card.render(entry, id, true)


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
