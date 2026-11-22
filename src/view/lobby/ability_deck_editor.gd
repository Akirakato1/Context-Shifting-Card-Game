extends VBoxContainer

signal recipe_changed(recipe: Dictionary)

const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")

const CATEGORIES := {
	AbilityDefinition.Timing.HAND_MANIPULATION: "Manipulation",
	AbilityDefinition.Timing.HAND_SHAPE: "Buffs and Nerfs",
	AbilityDefinition.Timing.SABOTAGE: "Sabotage",
	AbilityDefinition.Timing.FIELD: "Field",
}

var _catalog: Dictionary = {}
var _inputs: Dictionary = {}
var _editable := false

@onready var _open: Button = $Open
@onready var _dialog: ConfirmationDialog = $DeckDialog
@onready var _tabs: TabContainer = $DeckDialog/Content/DeckTabs
@onready var _total: Label = $DeckDialog/Content/Footer/Total
@onready var _restore: Button = $DeckDialog/Content/Footer/RestoreDefaults


func _ready() -> void:
	_open.pressed.connect(_open_editor)
	_restore.pressed.connect(_restore_defaults)
	_dialog.confirmed.connect(_confirm_recipe)
	render(_catalog, _editable)


func render(catalog: Dictionary, editable: bool) -> void:
	_catalog = catalog if not catalog.is_empty() else AbilityCatalog.public_catalog(
		AbilityCatalog.provisional_deck_recipe()
	)
	var permission_changed := _editable != editable
	_editable = editable
	if not is_node_ready():
		return
	var cards := 0
	for entry: Dictionary in _catalog.values():
		cards += int(entry.get("copies", 0))
	_open.text = "Ability Deck  ·  %d cards" % cards
	if _dialog.visible and (permission_changed or not _editable):
		_render_editor()


func _open_editor() -> void:
	_render_editor()
	_dialog.popup_centered_clamped(Vector2i(700, 530), 0.9)


func _render_editor() -> void:
	_inputs.clear()
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	for timing in CATEGORIES:
		var abilities: Array = _catalog.values().filter(func(entry: Dictionary) -> bool:
			return int(entry.get("timing", -1)) == timing
		)
		if abilities.is_empty():
			continue
		abilities.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return str(left.get("label", "")).naturalnocasecmp_to(str(right.get("label", ""))) < 0
		)
		_add_category(CATEGORIES[timing], abilities)
	_dialog.ok_button_text = "Apply" if _editable else "Close"
	_dialog.get_cancel_button().visible = _editable
	_restore.visible = _editable
	_update_total()


func _add_category(category: String, abilities: Array) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = category
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var rows := GridContainer.new()
	rows.columns = 2
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("h_separation", 18)
	rows.add_theme_constant_override("v_separation", 6)
	scroll.add_child(rows)
	var name_heading := Label.new()
	name_heading.text = "Ability"
	rows.add_child(name_heading)
	var count_heading := Label.new()
	count_heading.text = "Copies"
	rows.add_child(count_heading)
	for entry: Dictionary in abilities:
		var id := str(entry.get("id", ""))
		var label := Label.new()
		label.text = str(entry.get("display_name", entry.get("label", id)))
		label.tooltip_text = str(entry.get("rules_text", ""))
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_child(label)
		var copies := SpinBox.new()
		copies.name = id
		copies.custom_minimum_size.x = 100
		copies.max_value = AbilityCatalog.MAX_RECIPE_COPIES_PER_ABILITY
		copies.value = int(entry.get("copies", 0))
		copies.editable = _editable
		copies.value_changed.connect(func(_value: float): _update_total())
		rows.add_child(copies)
		_inputs[id] = copies


func _update_total() -> void:
	var count := 0
	for input: SpinBox in _inputs.values():
		count += int(input.value)
	var minimum := AbilityCatalog.MIN_LOBBY_DECK_SIZE
	var valid := count >= minimum
	_total.text = "%d cards" % count
	if _editable and not valid:
		_total.text += "  ·  At least %d required" % minimum
	_dialog.get_ok_button().disabled = _editable and not valid


func _restore_defaults() -> void:
	if not _editable:
		return
	var defaults := AbilityCatalog.provisional_deck_recipe()
	for id in _inputs:
		_inputs[id].set_value_no_signal(int(defaults.get(id, 0)))
	_update_total()


func _confirm_recipe() -> void:
	if not _editable or _dialog.get_ok_button().disabled:
		return
	var recipe := {}
	for id in _inputs:
		recipe[id] = int(_inputs[id].value)
	recipe_changed.emit(recipe)
