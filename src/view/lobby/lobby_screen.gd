class_name LobbyScreen
extends Control

signal setting_change_requested(key: StringName, value: Variant)
signal add_bot_requested
signal remove_bot_requested(bot_id: StringName)
signal bot_difficulty_requested(bot_id: StringName, difficulty: int)
signal bot_avatar_requested(bot_id: StringName, avatar: String)
signal practice_avatar_requested(avatar: String)
signal ready_requested(ready: bool)
signal start_requested
signal leave_requested
signal retry_requested

const MatchButtonArt := preload("res://src/view/match/match_button_art.gd")
const AvatarCatalog := preload("res://src/view/common/avatar_catalog.gd")
const BOT_DIFFICULTIES := ["Easy", "Standard", "Hard"]

var _model: Dictionary = {}
var _rendering := false
var _action_pending := false
var _settings_open := false

@onready var _room_code: Label = $Layout/Header/RoomCode
@onready var _copy_code: Button = $Layout/Header/CopyCode
@onready var _counts: Label = $Layout/Body/Roster/Counts
@onready var _add_bot: Button = $Layout/Body/Roster/Header/AddBotButton
@onready var _players: VBoxContainer = $Layout/Body/Roster/Scroll/Players
@onready var _victory_mode: OptionButton = $Layout/Body/Settings/VictoryMode
@onready var _victory_target: SpinBox = $Layout/Body/Settings/VictoryTarget
@onready var _visibility: OptionButton = $Layout/Body/Settings/Visibility
@onready var _no_time_limit: CheckButton = $Layout/Body/Settings/NoTimeLimit
@onready var _start_timer: SpinBox = $Layout/Body/Settings/StartTimer
@onready var _main_timer: SpinBox = $Layout/Body/Settings/MainTimer
@onready var _hand_timer: SpinBox = $Layout/Body/Settings/HandTimer
@onready var _end_timer: SpinBox = $Layout/Body/Settings/EndTimer
@onready var _reaction_timer: SpinBox = $Layout/Body/Settings/ReactionTimer
@onready var _hard_limit_timer: SpinBox = $Layout/Body/Settings/HardLimitTimer
@onready var _reconnect_timer: SpinBox = $Layout/Body/Settings/ReconnectTimer
@onready var _status: Label = $Layout/StatusPanel/Status
@onready var _retry: Button = $Layout/StatusPanel/RetryButton
@onready var _details: RichTextLabel = $Layout/StatusPanel/ConnectionDetails
@onready var _ready_button: CheckButton = $Layout/Footer/ReadyButton
@onready var _start_button: Button = $Layout/Footer/StartButton
@onready var _settings_button: Button = $Layout/Footer/SettingsButton
@onready var _ability_editor: Control = $Layout/Body/Settings/AbilityDeckEditor


func _ready() -> void:
	for button: Button in [
		_copy_code, _add_bot, _victory_mode, _visibility, _no_time_limit, _retry,
		$Layout/StatusPanel/DetailsButton, $Layout/Footer/LeaveButton, _settings_button, _start_button,
	]:
		MatchButtonArt.skin(button, MatchButtonArt.ACTION)
	if _victory_mode.item_count == 0:
		_victory_mode.add_item("Score race", 0)
		_victory_mode.add_item("Round-win race", 1)
	if _visibility.item_count == 0:
		_visibility.add_item("Public replacement requests", 0)
		_visibility.add_item("Private replacement requests", 1)
	for field in $Layout/Body/Settings.get_children():
		if field is Label and field.name != &"Heading":
			field.add_theme_font_size_override("font_size", 22)
		elif field is OptionButton:
			field.add_theme_font_size_override("font_size", 22)
		elif field is SpinBox:
			field.custom_minimum_size.y = 38
			field.get_line_edit().add_theme_font_size_override("font_size", 22)
	_details.visible = false
	_retry.visible = false
	_copy_code.pressed.connect(_copy_room_code)
	_settings_button.pressed.connect(_toggle_settings)
	_ability_editor.recipe_changed.connect(func(recipe: Dictionary):
		if not _rendering and _can_edit_settings():
			setting_change_requested.emit(&"ability_deck_recipe", recipe)
	)
	_update_page()


