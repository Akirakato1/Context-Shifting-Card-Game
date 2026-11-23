extends VBoxContainer

signal details_requested(title: String, description: String)

const GameTypes := preload("res://src/core/common/game_types.gd")
const Rational := preload("res://src/core/common/rational.gd")
const CONTEXT_ICONS := [
	preload("res://assets/artwork/context_emblems/context_emblem_rish.png"),
	preload("res://assets/artwork/context_emblems/context_emblem_flourish.png"),
	preload("res://assets/artwork/context_emblems/context_emblem_fall.png"),
]
const SUIT_ART := [
	preload("res://assets/artwork/card_suit_mountain.png"),
	preload("res://assets/artwork/card_suit_cloud.png"),
	preload("res://assets/artwork/card_suit_sea.png"),
]
const SUIT_CROPS := [
	Rect2(132, 219, 1737, 1365),
	Rect2(106, 262, 1885, 1141),
	Rect2(241, 295, 1707, 1429),
]
const SUIT_INK := preload("res://src/view/match/rank_ink.tres")
const POSITIVE := Color("a7e9b8")
const NEGATIVE := Color("ffaaa9")
const NEUTRAL := Color("dbeaf9")
const DURATION_COLOR := Color("b8c6d6")
const CONTEXT_COLORS := [Color("a0d8fb"), Color("bbeba8"), Color("ffc2a1")]
const CONTEXT_HAND_LABELS := {
	"single_context": "1 Context", "two_context": "2 Contexts", "three_context": "3 Contexts",
}

var _suit_icons: Array[AtlasTexture] = []
var _displayed: Array[Dictionary] = []

@onready var _rows: HFlowContainer = $FieldScroll/FieldRows


func _ready() -> void:
	for index in SUIT_ART.size():
		var icon := AtlasTexture.new()
		icon.atlas = SUIT_ART[index]
		icon.region = SUIT_CROPS[index]
		icon.filter_clip = true
		_suit_icons.append(icon)


func render(model: Dictionary, font: Font) -> void:
	var players := {}
	for player: Dictionary in model.get("players", []):
		var id := str(player.get("player_id", ""))
		players[id] = str(player.get("name", id))
	var catalog: Dictionary = model.get("ability_catalog", {})
	var badges: Array[Dictionary] = []
	for field: Dictionary in model.get("active_fields", []):
		var id := str(field.get("ability_id", ""))
		badges.append(_field_badge(field, catalog.get(id, {}), players, model))
	for modifier: Dictionary in model.get("active_score_modifiers", []):
		var id := str(modifier.get("source_definition_id", ""))
		badges.append(_modifier_badge(modifier, catalog.get(id, {}), players, model))
	if badges == _displayed:
		return
	_displayed = badges
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for badge in badges:
		_add_badge(badge, font)
	visible = not badges.is_empty()


func _field_badge(
	field: Dictionary, definition: Dictionary, players: Dictionary, model: Dictionary
) -> Dictionary:
	var id := str(field.get("ability_id", ""))
	var name := str(definition.get("display_name", id.capitalize()))
	var persistent := bool(field.get("persistent", false))
	var rounds := int(field.get("remaining_rounds", 0))
	var duration := "∞" if persistent else "◷%d" % rounds
	var duration_description := "Persistent" if persistent else "%d %s remaining" % [
		rounds, "round" if rounds == 1 else "rounds",
	]
	var source := str(players.get(str(field.get("source_player_id", "")), ""))
	if not source.is_empty():
		duration_description += " · Played by %s" % source
	var badge := {"text": name, "title": name, "duration": duration, "color": NEUTRAL}
	var description := name
	var direction := -1 if int(model.get("context_direction", 1)) < 0 else 1
	if id == "reverse_cycle":
		badge["text"] = "↺" if direction < 0 else "↻"
		var next := GameTypes.context_name(posmod(int(model.get("active_context", 0)) + direction, 3))
		description = "The clock runs %s. Next context: %s." % [
			"counterclockwise" if direction < 0 else "clockwise", next,
		]
	else:
		description = _apply_field_symbols(badge, field.get("effect_parameters", {}))
	var rules := str(definition.get("rules_text", ""))
	if not rules.is_empty():
		description = "%s\n%s" % [description, rules] if id == "reverse_cycle" else rules
	badge["description"] = "%s\n%s" % [description, duration_description]
	return badge


