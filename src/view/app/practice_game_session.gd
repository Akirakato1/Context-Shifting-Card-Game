extends RefCounted

signal command_result_received(request_message_id: String, result: Dictionary)
signal snapshot_applied(snapshot: Dictionary, sequence: int)
signal events_applied(events: Array, sequence: int)

const Types := preload("res://src/core/common/game_types.gd")
const Runtime := preload("res://src/view/app/runtime_game_session.gd")
const Controller := preload("res://src/core/match/match_controller.gd")
const State := preload("res://src/core/match/match_state.gd")
const Command := preload("res://src/core/commands/game_command.gd")
const DomainEvent := preload("res://src/core/events/domain_event.gd")
const Projector := preload("res://src/core/match/snapshot_projector.gd")
const HOST := &"host"
const OPPONENTS := [&"mika", &"ren", &"jo"]

var _runtime := Runtime.new()
var _controller: Controller
var _sequence := 0
var _bot_command_id := 0
var _next_bot_move := 0
var _last_phase := -1
var _last_round := -1
var _closed := false


func start() -> void:
	var config = _runtime._build_config([HOST] + OPPONENTS)
	config.set_victory_mode(Types.VictoryMode.ROUND_WIN_RACE)
	config.set_victory_target(3)
	config.set_information_visibility(Types.InformationVisibility.PRIVATE)
	_controller = Controller.new(State.create(config, randi()), null, Callable(), false)
	_controller.begin_match(Time.get_ticks_msec())
	_runtime._controller = _controller
	_runtime._display_names = {HOST: "You", &"mika": "Mika", &"ren": "Ren", &"jo": "Jo"}
	_publish()


func submit_command(request_message_id: String, command: Dictionary) -> Error:
	if _closed or _controller == null:
		return ERR_UNCONFIGURED
	_submit_local.call_deferred(request_message_id, command.duplicate(true))
	return OK


func _submit_local(request_message_id: String, command: Dictionary) -> void:
	if _closed:
		return
	var result = _controller.submit(Command.new(StringName(command.command_id), HOST,
		StringName(command.kind), command.payload), Time.get_ticks_msec())
	_publish(result.events)
	command_result_received.emit(request_message_id, {"accepted": result.accepted, "error_code": str(result.error_code)})


func poll() -> void:
	# Scoring can decide the winner before the final discards are done.
	if _closed or _controller == null or _controller.state.phase == Types.Phase.COMPLETE:
		return
	var now := Time.get_ticks_msec()
	var events := _controller.tick(now)
	var changed := not events.is_empty()
	if now >= _next_bot_move:
		_next_bot_move = now + 1_100
		for opponent in OPPONENTS:
			if _controller.state.phase != _last_phase or _controller.state.round_number != _last_round:
				break
			changed = _play_bot(opponent, now, events) or changed
	if changed:
		_publish(events)


func _play_bot(id: StringName, now: int, events: Array[DomainEvent]) -> bool:
	var state := _controller.state
	var player = state.players[id]
	match state.phase:
		Types.Phase.START, Types.Phase.MAIN_1, Types.Phase.MAIN_2:
			return not player.ready and _bot_submit(id, &"set_ready", {"ready": true}, now, events)
		Types.Phase.HAND_PLAY:
			if player.hand_locked:
				return false
			var cards: Array = []
			var contexts: Array = Projector.for_recipient(state, id, Types.RecipientRole.ACTIVE_PLAYER).active_contexts
			for card in player.hand:
				var eligible = card.eligible_half_indexes_for_contexts(PackedInt32Array(contexts))
				if eligible.is_empty():
					continue
				var choices: Array = []
				for i in 2:
					if card.half_at(i).is_joker():
						choices.append({"half_index": i, "context": state.active_context, "suit": 0})
				var best: int = eligible[0]
				for i in eligible:
					if card.half_at(i).effective_rank() > card.half_at(best).effective_rank():
						best = i
				cards.append({"card_id": str(card.card_id), "half_index": best, "joker_choices": choices})
			if _bot_submit(id, &"stage_hand", {"cards": cards}, now, events):
				return _bot_submit(id, &"lock_hand", {}, now, events)
		Types.Phase.END:
			if player.end_discard_complete:
				return false
			var ids: Array = []
			for i in maxi(0, player.ability_hand.size() - state.ability_deck.end_hand_limit):
				ids.append(str(player.ability_hand[i].copy_id))
			return _bot_submit(id, &"choose_ability_discards", {"copy_ids": ids}, now, events)
	return false


func _bot_submit(
	id: StringName, kind: StringName, payload: Dictionary, now: int, events: Array[DomainEvent]
) -> bool:
	_bot_command_id += 1
	var result := _controller.submit(Command.new(StringName("bot-%d" % _bot_command_id), id, kind, payload), now)
	events.append_array(result.events)
	return result.accepted


func _publish(events: Array = []) -> void:
	var state := _controller.state
	if _last_phase != state.phase or _last_round != state.round_number:
		_next_bot_move = Time.get_ticks_msec() + 950
		_last_phase = state.phase
		_last_round = state.round_number
	var snapshot := Projector.for_recipient(state, HOST, Types.RecipientRole.ACTIVE_PLAYER)
	snapshot["lobby_settings"] = state.config.to_dict()
	snapshot["server_now_msec"] = Time.get_ticks_msec()
	snapshot = _runtime._decorate_snapshot(snapshot, HOST, Types.RecipientRole.ACTIVE_PLAYER)
	snapshot["is_practice"] = true
	_sequence += 1
	var projected := DomainEvent.for_recipient(events, HOST, Types.RecipientRole.ACTIVE_PLAYER)
	if not projected.is_empty():
		events_applied.emit(projected, _sequence)
	snapshot_applied.emit(snapshot, _sequence)


func close() -> void:
	_closed = true
