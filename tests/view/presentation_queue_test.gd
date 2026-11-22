extends "res://tests/test_case.gd"

const PRESENTATION_STATE_PATH := "res://src/view/common/presentation_state.gd"
const PRESENTATION_QUEUE_PATH := "res://src/view/common/presentation_queue.gd"
const COMMAND_GATEWAY_PATH := "res://src/view/common/ui_command_gateway.gd"
const APP_CONTROLLER_PATH := "res://src/view/app/app_controller.gd"
const APP_ROOT_PATH := "res://src/view/app/app_root.tscn"


class FakeSession extends RefCounted:
	signal snapshot_applied(snapshot: Dictionary, sequence: int)
	signal events_applied(events: Array, sequence: int)
	signal command_result_received(request_message_id: String, result: Dictionary)
	signal session_failed(reason: String)

	var submissions: Array[Dictionary] = []
	var next_error: Error = OK

	func submit_command(message_id: String, command: Dictionary) -> Error:
		submissions.append({
			"message_id": message_id,
			"command": command.duplicate(true),
		})
		return next_error

	func poll() -> void:
		pass


func test_snapshot_replaces_gap_and_state_getters_are_immutable() -> void:
	var presentation = _new_script(PRESENTATION_STATE_PATH)
	if presentation == null:
		return
	assert_true(presentation.apply_snapshot({
		"phase": 1,
		"players": [{"player_id": "one", "score": 0}],
		"private_hand": [{"card_id": "card-1"}],
	}, 1))
	assert_true(presentation.apply_event({
		"kind": "score_changed",
		"state_patch": {"round_number": 2},
	}, 2))
	assert_false(presentation.apply_event({
		"kind": "stale",
		"state_patch": {"round_number": 99},
	}, 1))
	assert_eq(presentation.public_state().round_number, 2)

	assert_true(presentation.apply_snapshot({
		"phase": 4,
		"round_number": 7,
		"players": [{"player_id": "one", "score": 12}],
		"private_hand": [{"card_id": "replacement"}],
		"required_ability_discards": 2,
	}, 9))
	var public_copy: Dictionary = presentation.public_state()
	var private_copy: Dictionary = presentation.private_state()
	assert_false(public_copy.has("required_ability_discards"))
	assert_eq(private_copy.required_ability_discards, 2)
	public_copy.players[0].score = 999
	private_copy.private_hand[0].card_id = "mutated"
	assert_eq(presentation.public_state().players[0].score, 12)
	assert_eq(presentation.private_state().private_hand[0].card_id, "replacement")
	assert_eq(presentation.sequence(), 9)


func test_queue_skip_applies_remaining_events_without_stale_animation_callback() -> void:
	var queue = _new_script(PRESENTATION_QUEUE_PATH)
	if queue == null:
		return
	queue.set_duration(&"slow_reveal", 1000)
	var applied: Array[String] = []
	var finished: Array[String] = []
	queue.event_ready.connect(func(event: Dictionary): applied.append(event.kind))
	queue.cue_finished.connect(func(event: Dictionary): finished.append(event.kind))
	queue.enqueue([
		{"kind": "slow_reveal", "payload": {}, "sequence": 4},
		{"kind": "score_update", "payload": {}, "sequence": 5},
	])
	var token: int = queue.tick(0)
	assert_eq(applied, ["slow_reveal"])
	assert_true(queue.is_busy())

	queue.skip_to_latest()
	assert_eq(applied, ["slow_reveal", "score_update"])
	assert_false(queue.is_busy())
	assert_false(queue.complete_active(token))
	assert_eq(finished, [])

	queue.enqueue([{"kind": "old", "payload": {}, "sequence": 5}])
	var stale_token: int = queue.tick(0)
	queue.cancel_before_sequence(8)
	assert_false(queue.complete_active(stale_token))
	assert_false(queue.is_busy())


func test_command_gateway_deduplicates_in_flight_action_and_uses_unique_ids() -> void:
	var gateway = _new_script(COMMAND_GATEWAY_PATH)
	if gateway == null:
		return
	var session := FakeSession.new()
	gateway.bind_session(session)
	var completions: Array[Dictionary] = []
	gateway.command_completed.connect(func(kind: StringName, message_id: String, result: Dictionary):
		completions.append({
			"kind": kind, "message_id": message_id, "result": result,
		})
	)
	var first: String = gateway.send(&"lock_hand", {"cards": []})
	var duplicate: String = gateway.send(&"lock_hand", {"cards": []})
	assert_false(first.is_empty())
	assert_eq(duplicate, "")
	assert_eq(session.submissions.size(), 1)
	assert_eq(session.submissions[0].command.kind, "lock_hand")
	assert_eq(session.submissions[0].command.payload, {"cards": []})
	assert_false(String(session.submissions[0].command.command_id).is_empty())

	gateway.handle_command_result(first, {"accepted": false, "error_code": "invalid_hand"})
	assert_eq(completions, [{
		"kind": &"lock_hand",
		"message_id": first,
		"result": {"accepted": false, "error_code": "invalid_hand"},
	}])
	var second: String = gateway.send(&"lock_hand", {"cards": []})
	assert_ne(second, first)
	assert_eq(session.submissions.size(), 2)
	gateway.set_input_locked(true)
	assert_eq(gateway.send(&"set_ready", {"ready": true}), "")


func test_application_shell_instantiates_with_named_screen_host() -> void:
	if not ResourceLoader.exists(APP_ROOT_PATH):
		assert_true(false, "application shell scene must exist")
		return
	var root = load(APP_ROOT_PATH).instantiate()
	assert_true(root.has_node("Backdrop"))
	assert_true(root.has_node("SafeArea/ScreenHost"))
	assert_true(root.has_node("SafeArea/ConnectionBanner"))
	root.free()


func test_app_controller_binds_authoritative_session_updates_and_failure_state() -> void:
	var controller = _new_script(APP_CONTROLLER_PATH)
	if controller == null:
		return
	var session := FakeSession.new()
	controller.bind_session(session)
	session.snapshot_applied.emit({"phase": 1, "private_hand": []}, 3)
	assert_eq(controller.presentation_state.public_state().phase, 1)
	session.events_applied.emit([{
		"kind": "phase_changed",
		"state_patch": {"phase": 2},
	}], 4)
	controller.advance_presentation(0)
	assert_eq(controller.presentation_state.public_state().phase, 2)
	session.session_failed.emit("host_lost")
	assert_eq(controller.connection_state(), {
		"status": "failed",
		"reason": "host_lost",
	})
	controller.free()


func _new_script(path: String) -> Variant:
	if not ResourceLoader.exists(path):
		assert_true(false, "%s must exist" % path)
		return null
	var script: Script = load(path)
	if script == null or not script.can_instantiate():
		assert_true(false, "%s must instantiate" % path)
		return null
	return script.new()
