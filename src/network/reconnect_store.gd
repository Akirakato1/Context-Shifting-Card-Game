class_name ReconnectStore
extends RefCounted

const DEFAULT_PATH := "user://shift-reconnect.json"

var _path: String


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


func save(
	room_code: String,
	player_id: StringName,
	token: String,
	expires_at: int
) -> Error:
	if room_code.is_empty() or player_id.is_empty() or token.is_empty() or expires_at < 0:
		return ERR_INVALID_PARAMETER
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({
		"room_code": room_code.to_upper(),
		"player_id": str(player_id),
		"token": token,
		"expires_at": expires_at,
	}))
	file.close()
	return OK


func load_record(now_msec: int) -> Dictionary:
	if not FileAccess.file_exists(_path):
		return {}
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not _is_valid_record(parsed):
		clear()
		return {}
	var record: Dictionary = parsed
	record["expires_at"] = int(record["expires_at"])
	if now_msec > record["expires_at"]:
		clear()
		return {}
	return record.duplicate(true)


func verify(
	room_code: String,
	player_id: StringName,
	token: String,
	now_msec: int
) -> bool:
	var record := load_record(now_msec)
	return (
		not record.is_empty()
		and record["room_code"] == room_code.to_upper()
		and record["player_id"] == str(player_id)
		and record["token"] == token
	)


func clear() -> Error:
	if not FileAccess.file_exists(_path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


func _is_valid_record(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	return (
		typeof(value.get("room_code", null)) == TYPE_STRING
		and not String(value["room_code"]).is_empty()
		and typeof(value.get("player_id", null)) == TYPE_STRING
		and not String(value["player_id"]).is_empty()
		and typeof(value.get("token", null)) == TYPE_STRING
		and not String(value["token"]).is_empty()
		and typeof(value.get("expires_at", null)) in [TYPE_INT, TYPE_FLOAT]
	)
