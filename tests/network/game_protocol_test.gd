extends "res://tests/test_case.gd"

const GameProtocol = preload("res://src/network/game_protocol.gd")


func test_shared_fixtures_round_trip_every_kind_and_unicode() -> void:
	var source := FileAccess.get_file_as_string(
		"res://service/signaling/test/fixtures/game_envelopes.json"
	)
	var fixture: Dictionary = JSON.parse_string(source)
	var seen_kinds: Array[String] = []
	for envelope in fixture["envelopes"]:
		var encoded: PackedByteArray = GameProtocol.encode(envelope)
		var decoded = GameProtocol.decode(encoded)
		assert_true(decoded.ok, "fixture should decode: %s" % str(decoded.error_code))
		if decoded.ok:
			seen_kinds.append(decoded.envelope["kind"])
			assert_eq(JSON.parse_string(JSON.stringify(decoded.envelope)), envelope)
	assert_eq(seen_kinds, GameProtocol.KINDS)
	assert_eq(fixture["envelopes"][0]["payload"]["display_name"], "Zoë 雪")


func test_empty_payload_and_json_types_are_stable() -> void:
	var envelope := _envelope("heartbeat", {
		&"label": &"ready",
		"count": 7,
		"ratio": 1.25,
		"enabled": true,
		"nothing": null,
		"nested": [{&"key": &"value"}],
	})
	var decoded = GameProtocol.decode(GameProtocol.encode(envelope))

	assert_true(decoded.ok)
	assert_eq(decoded.envelope["payload"]["label"], "ready")
	assert_eq(typeof(decoded.envelope["payload"]["label"]), TYPE_STRING)
	assert_eq(typeof(decoded.envelope["payload"]["count"]), TYPE_INT)
	assert_eq(typeof(decoded.envelope["payload"]["ratio"]), TYPE_FLOAT)
	assert_eq(decoded.envelope["payload"]["nested"][0]["key"], "value")

	var empty = GameProtocol.decode(GameProtocol.encode(_envelope("heartbeat_ack", {})))
	assert_true(empty.ok)
	assert_eq(empty.envelope["payload"], {})


func test_exact_maximum_envelope_is_accepted_and_one_more_byte_is_rejected() -> void:
	var baseline := _envelope("snapshot", {"blob": ""})
	var baseline_size := JSON.stringify(baseline).to_utf8_buffer().size()
	var legal_blob_size: int = GameProtocol.MAX_ENVELOPE_BYTES - baseline_size
	var legal := _envelope("snapshot", {"blob": "x".repeat(legal_blob_size)})
	var legal_bytes: PackedByteArray = GameProtocol.encode(legal)

	assert_eq(legal_bytes.size(), GameProtocol.MAX_ENVELOPE_BYTES)
	assert_true(GameProtocol.decode(legal_bytes).ok)
	assert_eq(GameProtocol.encode(
		_envelope("snapshot", {"blob": "x".repeat(legal_blob_size + 1)})
	).size(), 0)

	var oversized := legal_bytes.duplicate()
	oversized.append(32)
	var oversized_result = GameProtocol.decode(oversized)
	assert_false(oversized_result.ok)
	assert_eq(oversized_result.error_code, &"message_too_large")


func test_decode_rejects_invalid_utf8_json_version_kind_and_ids() -> void:
	_assert_decode_error(PackedByteArray([0xc3, 0x28]), &"invalid_utf8")
	_assert_decode_error("{".to_utf8_buffer(), &"invalid_json")

	var unknown_version := _envelope("command", {})
	unknown_version["v"] = 2
	_assert_decode_error(JSON.stringify(unknown_version).to_utf8_buffer(), &"unsupported_version")

	var unknown_kind := _envelope("not_real", {})
	_assert_decode_error(JSON.stringify(unknown_kind).to_utf8_buffer(), &"unknown_kind")

	for id_key in ["message_id", "match_id", "sender_id"]:
		var missing := _envelope("command", {})
		missing.erase(id_key)
		_assert_decode_error(
			JSON.stringify(missing).to_utf8_buffer(),
			StringName("missing_%s" % id_key)
		)


func test_encode_rejects_non_json_payload_values() -> void:
	assert_eq(GameProtocol.encode(_envelope("command", {"object": self})).size(), 0)
	assert_eq(GameProtocol.encode(_envelope(
		"command", {"callable": Callable(self, "failures")}
	)).size(), 0)


func _envelope(kind: String, payload: Dictionary) -> Dictionary:
	return {
		"v": 1,
		"kind": kind,
		"message_id": "message-1",
		"match_id": "match-1",
		"sender_id": "sender-1",
		"payload": payload,
	}


func _assert_decode_error(bytes: PackedByteArray, expected: StringName) -> void:
	var result = GameProtocol.decode(bytes)
	assert_false(result.ok)
	assert_eq(result.error_code, expected)