func render(model: Dictionary) -> void:
	_model = model.duplicate(true)
	_rendering = true
	_action_pending = false
	var is_host := bool(_model.get("is_host", false))
	var is_practice := bool(_model.get("is_practice", false))
	var started := bool(_model.get("match_started", false))
	var active_count := int(_model.get("active_player_count", 0))
	var spectator_count := int(_model.get("spectator_count", 0))
	_room_code.text = "ROOM  %s" % String(_model.get("room_code", "------"))
	_copy_code.disabled = str(_model.get("room_code", "")).length() != 6
	_counts.text = "%d / 4 players" % active_count
	if not is_practice:
		_counts.text += "   •   %d / 4 spectators" % spectator_count
	_add_bot.disabled = not bool(_model.get("can_add_bot", false))
	_add_bot.tooltip_text = (
		"The player seats are full" if _add_bot.disabled else "Add a computer-controlled opponent"
	)
	_render_players(_model.get("players", []))
	var settings: Dictionary = _model.get("settings", {})
	var victory_mode := int(settings.get("victory_mode", GameTypes.VictoryMode.SCORE_RACE))
	_victory_mode.select(victory_mode)
	_victory_target.value = int(settings.get("victory_target", GameTypes.default_victory_target(victory_mode)))
	$Layout/Body/Settings/VictoryTargetLabel.text = (
		"Round wins needed" if victory_mode == GameTypes.VictoryMode.ROUND_WIN_RACE else "Points to win"
	)
	_visibility.select(int(settings.get("information_visibility", 0)))
	var untimed := bool(settings.get("no_time_limit", false))
	_no_time_limit.set_pressed_no_signal(untimed)
	_start_timer.value = int(settings.get("start_timer_msec", 5000)) / 1000.0
	_main_timer.value = int(settings.get("main_timer_msec", 5000)) / 1000.0
	_hand_timer.value = int(settings.get("hand_timer_msec", 15000)) / 1000.0
	_end_timer.value = int(settings.get("end_timer_msec", 3000)) / 1000.0
	_reaction_timer.value = int(settings.get("reaction_window_msec", 2000)) / 1000.0
	_hard_limit_timer.value = int(settings.get("public_hard_limit_msec", 30000)) / 1000.0
	_reconnect_timer.value = int(settings.get("reconnect_grace_msec", 30000)) / 1000.0
	var editable := _can_edit_settings()
	_victory_mode.disabled = not editable
	_victory_target.editable = editable
	_visibility.disabled = not editable
	_no_time_limit.disabled = not editable
	for timer in [_start_timer, _main_timer, _hand_timer, _end_timer, _hard_limit_timer]:
		timer.editable = editable and not untimed
	_reaction_timer.editable = editable
	_reconnect_timer.editable = editable
	_start_button.disabled = not _can_start_match()
	_ready_button.disabled = started or active_count < 2
	_ability_editor.render(_model.get("ability_catalog", {}), editable)
	var local_id := str(_model.get("private_player_id", ""))
	for player in _model.get("players", []):
		if str(player.get("player_id", "")) == local_id and not local_id.is_empty():
			_ready_button.set_pressed_no_signal(bool(player.get("ready", false)))
			break
	var connection: Dictionary = _model.get("connection", _model.get("connection_state", {}))
	if connection.get("status", "connected") == "connected":
		_status.text = "Waiting for another player to join." if active_count < 2 else ""
		if is_practice and active_count < 2:
			_status.text = "Add a bot to start a practice match."
		if is_host and active_count >= 2 and not started:
			var waiting := int(_model.get("lobby_unready_guests", active_count - 1))
			if waiting > 0:
				_status.text = "Waiting for %d %s to ready up." % [
					waiting, "player" if waiting == 1 else "players",
				]
		_status.modulate = Color("a7d8c4")
		_retry.visible = false
	_update_page()
	_rendering = false


