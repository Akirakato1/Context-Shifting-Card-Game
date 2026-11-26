extends VBoxContainer

signal player_selected(player_id: String)

const AvatarCatalog := preload("res://src/view/common/avatar_catalog.gd")
const MatchButtonArt := preload("res://src/view/match/match_button_art.gd")

var _title := Label.new()
var _buttons := HBoxContainer.new()
var _notice := PanelContainer.new()
var _roster: Array = []
var _introduced := false


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 5)
	_title.name = "Watching"
	_title.add_theme_font_override("font", ThemeDB.fallback_font)
	_title.add_theme_font_size_override("font_size", 17)
	_title.add_theme_constant_override("outline_size", 6)
	add_child(_title)
	_buttons.name = "Players"
	_buttons.mouse_filter = MOUSE_FILTER_IGNORE
	_buttons.add_theme_constant_override("separation", 5)
	add_child(_buttons)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("162330f2")
	background.border_color = Color("7895aa")
	background.set_border_width_all(1)
	background.set_corner_radius_all(5)
	background.content_margin_left = 10
	background.content_margin_right = 10
	background.content_margin_top = 6
	background.content_margin_bottom = 6
	_notice.add_theme_stylebox_override("panel", background)
	_notice.mouse_filter = MOUSE_FILTER_IGNORE
	_notice.size_flags_horizontal = SIZE_SHRINK_BEGIN
	var instructions := Label.new()
	instructions.text = "Click a portrait or choose a name to switch viewpoints."
	instructions.add_theme_font_override("font", ThemeDB.fallback_font)
	instructions.add_theme_font_size_override("font_size", 15)
	_notice.add_child(instructions)
	add_child(_notice)
	_notice.hide()
	hide()


func render(players: Array, watching_id: String, ability: String, targeting: bool) -> void:
	visible = not watching_id.is_empty()
	if not visible:
		return
	var roster := players.map(func(player: Dictionary) -> Array:
		var id := str(player.player_id)
		return [id, str(player.get("name", player.get("display_name", id))),
			str(player.get("avatar_id", AvatarCatalog.default_avatar_id(int(player.get("seat_index", 0)))))]
	)
	if roster != _roster:
		_roster = roster
		for child in _buttons.get_children():
			_buttons.remove_child(child)
			child.queue_free()
		for row: Array in _roster:
			var button := Button.new()
			button.text = row[1]
			button.icon = AvatarCatalog.front_texture(row[2])
			button.tooltip_text = "Watch %s" % row[1]
			button.custom_minimum_size = Vector2(112, 36)
			button.clip_text = true
			button.toggle_mode = true
			button.add_theme_constant_override("icon_max_width", 23)
			button.add_theme_font_override("font", ThemeDB.fallback_font)
			button.add_theme_font_size_override("font_size", 14)
			MatchButtonArt.skin(button, MatchButtonArt.MENU)
			button.pressed.connect(player_selected.emit.bind(row[0]))
			_buttons.add_child(button)
	for index in _roster.size():
		var selected: bool = _roster[index][0] == watching_id
		_buttons.get_child(index).set_pressed_no_signal(selected)
		if selected:
			_title.text = "Watching %s" % _roster[index][1]
	if not ability.is_empty():
		_title.text += "  ·  %s %s" % ["Playing" if targeting else "Primed", ability]
	if not _introduced:
		_introduced = true
		_notice.show()
		get_tree().create_timer(7.0).timeout.connect(_notice.hide)


func dismiss_notice() -> void:
	_notice.hide()
