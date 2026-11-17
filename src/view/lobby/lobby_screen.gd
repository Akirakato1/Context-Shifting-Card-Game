class_name LobbyScreen
extends Control

signal setting_change_requested(key: StringName, value: Variant)
signal ready_requested(ready: bool)
signal start_requested
signal leave_requested
signal retry_requested

var _model: Dictionary = {}
var _rendering := false
var _action_pending := false

@onready var _room_code: Label = $Layout/Header/RoomCode
@onready var _counts: Label = $Layout/Body/Roster/Counts
@onready var _players: VBoxContainer = $Layout/Body/Roster/Players
@onready var _victory_mode: OptionButton = $Layout/Body/Settings/VictoryMode
@onready var _victory_target: SpinBox = $Layout/Body/Settings/VictoryTarget
@onready var _visibility: OptionButton = $Layout/Body/Settings/Visibility
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


func _ready() -> void:
	if _victory_mode.item_count == 0:
		_victory_mode.add_item("Score race", 0)
		_victory_mode.add_item("Round-win race", 1)
	if _visibility.item_count == 0:
		_visibility.add_item("Public replacement requests", 0)
		_visibility.add_item("Private replacement requests", 1)
	_details.visible = false
	_retry.visible = false


func render(model: Dictionary) -> void:
	_model = model.duplicate(true)
	_rendering = true
	_action_pending = false
	var is_host := bool(_model.get("is_host", false))
	var started := bool(_model.get("match_started", false))
	var active_count := int(_model.get("active_player_count", 0))
	var spectator_count := int(_model.get("spectator_count", 0))
	_room_code.text = "ROOM  %s" % String(_model.get("room_code", "------"))
	_counts.text = "%d / 4 players   •   %d / 4 spectators" % [active_count, spectator_count]
	_render_players(_model.get("players", []))
	var settings: Dictionary = _model.get("settings", {})
	_victory_mode.select(int(settings.get("victory_mode", 0)))
	_victory_target.value = int(settings.get("victory_target", 10))
	_visibility.select(int(settings.get("information_visibility", 0)))
	_start_timer.value = int(settings.get("start_timer_msec", 5000)) / 1000.0
	_main_timer.value = int(settings.get("main_timer_msec", 5000)) / 1000.0
	_hand_timer.value = int(settings.get("hand_timer_msec", 15000)) / 1000.0
	_end_timer.value = int(settings.get("end_timer_msec", 3000)) / 1000.0
	_reaction_timer.value = int(settings.get("reaction_window_msec", 2000)) / 1000.0
	_hard_limit_timer.value = int(settings.get("public_hard_limit_msec", 30000)) / 1000.0
	_reconnect_timer.value = int(settings.get("reconnect_grace_msec", 30000)) / 1000.0
	var editable := is_host and not started
	_victory_mode.disabled = not editable
	_victory_target.editable = editable
	_visibility.disabled = not editable
	for timer in [
		_start_timer, _main_timer, _hand_timer, _end_timer,
		_reaction_timer, _hard_limit_timer, _reconnect_timer,
	]:
		timer.editable = editable
	_start_button.visible = is_host
	_start_button.disabled = not editable or active_count < 2
	_ready_button.disabled = started or str(_model.get("local_role", "active")) == "spectator"
	var connection: Dictionary = _model.get("connection", {})
	if connection.get("status", "connected") == "connected":
		_status.text = "Room ready. Share the code when everyone is seated."
		_status.modulate = Color("a7d8c4")
		_retry.visible = false
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
	}
	_status.text = messages.get(reason, "The room could not continue. Try again.")
	_status.modulate = Color("ff9a9a")
	_retry.visible = reason in [
		&"direct_connection_failed", &"relay_unavailable",
		&"signaling_timeout", &"room_not_found",
	]
	_action_pending = false


func _render_players(player_models: Array) -> void:
	for child in _players.get_children():
		child.queue_free()
	for player in player_models:
		if not player is Dictionary:
			continue
		var row := Label.new()
		var ready_text := "READY" if player.get("ready", false) else "WAITING"
		row.text = "%s   ·   %s   ·   %s" % [
			player.get("name", "Player"), str(player.get("role", "active")).to_upper(), ready_text,
		]
		_players.add_child(row)


func _on_setting_changed(value: Variant, key: StringName, scale_msec: bool = false) -> void:
	if _rendering or not bool(_model.get("is_host", false)) or bool(_model.get("match_started", false)):
		return
	var emitted_value: Variant = int(float(value) * 1000.0) if scale_msec else int(value)
	setting_change_requested.emit(key, emitted_value)


func _on_victory_mode_selected(index: int) -> void:
	_on_setting_changed(index, &"victory_mode")


func _on_victory_target_changed(value: float) -> void:
	_on_setting_changed(value, &"victory_target")


func _on_visibility_selected(index: int) -> void:
	_on_setting_changed(index, &"information_visibility")


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
	if _rendering or bool(_model.get("match_started", false)):
		return
	ready_requested.emit(ready)


func _on_start_pressed() -> void:
	if (
		_action_pending or not bool(_model.get("is_host", false))
		or bool(_model.get("match_started", false))
		or int(_model.get("active_player_count", 0)) < 2
	):
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
