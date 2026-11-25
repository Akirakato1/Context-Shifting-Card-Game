class_name MainMenuScreen
extends Control

signal host_requested(player_name: String)
signal join_requested(player_name: String, room_code: String, role: String)
signal screen_requested(screen_id: StringName)
signal settings_requested
signal practice_requested
signal tutorial_requested

const MatchButtonArt := preload("res://src/view/match/match_button_art.gd")
const AvatarCatalog := preload("res://src/view/common/avatar_catalog.gd")
const GameTypes := preload("res://src/core/common/game_types.gd")
const SLIDE_HOLD_SECONDS := 7.0
const SLIDE_FADE_SECONDS := 1.6
const BACKGROUND_ART: Array[Texture2D] = [
	preload("res://assets/artwork/background/background_rise.png"),
	preload("res://assets/artwork/background/background_flourish.png"),
	preload("res://assets/artwork/background/background_fall.png"),
]

var _busy := false
var _avatar_id := ""
var _avatar_buttons: Dictionary[String, Button] = {}
var _slide_index := 0
var _slideshow: Tween

@onready var _current_slide: TextureRect = $Background/Current
@onready var _incoming_slide: TextureRect = $Background/Incoming
@onready var _title: Label = $Content/Title
@onready var _name_label: Label = $Content/PlayerNameLabel
@onready var _name_input: LineEdit = $Content/PlayerName
@onready var _avatar_picker: VBoxContainer = $Content/AvatarPicker
@onready var _host_button: Button = $Content/HostButton
@onready var _join_panel: PanelContainer = $Content/JoinPanel
@onready var _code_input: LineEdit = $Content/JoinPanel/JoinFields/Code
@onready var _role_input: OptionButton = $Content/JoinPanel/JoinFields/Role
@onready var _join_button: Button = $Content/JoinPanel/JoinFields/JoinButton
@onready var _status: Label = $Content/Status
@onready var _back: Button = $Content/BackButton


func _ready() -> void:
	item_rect_changed.connect(_layout_background)
	_layout_background()
	_start_slideshow()
	_build_avatar_picker()
	for button: Button in $Content.find_children("*", "Button", true, false):
		MatchButtonArt.skin(button, MatchButtonArt.ACTION)
	if _role_input.item_count == 0:
		_role_input.add_item("Active player", 0)
		_role_input.add_item("Spectator", 1)
	$Content/CreateLobbyButton.pressed.connect(func(): screen_requested.emit(&"create_lobby"))
	$Content/JoinLobbyButton.pressed.connect(func(): screen_requested.emit(&"join_lobby"))
	$Content/PracticeButton.pressed.connect(func(): practice_requested.emit())
	$Content/TutorialButton.pressed.connect(func(): tutorial_requested.emit())
	$Content/SettingsButton.pressed.connect(func(): settings_requested.emit())
	$Content/QuitButton.pressed.connect(func(): get_tree().quit())
	_back.pressed.connect(func(): screen_requested.emit(&"menu"))
	_name_input.text_submitted.connect(func(_text: String):
		if _host_button.visible and not _host_button.disabled:
			_on_host_pressed()
		elif _join_panel.visible:
			_code_input.grab_focus()
	)
	_code_input.text_submitted.connect(func(_text: String): _on_join_pressed())
	set_page(&"menu")


func _layout_background() -> void:
	var bounds := get_global_transform().affine_inverse() * get_viewport_rect()
	$Background.position = bounds.position
	$Background.size = bounds.size