func show_error(reason: StringName) -> void:
	var messages := {
		&"active_seats_full": "The player seats are full. Join as a spectator or try another room.",
		&"spectator_slots_full": "The spectator section is full. Try another room.",
		&"room_not_found": "That room could not be found. Check the code and try again.",
		&"direct_connection_failed": "The direct and relay routes could not connect. Try again or return to the menu.",
		&"relay_unavailable": "A direct route could not connect, and relay fallback was unavailable. Try again or return to the menu.",
		&"signaling_timeout": "The room service did not respond. Try again.",
		&"host_closed": "The host closed this room. Return to the menu.",
		&"not_enough_players": "At least two connected players are required to start.",
		&"players_not_ready": "Wait for all players to ready up before starting.",
		&"ready_update_failed": "Your Ready status could not be updated. Try again.",
		&"invalid_ability_deck_recipe": "That ability deck recipe could not be applied.",
		&"config_locked": "The match has started. Player slots and settings are locked.",
		&"host_only": "Only the host can edit player slots and settings.",
		&"invalid_bot_difficulty": "Choose Easy, Standard, or Hard for this bot.",
		&"practice_only": "This avatar picker is available in Practice.",
		&"invalid_avatar": "Choose an avatar from the list.",
		&"avatar_in_use": "That avatar is already in use at this table.",
		&"unknown_bot": "That bot is no longer in the lobby.",
		&"lobby_unavailable": "The lobby is unavailable. Return to the menu and try again.",
	}
	_status.text = messages.get(reason, "The room could not continue. Try again.")
	if reason == &"active_seats_full" and _can_edit_settings():
		_status.text = "The player seats are full."
	_status.modulate = Color("ff9a9a")
	_retry.visible = reason in [
		&"direct_connection_failed", &"relay_unavailable",
		&"signaling_timeout", &"room_not_found",
	]
	_action_pending = false
	_start_button.disabled = not _can_start_match() or reason == &"players_not_ready"


func trigger_ready_shortcut() -> bool:
	if _rendering or not _ready_button.is_visible_in_tree() or _ready_button.disabled:
		return false
	_ready_button.button_pressed = not _ready_button.button_pressed
	return true


