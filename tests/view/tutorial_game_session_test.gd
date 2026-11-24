extends "res://tests/test_case.gd"

const Tutorial := preload("res://src/view/app/tutorial_game_session.gd")
const Command := preload("res://src/core/commands/game_command.gd")
const Types := preload("res://src/core/common/game_types.gd")
const Events := preload("res://src/core/events/domain_event.gd")

var _session: Tutorial
var _command_id := 0
var _now := 0


func test_tutorial_plays_three_fixed_rounds_through_the_match_controller() -> void:
	_session = Tutorial.new()
	_session.start()
	_now = Time.get_ticks_msec()
	var state = _session._controller.state
	var player: PlayerState = state.players[&"host"]
	assert_eq(state.seat_order, [&"host", &"mika"])
	assert_eq(state.phase, Types.Phase.MAIN_1)
	assert_eq(state.phase_deadline_msec, -1)
	assert_false(_send(&"set_ready", {"ready": true}).accepted)
	_read_steps()

	_play(&"rise_ascendancy")
	_ready_up()
	_read_steps()
	await _flip_tutorial_card()
	_submit_hand([_pick(0, 0), _pick(1, 1)])
	assert_eq(player.provisional_score.base_value, 16)
	assert_eq(player.locked_context.category_id, &"all_contexts_1")
	assert_eq(player.provisional_score.final_score > 16, true)
	_read_steps()
	_ready_up()
	assert_eq(player.round_wins, 1)

	_send(&"set_replenishment_request", {"request": {0: 4}})
	assert_false(_send(&"set_ready", {"ready": true}).accepted)
	_draw({1: 4})
	_play(&"momentary_lock", "mika")
	_ready_up()
	_manipulate(&"mirror_rank", 2)
	var three_of_a_kind := [_pick(2, 0)]
	for card in player.hand:
		if card.card_id not in _session._opening_cards:
			three_of_a_kind.append({"card_id": str(card.card_id), "half_index": 0})
	_submit_hand(three_of_a_kind)
	assert_eq(player.provisional_score.base_value, 9)
	assert_eq(player.locked_context.category_id, &"flourish_6")
	_read_steps()
	_ready_up()
	assert_eq(player.round_wins, 2)
	assert_eq(state.phase, Types.Phase.END)
	assert_eq(player.ability_hand.size(), 3)
	_require(&"choose_ability_discards", {"copy_ids": [str(player.ability_hand[0].copy_id)]})
	_run_bot()
	assert_eq(player.ability_hand.size(), 2)

	_draw({0: 1, 2: 5})
	assert_eq(player.ability_hand.size(), 5)
	_ready_up()
	_manipulate(&"suit_imprint", 4, 0)
	_manipulate(&"ride_the_cycle", 5)
	var joker_pick := _pick(3, 0)
	joker_pick["joker_choices"] = [{"half_index": 1, "context": 0, "suit": 0}]
	var flush := [joker_pick, _pick(4, 0), _pick(5, 0)]
	for card in player.hand:
		if card.card_id in _session._opening_cards:
			continue
		var halves := card.eligible_half_indexes(Types.Context.FALL)
		if halves.size() == 1:
			flush.append({"card_id": str(card.card_id), "half_index": halves[0]})
			break
	assert_eq(flush.size(), 4)
	_submit_hand(flush)
	assert_eq(player.locked_context.category_id, &"rise_fall_4")
	var before: int = player.provisional_score.final_score
	_play(&"flush_buff", "host")
	assert_true(player.provisional_score.final_score > before)
	_ready_up()
	assert_eq(state.phase, Types.Phase.COMPLETE)
	assert_eq(state.winner_id, &"host")
	assert_eq(player.round_wins, 3)
	assert_true(_session._current_lesson().is_empty())
	_session.close()
	_session = null


func _flip_tutorial_card() -> void:
	var step := _session._step
	var card_id := _session._opening_cards[1]
	_session.advance_lesson()
	_session.complete_card_flip(_session._opening_cards[0], 1)
	assert_eq(_session._step, step)
	assert_false(_send(&"lock_hand", {}).accepted)
	var scene := preload("res://src/view/match/match_screen.tscn")
	var table = scene.instantiate()
	Engine.get_main_loop().root.add_child(table)
	var render_snapshot := func(snapshot: Dictionary, _sequence: int): table.render(snapshot)
	_session.snapshot_applied.connect(render_snapshot)
	table.intent_requested.connect(func(kind: StringName, payload: Dictionary):
		if kind == &"tutorial_flip":
			_session.complete_card_flip(StringName(payload.card_id), int(payload.top_half))
	)
	_session._publish()
	assert_false(table.get_node("Tutorial/Margin/Content/Next").visible)
	var controls = table.get_node("PhaseControls")
	controls.sort_hand(Types.Context.RISE)
	assert_eq(_session._step, step)
	assert_false(controls.card_widget(card_id).orientation_flipped)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	controls.card_widget(card_id)._gui_input(click)
	assert_eq(_session._step, step + 1)
	assert_true(controls.card_widget(card_id).orientation_flipped)
	_session.snapshot_applied.disconnect(render_snapshot)
	table.queue_free()
	await Engine.get_main_loop().process_frame


func _read_steps() -> void:
	while _session._current_lesson().get("command", &"") == &"":
		var step := _session._step
		_session.advance_lesson()
		if _session._step == step:
			break


func _ready_up() -> void:
	_run_bot()
	_require(&"set_ready", {"ready": true})


func _draw(request: Dictionary) -> void:
	_require(&"set_replenishment_request", {"request": request})
	_ready_up()


func _play(id: StringName, target := "") -> void:
	var payload := {"copy_id": _ability_id(id), "target_player_id": target}
	if not target.is_empty():
		payload["choices"] = {"target_player_id": [target]}
	_require(&"play_public_ability", payload)


func _manipulate(id: StringName, card_index: int, suit := -1) -> void:
	_require(&"stage_manipulation", {"copy_id": _ability_id(id)})
	var choices := {"cards": [str(_session._opening_cards[card_index])]}
	if suit >= 0:
		choices["suit"] = [suit]
	_require(&"commit_manipulation", {"choices": choices})


func _pick(index: int, half_index: int) -> Dictionary:
	return {"card_id": str(_session._opening_cards[index]), "half_index": half_index}


func _submit_hand(picks: Array) -> void:
	_require(&"stage_hand", {"cards": picks})
	_require(&"lock_hand", {})
	_require(&"unlock_hand", {})
	_run_bot()
	_require(&"lock_hand", {})


func _ability_id(id: StringName) -> String:
	for card in _session._controller.state.players[&"host"].ability_hand:
		if card.definition.id == id:
			return str(card.copy_id)
	assert_true(false, "Missing ability %s" % id)
	return ""


func _run_bot() -> void:
	_now += 3_000
	var events: Array[Events] = []
	_session._play_bot(&"mika", _now, events)


func _require(kind: StringName, payload: Dictionary) -> void:
	var result = _send(kind, payload)
	assert_true(result.accepted, "%s %s failed at lesson %d: %s" % [kind, payload, _session._step + 1, result.error_code])


func _send(kind: StringName, payload: Dictionary):
	_command_id += 1
	return _session._submit_player_command(
		Command.new(StringName("test-%d" % _command_id), &"host", kind, payload),
		_now
	)
