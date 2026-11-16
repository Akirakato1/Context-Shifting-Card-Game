class_name MainMenuScreen
extends Control

signal host_requested(player_name: String)
signal join_requested(player_name: String, room_code: String, role: String)

var _busy := false

@onready var _name_input: LineEdit = $Content/PlayerName
@onready var _host_button: Button = $Content/HostButton
@onready var _code_input: LineEdit = $Content/JoinPanel/JoinFields/Code
@onready var _role_input: OptionButton = $Content/JoinPanel/JoinFields/Role
@onready var _join_button: Button = $Content/JoinPanel/JoinFields/JoinButton
@onready var _status: Label = $Content/Status


func _ready() -> void:
	if _role_input.item_count == 0:
		_role_input.add_item("Active player", 0)
		_role_input.add_item("Spectator", 1)
	_update_buttons()


func set_busy(busy: bool, message: String = "") -> void:
	_busy = busy
	if not message.is_empty():
		_status.text = message
	_update_buttons()


func show_error(message: String) -> void:
	_busy = false
	_status.text = message
	_status.modulate = Color("ff9a9a")
	_update_buttons()


func clear_error() -> void:
	_status.text = "Host a new table or join your friends with a room code."
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
	_host_button.disabled = _busy or not has_name
	_join_button.disabled = _busy or not has_name or normalized_code().length() != 6