func _render_players(player_models: Array) -> void:
	for child in _players.get_children():
		_players.remove_child(child)
		child.queue_free()
	for player in player_models:
		if not player is Dictionary:
			continue
		var surface := PanelContainer.new()
		surface.add_theme_stylebox_override("panel", preload("res://themes/shift_panel.tres"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var portrait := TextureRect.new()
		portrait.name = "Avatar"
		portrait.texture = AvatarCatalog.front_texture(str(player.get("avatar_id",
			AvatarCatalog.default_avatar_id(int(player.get("seat_index", 0))))))
		portrait.custom_minimum_size = Vector2(72, 72)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_label := Label.new()
		name_label.name = "PlayerName"
		name_label.text = str(player.get("name", "Player"))
		name_label.tooltip_text = name_label.text
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.add_theme_font_size_override("font_size", 28)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 18)
		margin.add_theme_constant_override("margin_right", 18)
		row.add_child(portrait)
		row.add_child(name_label)
		if player.get("is_bot", false):
			_render_bot_controls(row, player)
		else:
			_render_human_controls(row, player)
		margin.add_child(row)
		surface.add_child(margin)
		_players.add_child(surface)


func _render_human_controls(row: HBoxContainer, player: Dictionary) -> void:
	var status := Label.new()
	status.text = "Ready" if player.get("ready", false) else "Waiting"
	if str(player.get("role", "active")) == "spectator":
		status.text = "Spectator"
	elif player.get("is_host", false):
		status.text = "Host"
	if not bool(player.get("connected", true)):
		status.text = "Connecting…"
	status.add_theme_font_size_override("font_size", 21)
	status.add_theme_color_override("font_color", Color("a7d8c4") if status.text == "Ready" else Color("adbac9"))
	row.add_child(status)
	if not _can_edit_settings() or not bool(_model.get("is_practice", false)):
		return
	if str(player.get("player_id", "")) != str(_model.get("private_player_id", "")):
		return
	var picker := _avatar_picker("PlayerAvatar", "Choose your Practice portrait", player, GameTypes.AVATAR_IDS)
	picker.get_popup().id_pressed.connect(func(index: int):
		if _can_request_roster_change():
			practice_avatar_requested.emit(GameTypes.AVATAR_IDS[index])
	)
	row.add_child(picker)


func _render_bot_controls(row: HBoxContainer, player: Dictionary) -> void:
	var difficulty := clampi(int(player.get("bot_difficulty", 1)), 0, BOT_DIFFICULTIES.size() - 1)
	var editable := _can_edit_settings()
	var status := Label.new()
	status.name = "BotStatus"
	status.text = "Bot" if editable else "Bot · %s" % BOT_DIFFICULTIES[difficulty]
	status.add_theme_font_size_override("font_size", 21)
	status.add_theme_color_override("font_color", Color("adbac9"))
	row.add_child(status)
	if not editable:
		return
	var bot_id := StringName(player.get("player_id", ""))
	var options := OptionButton.new()
	options.name = "BotDifficulty"
	options.tooltip_text = "Difficulty for %s" % str(player.get("name", "this bot"))
	options.custom_minimum_size.y = 40
	options.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	options.add_theme_font_size_override("font_size", 21)
	for label: String in BOT_DIFFICULTIES:
		options.add_item(label)
	options.select(difficulty)
	options.item_selected.connect(func(level: int):
		if _can_request_roster_change():
			bot_difficulty_requested.emit(bot_id, level)
	)
	MatchButtonArt.skin(options, MatchButtonArt.ACTION)
	row.add_child(options)
	var available: Array = player.get("bot_available_avatars", GameTypes.AVATAR_IDS)
	var picker := _avatar_picker("BotAvatar", "Choose a portrait for this bot", player, available)
	picker.get_popup().id_pressed.connect(func(index: int):
		if _can_request_roster_change():
			bot_avatar_requested.emit(bot_id, GameTypes.AVATAR_IDS[index])
	)
	row.add_child(picker)
	var remove := Button.new()
	remove.name = "RemoveBotButton"
	remove.text = "Remove"
	remove.tooltip_text = "Remove %s" % str(player.get("name", "this bot"))
	remove.custom_minimum_size.y = 40
	remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	remove.add_theme_font_size_override("font_size", 21)
	remove.pressed.connect(func():
		if _can_request_roster_change():
			remove_bot_requested.emit(bot_id)
	)
	MatchButtonArt.skin(remove, MatchButtonArt.ACTION)
	row.add_child(remove)


func _avatar_picker(node_name: String, help_text: String, player: Dictionary, available: Array) -> MenuButton:
	var picker := MenuButton.new()
	picker.name = node_name
	picker.text = "Avatar"
	picker.tooltip_text = help_text
	picker.custom_minimum_size.y = 40
	picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picker.add_theme_font_size_override("font_size", 21)
	MatchButtonArt.skin(picker, MatchButtonArt.ACTION)
	var avatars := picker.get_popup()
	avatars.add_theme_constant_override("icon_max_width", 32)
	var selected := GameTypes.canonical_avatar_id(str(player.get("avatar_id", "")))
	for index in GameTypes.AVATAR_IDS.size():
		var avatar: String = GameTypes.AVATAR_IDS[index]
		avatars.add_radio_check_item(AvatarCatalog.display_name(avatar), index)
		avatars.set_item_icon(index, AvatarCatalog.front_texture(avatar))
		avatars.set_item_checked(index, avatar == selected)
		avatars.set_item_disabled(index, avatar not in available)
	return picker


func _can_edit_settings() -> bool:
	return bool(_model.get("is_host", false)) and not bool(_model.get("match_started", false))


func _can_request_roster_change() -> bool:
	return not _rendering and not _settings_open and _can_edit_settings()


func _on_add_bot_pressed() -> void:
	if _can_request_roster_change() and not _add_bot.disabled:
		add_bot_requested.emit()


func _can_start_match() -> bool:
	return (
		_can_edit_settings() and int(_model.get("active_player_count", 0)) >= 2
		and int(_model.get("lobby_unready_guests", 1)) == 0
	)


func _toggle_settings() -> void:
	_settings_open = not _settings_open
	_update_page()


func _update_page() -> void:
	var is_host := bool(_model.get("is_host", false))
	var is_practice := bool(_model.get("is_practice", false))
	var settings_title := "Practice Settings" if is_practice else "Lobby Settings"
	var roster_title := "Practice" if is_practice else "Table Lobby"
	$Layout/Body/Roster.visible = not _settings_open
	$Layout/Body/Settings.visible = _settings_open
	$Layout/Header/Title.text = settings_title if _settings_open else roster_title
	_room_code.visible = not is_practice
	_copy_code.visible = not is_practice
	$Layout/Body/Settings/ReconnectTimerLabel.visible = not is_practice
	_reconnect_timer.visible = not is_practice
	$Layout/Body/Settings/Heading.text = "Match rules" if _can_edit_settings() else "Match rules · view only"
	$Layout/Footer/LeaveButton.text = "Leave Practice" if is_practice else "Leave Lobby"
	_settings_button.text = ("Back to Practice" if is_practice else "Back to Lobby") if _settings_open else settings_title
	_add_bot.visible = not _settings_open and _can_edit_settings()
	_ready_button.visible = not _settings_open and not is_host and str(_model.get("local_role", "active")) == "active"
	_start_button.visible = not _settings_open and is_host


func _copy_room_code() -> void:
	var code := str(_model.get("room_code", ""))
	if code.length() == 6:
		DisplayServer.clipboard_set(code)
		_status.text = "Room code copied."
		_status.modulate = Color("a7d8c4")


func _on_setting_changed(value: Variant, key: StringName, scale_msec: bool = false) -> void:
	if _rendering or not _can_edit_settings():
		return
	var emitted_value: Variant = roundi(float(value) * 1000.0) if scale_msec else int(value)
	setting_change_requested.emit(key, emitted_value)


func _on_victory_mode_selected(index: int) -> void:
	_on_setting_changed(index, &"victory_mode")


func _on_victory_target_changed(value: float) -> void:
	_on_setting_changed(value, &"victory_target")


func _on_visibility_selected(index: int) -> void:
	_on_setting_changed(index, &"information_visibility")


func _on_no_time_limit_toggled(enabled: bool) -> void:
	if not _rendering and _can_edit_settings():
		setting_change_requested.emit(&"no_time_limit", enabled)


func _on_start_timer_changed(value: float) -> void:
	_on_setting_changed(value, &"start_timer_msec", true)


func _on_main_timer_changed(value: float) -> void:
	_on_setting_changed(value, &"main_timer_msec", true)


func _on_hand_timer_changed(value: float) -> void:
	_on_setting_changed(value, &"hand_timer_msec", true)


func _on_end_timer_changed(value: float) -> void:
	_on_setting_changed(value, &"end_timer_msec", true)


func _on_reaction_timer_changed(value: float) -> void:
	_on_setting_changed(value, &"reaction_window_msec", true)


func _on_hard_limit_timer_changed(value: float) -> void:
	_on_setting_changed(value, &"public_hard_limit_msec", true)


func _on_reconnect_timer_changed(value: float) -> void:
	_on_setting_changed(value, &"reconnect_grace_msec", true)


func _on_ready_toggled(ready: bool) -> void:
	if _rendering or _ready_button.disabled or not _ready_button.visible:
		return
	ready_requested.emit(ready)


func _on_start_pressed() -> void:
	if _action_pending or not _can_start_match() or _start_button.disabled:
		return
	_action_pending = true
	_start_button.disabled = true
	start_requested.emit()


func _on_details_pressed() -> void:
	_details.visible = not _details.visible


func _on_retry_pressed() -> void:
	if _action_pending:
		return
	_action_pending = true
	retry_requested.emit()


func _on_leave_pressed() -> void:
	leave_requested.emit()