func _apply_field_symbols(badge: Dictionary, params: Dictionary) -> String:
	var context := int(params.get("context", -1))
	var context_name := GameTypes.context_name(context)
	var suit := int(params.get("suit", -1))
	var sign_value := _signed_delta(params)
	var rule := str(params.get("field_rule", ""))
	match rule:
		"additional_context":
			if context in [0, 1, 2]:
				badge["icon"] = CONTEXT_ICONS[context]
				badge["color"] = CONTEXT_COLORS[context]
			badge["text"] = "+"
			badge["icon_after"] = true
			return "%s is also active this round." % context_name
		"per_selected_suit":
			if suit in [0, 1, 2]:
				badge["icon"] = _suit_icons[suit]
				badge["icon_material"] = SUIT_INK
			badge["color"] = _delta_color(sign_value)
			badge["text"] = "%s /" % sign_value
			badge["icon_after"] = true
			return "%s Field per %s scoring half." % [sign_value, GameTypes.suit_name(suit)]
		"per_selected_rank_set":
			var ranks: Array = params.get("ranks", [])
			badge["color"] = _delta_color(sign_value)
			badge["text"] = "%s / %s" % [sign_value, "·".join(ranks.map(func(rank): return str(rank)))]
			return "%s Field per non-Joker scoring half with rank %s." % [
				sign_value, "/".join(ranks.map(func(rank): return str(rank))),
			]
		"leading_context", "strict_context_majority":
			if context in [0, 1, 2]:
				badge["icon"] = CONTEXT_ICONS[context]
			badge["color"] = _delta_color(sign_value)
			var strict := rule == "strict_context_majority"
			badge["text"] = "%s %s" % [">" if strict else "≥", sign_value]
			var condition := "has strictly the most halves" if strict else "leads or ties for most halves"
			return "%s Field when %s %s in the submitted hand." % [sign_value, context_name, condition]
	return str(badge["title"])


func _modifier_badge(
	modifier: Dictionary, definition: Dictionary, players: Dictionary, model: Dictionary
) -> Dictionary:
	var id := str(modifier.get("source_definition_id", ""))
	var target_id := str(modifier.get("target_player_id", ""))
	var target := str(players.get(target_id, target_id))
	var short_target := "You" if target_id == str(model.get("private_player_id", "")) else target
	var category := str(modifier.get("category_id", ""))
	var category_label: String = CONTEXT_HAND_LABELS.get(category, category.capitalize())
	var factors := {"card_hand": "Hand", "context_hand": "Context", "field": "Field"}
	var factor: String = factors.get(str(modifier.get("factor_id", "")), "")
	var delta := _signed_delta(modifier.get("delta", {}))
	var rule := str(definition.get("rules_text", "%s %s if %s applies." % [delta, factor, category_label]))
	return {
		"text": "%s  %s · %s" % [delta, category_label, short_target],
		"title": str(definition.get("display_name", id.capitalize())),
		"duration": "◷1", "color": _delta_color(delta),
		"description": "%s\nTarget: %s · This round" % [rule, target],
	}


func _signed_delta(parameters: Dictionary) -> String:
	var delta := Rational.new(int(parameters.get("numerator", 0)), int(parameters.get("denominator", 1)))
	var value := str(delta.numerator)
	if delta.denominator > 1:
		value = "%d/%d" % [delta.numerator, delta.denominator]
		if 1000 % delta.denominator == 0:
			value = ("%.3f" % (float(delta.numerator) / delta.denominator)).rstrip("0").rstrip(".")
	return "+" + value if delta.numerator > 0 else value


func _delta_color(value: String) -> Color:
	if value.begins_with("-"):
		return NEGATIVE
	return POSITIVE if value.begins_with("+") else NEUTRAL


func _add_badge(badge: Dictionary, font: Font) -> void:
	var button := Button.new()
	button.flat = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = "%s\n%s" % [badge.title, badge.description]
	_rows.add_child(button)
	var row := HBoxContainer.new()
	row.name = "Display"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 7.0
	row.offset_right = -7.0
	var effect := _add_label(row, "Effect", badge.text, badge.color, font, 19)
	var texture: Texture2D = badge.get("icon")
	if texture != null:
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.custom_minimum_size = Vector2(24, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = texture
		icon.material = badge.get("icon_material")
		row.add_child(icon)
		if not bool(badge.get("icon_after", false)):
			row.move_child(icon, effect.get_index())
	_add_label(row, "Duration", badge.duration, DURATION_COLOR, font, 15)
	button.custom_minimum_size = Vector2(row.get_combined_minimum_size().x + 16.0, 27.0)
	button.pressed.connect(func(): details_requested.emit(badge.title, badge.description))


func _add_label(
	row: HBoxContainer, node_name: String, content: String, color: Color, font: Font, font_size: int
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = content
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("23303d"))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", font_size)
	if font != null:
		label.add_theme_font_override("font", font)
	row.add_child(label)
	return label
