class_name GameProtocol
extends RefCounted

const VERSION := 1
const MAX_ENVELOPE_BYTES := 256 * 1024
const MAX_SAFE_JSON_INTEGER := 9007199254740991.0
const KINDS: Array[String] = [
	"command",
	"command_result",
	"event_batch",
	"snapshot",
	"view_update",
	"heartbeat",
	"heartbeat_ack",
	"disconnect_notice",
]


class ProtocolResult extends RefCounted:
	var ok: bool
	var error_code: StringName
	var envelope: Dictionary

	func _init(
		was_ok: bool,
		error: StringName = &"",
		decoded_envelope: Dictionary = {}
	) -> void:
		ok = was_ok
		error_code = error
		envelope = decoded_envelope.duplicate(true)


static func encode(envelope: Dictionary) -> PackedByteArray:
	if not _is_json_safe(envelope):
		return PackedByteArray()
	var normalized: Dictionary = _normalize_json(envelope)
	if not _validate_envelope(normalized).is_empty():
		return PackedByteArray()
	var bytes := JSON.stringify(normalized).to_utf8_buffer()
	if bytes.size() > MAX_ENVELOPE_BYTES:
		return PackedByteArray()
	return bytes


static func decode(bytes: PackedByteArray) -> ProtocolResult:
	if bytes.is_empty():
		return ProtocolResult.new(false, &"empty_message")
	if bytes.size() > MAX_ENVELOPE_BYTES:
		return ProtocolResult.new(false, &"message_too_large")

	if not _is_valid_utf8(bytes):
		return ProtocolResult.new(false, &"invalid_utf8")
	var text := bytes.get_string_from_utf8()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return ProtocolResult.new(false, &"invalid_json")
	if not parser.data is Dictionary:
		return ProtocolResult.new(false, &"invalid_envelope")
	if not _is_json_safe(parser.data):
		return ProtocolResult.new(false, &"invalid_envelope")

	var normalized: Dictionary = _normalize_json(parser.data)
	var validation_error := _validate_envelope(normalized)
	if not validation_error.is_empty():
		return ProtocolResult.new(false, validation_error)
	return ProtocolResult.new(true, &"", normalized)


static func _validate_envelope(envelope: Dictionary) -> StringName:
	if not envelope.has("v"):
		return &"missing_version"
	if typeof(envelope["v"]) != TYPE_INT or envelope["v"] != VERSION:
		return &"unsupported_version"
	if not envelope.has("kind") or typeof(envelope["kind"]) != TYPE_STRING:
		return &"unknown_kind"
	if not KINDS.has(envelope["kind"]):
		return &"unknown_kind"
	for id_key in ["message_id", "match_id", "sender_id"]:
		if (
			not envelope.has(id_key)
			or typeof(envelope[id_key]) != TYPE_STRING
			or String(envelope[id_key]).is_empty()
		):
			return StringName("missing_%s" % id_key)
	if not envelope.has("payload") or not envelope["payload"] is Dictionary:
		return &"invalid_payload"
	return &""


static func _is_json_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item in value:
				if not _is_json_safe(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
					return false
				if not _is_json_safe(value[key]):
					return false
			return true
		_:
			return false


static func _is_valid_utf8(bytes: PackedByteArray) -> bool:
	var index := 0
	while index < bytes.size():
		var leading := bytes[index]
		if leading <= 0x7f:
			index += 1
			continue
		if leading >= 0xc2 and leading <= 0xdf:
			if index + 1 >= bytes.size() or not _is_continuation(bytes[index + 1]):
				return false
			index += 2
			continue
		if leading >= 0xe0 and leading <= 0xef:
			if index + 2 >= bytes.size():
				return false
			var second := bytes[index + 1]
			if (
				(leading == 0xe0 and (second < 0xa0 or second > 0xbf))
				or (leading == 0xed and (second < 0x80 or second > 0x9f))
				or (leading != 0xe0 and leading != 0xed and not _is_continuation(second))
				or not _is_continuation(bytes[index + 2])
			):
				return false
			index += 3
			continue
		if leading >= 0xf0 and leading <= 0xf4:
			if index + 3 >= bytes.size():
				return false
			var second := bytes[index + 1]
			if (
				(leading == 0xf0 and (second < 0x90 or second > 0xbf))
				or (leading == 0xf4 and (second < 0x80 or second > 0x8f))
				or (leading != 0xf0 and leading != 0xf4 and not _is_continuation(second))
				or not _is_continuation(bytes[index + 2])
				or not _is_continuation(bytes[index + 3])
			):
				return false
			index += 4
			continue
		return false
	return true


static func _is_continuation(byte: int) -> bool:
	return byte >= 0x80 and byte <= 0xbf


static func _normalize_json(value: Variant) -> Variant:
	match typeof(value):
		TYPE_STRING_NAME:
			return String(value)
		TYPE_FLOAT:
			if absf(value) <= MAX_SAFE_JSON_INTEGER and value == floorf(value):
				return int(value)
			return value
		TYPE_ARRAY:
			var normalized_array: Array = []
			for item in value:
				normalized_array.append(_normalize_json(item))
			return normalized_array
		TYPE_DICTIONARY:
			var normalized_dictionary := {}
			for key in value:
				normalized_dictionary[String(key)] = _normalize_json(value[key])
			return normalized_dictionary
		_:
			return value