func _start_slideshow() -> void:
	_current_slide.texture = BACKGROUND_ART[_slide_index]
	_slideshow = create_tween().set_loops()
	_slideshow.tween_interval(SLIDE_HOLD_SECONDS)
	_slideshow.tween_callback(func():
		_slide_index = (_slide_index + 1) % BACKGROUND_ART.size()
		_incoming_slide.texture = BACKGROUND_ART[_slide_index]
	)
	_slideshow.tween_property(_incoming_slide, "modulate:a", 1.0, SLIDE_FADE_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_slideshow.tween_callback(func():
		_current_slide.texture = _incoming_slide.texture
		_incoming_slide.modulate.a = 0.0
	)


func _build_avatar_picker() -> void:
	var choices := _avatar_picker.get_node("Choices")
	var group := ButtonGroup.new()
	for index in GameTypes.AVATAR_IDS.size():
		var id: String = GameTypes.AVATAR_IDS[index]
		var option := Button.new()
		option.name = id
		option.tooltip_text = "Avatar %d" % (index + 1)
		option.icon = AvatarCatalog.front_texture(id)
		option.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		option.expand_icon = true
		option.add_theme_constant_override("icon_max_width", 92)
		option.custom_minimum_size.y = 98
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.toggle_mode = true
		option.button_group = group
		option.pressed.connect(_select_avatar.bind(id))
		choices.add_child(option)
		_avatar_buttons[id] = option


func _select_avatar(id: String) -> void:
	_avatar_id = id if id in GameTypes.AVATAR_IDS else GameTypes.default_avatar_id(0)
	for option_id in _avatar_buttons:
		_avatar_buttons[option_id].set_pressed_no_signal(option_id == _avatar_id)


func set_page(page: StringName, name_prefill: String = "", avatar_prefill: String = "") -> void:
	var main := page == &"menu"
	$CreditsButton.visible = main
	$MenuSurface.visible = not main
	$Content/Logo.visible = main
	_title.visible = not main
	if page == &"create_lobby":
		_title.text = "Create Lobby"
	elif page == &"join_lobby":
		_title.text = "Join Lobby"
	for button in [
		$Content/CreateLobbyButton, $Content/JoinLobbyButton, $Content/PracticeButton,
		$Content/TutorialButton, $Content/SettingsButton, $Content/QuitButton,
	]:
		button.visible = main
	_name_label.visible = not main
	_name_input.visible = not main
	_avatar_picker.visible = not main
	_host_button.visible = page == &"create_lobby"
	_join_panel.visible = page == &"join_lobby"
	_back.visible = not main
	_status.visible = not main
	_status.text = ""
	_name_input.text = name_prefill
	_select_avatar(avatar_prefill)
	_update_buttons()
	if not main:
		_name_input.grab_focus()


func player_name() -> String:
	return _name_input.text.strip_edges()


func avatar_id() -> String:
	return _avatar_id


func _unhandled_input(event: InputEvent) -> void:
	if _back.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		screen_requested.emit(&"menu")


func set_busy(busy: bool, message: String = "") -> void:
	_busy = busy
	if not message.is_empty():
		_status.text = message
		_status.modulate = Color("b8c8da")
	_update_buttons()


func show_error(message: String) -> void:
	_busy = false
	_status.text = message
	_status.modulate = Color("ff9a9a")
	_update_buttons()


func clear_error() -> void:
	_status.text = ""
	_status.modulate = Color("b8c8da")


func _on_host_pressed() -> void:
	if _busy:
		return
	var player_name := _name_input.text.strip_edges()
	if player_name.is_empty():
		show_error("Enter a player name first.")
		return
	set_busy(true, "Creating room…")
	host_requested.emit(player_name)


func _on_join_pressed() -> void:
	if _busy:
		return
	var player_name := _name_input.text.strip_edges()
	var room_code := normalized_code()
	if player_name.is_empty() or room_code.length() != 6:
		show_error("Enter a player name and six-character room code.")
		return
	var role := "spectator" if _role_input.selected == 1 else "active"
	set_busy(true, "Joining room…")
	join_requested.emit(player_name, room_code, role)


func normalized_code() -> String:
	return _code_input.text.strip_edges().to_upper().replace("-", "").replace(" ", "")


func _on_input_changed(_value: String = "") -> void:
	if not _busy:
		clear_error()
	_update_buttons()


func _update_buttons() -> void:
	if not is_node_ready():
		return
	var has_name := not _name_input.text.strip_edges().is_empty()
	_name_input.editable = not _busy
	_code_input.editable = not _busy
	_role_input.disabled = _busy
	for option: Button in _avatar_buttons.values():
		option.disabled = _busy
	_host_button.disabled = _busy or not has_name
	_join_button.disabled = _busy or not has_name or normalized_code().length() != 6
