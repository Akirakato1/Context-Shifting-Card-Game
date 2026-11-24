extends "res://src/view/app/practice_game_session.gd"

const Kinds := preload("res://src/core/commands/command_kinds.gd")
const FullCard := preload("res://src/core/cards/full_card_state.gd")
const Pile := preload("res://src/core/cards/context_pile.gd")
const AbilityCard := preload("res://src/core/abilities/ability_state.gd")
const AbilityDeck := preload("res://src/core/abilities/ability_deck_state.gd")
const Lesson := preload("res://src/view/app/tutorial_lesson.gd")
const BOT := &"mika"
const RISE := Types.Context.RISE
const FLOURISH := Types.Context.FLOURISH
const FALL := Types.Context.FALL
const MOUNTAIN := Types.Suit.MOUNTAIN
const CLOUD := Types.Suit.CLOUD
const SEA := Types.Suit.SEA

var _step := 0
var _opening_cards: Array[StringName] = []


func start() -> void:
	_opponents.assign([BOT])
	super.start()


func advance_lesson() -> void:
	var lesson := _current_lesson()
	if lesson.is_empty() or lesson.has("command") or lesson.has("flip_card") or not _at_lesson(lesson):
		return
	_step += 1
	_publish()


func complete_card_flip(card_id: StringName, top_half: int) -> void:
	var lesson := _current_lesson()
	if (
		not lesson.has("flip_card") or not _at_lesson(lesson)
		or card_id != _opening_cards[lesson.flip_card] or top_half != 1
	):
		return
	_step += 1
	_publish()


func _submit_player_command(command: Command, now: int) -> CommandResult:
	var lesson := _current_lesson()
	var kind := command.kind
	if kind == Kinds.UNLOCK_HAND:
		var reopen := super._submit_player_command(command, now)
		if reopen.accepted:
			_step -= 1
		return reopen
	if kind not in [
		Kinds.SET_READY, Kinds.PLAY_PUBLIC_ABILITY, Kinds.STAGE_MANIPULATION,
		Kinds.COMMIT_MANIPULATION, Kinds.LOCK_HAND, Kinds.CHOOSE_ABILITY_DISCARDS,
	]:
		return super._submit_player_command(command, now)
	if lesson.is_empty() or not _at_lesson(lesson) or not _matches_lesson(command, lesson):
		return CommandResult.new(false, &"follow_the_tutorial_prompt")
	var result := super._submit_player_command(command, now)
	if result.accepted and kind != Kinds.STAGE_MANIPULATION:
		_step += 1
	return result


func _matches_lesson(command: Command, lesson: Dictionary) -> bool:
	var kind := command.kind
	var expected: StringName = lesson.get("command", &"")
	if kind != expected and (kind != Kinds.STAGE_MANIPULATION or expected != Kinds.COMMIT_MANIPULATION):
		return false
	var player: PlayerState = _controller.state.players[HOST]
	var payload := command.payload
	match kind:
		Kinds.SET_READY:
			if not payload.get("ready", false):
				return false
			var request: Dictionary = _controller.state.start_requests.get(HOST, {})
			for context in [RISE, FLOURISH, FALL]:
				if lesson.has("draw") and request.get(context, 0) != lesson.draw.get(context, 0):
					return false
		Kinds.PLAY_PUBLIC_ABILITY, Kinds.STAGE_MANIPULATION, Kinds.COMMIT_MANIPULATION:
			var copy_id := StringName(payload.get("copy_id", player.pending_manipulation.get("copy_id", "")))
			var ability_matches := player.ability_hand.any(
				func(card: AbilityCard): return card.copy_id == copy_id and card.definition.id == lesson.ability
			)
			if not ability_matches:
				return false
			if kind == Kinds.PLAY_PUBLIC_ABILITY:
				return StringName(payload.get("target_player_id", "")) == lesson.get("target", &"")
			if kind == Kinds.COMMIT_MANIPULATION:
				var choices: Dictionary = payload.get("choices", {})
				var cards: Array = choices.get("cards", [])
				if cards.size() != 1 or str(cards[0]) != str(_opening_cards[lesson.card]):
					return false
				if lesson.has("suit") and choices.get("suit", []) != [lesson.suit]:
					return false
		Kinds.LOCK_HAND:
			return _matches_hand(player, lesson)
	return true


func _matches_hand(player: PlayerState, lesson: Dictionary) -> bool:
	var staged := player.staged_submission
	if staged.size() != lesson.hand_size:
		return false
	for index in lesson.get("opening_cards", []):
		if not staged.any(func(pick: Dictionary): return pick.card_id == _opening_cards[index]):
			return false
	for pick in staged:
		var card_index := player.hand.find_custom(func(card: FullCard): return card.card_id == pick.card_id)
		if card_index < 0:
			return false
		var card: FullCard = player.hand[card_index]
		var half = card.half_at(pick.half_index)
		if lesson.has("rank") and half.effective_rank() != lesson.rank:
			return false
		if lesson.has("suit") and half.effective_suit() != lesson.suit:
			return false
		if lesson.has("bottom_context"):
			var bottom = card.half_at(1 - pick.half_index)
			var context: int = bottom.joker_context if bottom.is_joker() else bottom.effective_context()
			if context != lesson.bottom_context:
				return false
			if bottom.is_joker() and bottom.joker_suit != MOUNTAIN:
				return false
	return true


func _current_lesson() -> Dictionary:
	return Lesson.STEPS[_step] if _step < Lesson.STEPS.size() else {}


func _at_lesson(lesson: Dictionary) -> bool:
	return _controller.state.round_number == lesson.round and _controller.state.phase == lesson.phase


func _append_local_snapshot_data(snapshot: Dictionary) -> void:
	super._append_local_snapshot_data(snapshot)
	snapshot["is_tutorial"] = true
	var lesson := _current_lesson()
	if lesson.is_empty():
		return
	var active := _at_lesson(lesson)
	snapshot["tutorial"] = {
		"step": _step + 1,
		"total": Lesson.STEPS.size(),
		"title": lesson.title if active else "Finishing the phase",
		"body": lesson.body if active else "Mika acts automatically. The next lesson appears when this phase closes.",
		"show_next": active and not lesson.has("command") and not lesson.has("flip_card"),
	}
	if active and lesson.has("flip_card"):
		snapshot.tutorial["flip_card_id"] = str(_opening_cards[lesson.flip_card])


func _create_starting_state(config: MatchConfig) -> State:
	var state := State.create(config, 610_023)
	_script_context_cards(state)
	_script_ability_cards(state)
	return state


func _script_context_cards(state: State) -> void:
	var pools := {}
	for context in [RISE, FLOURISH, FALL]:
		pools[context] = state.piles[context].snapshot_draw_cards()
	for player_id in state.seat_order:
		var player: PlayerState = state.players[player_id]
		for card in player.hand:
			pools[card.first.base_context].append(card.first)
			pools[card.second.base_context].append(card.second)
		player.hand.clear()
	var player: PlayerState = state.players[HOST]
	for faces in [
		[[RISE, 8, MOUNTAIN], [FALL, 3, SEA]],
		[[FLOURISH, 2, CLOUD], [RISE, 8, CLOUD]],
		[[FLOURISH, 8, SEA], [FLOURISH, 6, CLOUD]],
		[[FALL, 4, MOUNTAIN], [RISE, 0, -1]],
		[[FALL, 7, CLOUD], [RISE, 2, SEA]],
		[[FLOURISH, 9, MOUNTAIN], [FALL, 10, CLOUD]],
	]:
		var card := _deal_card(state, pools, faces)
		player.hand.append(card)
		_opening_cards.append(card.card_id)
	var bot: PlayerState = state.players[BOT]
	for faces in [
		[[RISE, 1, SEA], [FALL, 1, CLOUD]],
		[[RISE, 1, CLOUD], [FLOURISH, 1, MOUNTAIN]],
		[[RISE, 1, MOUNTAIN], [FALL, 1, SEA]],
		[[FLOURISH, 1, CLOUD], [FALL, 1, MOUNTAIN]],
		[[FLOURISH, 2, MOUNTAIN], [FALL, 2, SEA]],
		[[FLOURISH, 2, SEA], [FALL, 2, CLOUD]],
	]:
		bot.hand.append(_deal_card(state, pools, faces))
	var upcoming := {
		RISE: [[RISE, 5, CLOUD]],
		FLOURISH: [
			[FLOURISH, 3, MOUNTAIN], [FLOURISH, 3, CLOUD],
			[FLOURISH, 3, SEA], [FLOURISH, 3, SEA],
		],
		FALL: [
			[FALL, 2, MOUNTAIN], [FALL, 5, MOUNTAIN],
			[FALL, 6, MOUNTAIN], [FALL, 8, MOUNTAIN], [FALL, 10, MOUNTAIN],
		],
	}
	for context in upcoming:
		var draws: Array = []
		for face in upcoming[context]:
			draws.push_front(_take_half(pools, face))
		state.piles[context] = Pile.new(context, pools[context] + draws)


func _deal_card(state: State, pools: Dictionary, faces: Array) -> FullCard:
	return FullCard.new(state.allocate_card_id(), _take_half(pools, faces[0]), _take_half(pools, faces[1]))


func _take_half(pools: Dictionary, face: Array) -> HalfCardState:
	var pile: Array = pools[face[0]]
	var index := pile.find_custom(
		func(half: HalfCardState): return half.base_rank == face[1] and half.base_suit == face[2]
	)
	assert(index >= 0, "Missing tutorial half %s" % [face])
	return pile.pop_at(index)


func _script_ability_cards(state: State) -> void:
	var deck: Array[AbilityCard] = []
	for index in state.config.ability_definitions.size():
		deck.append(AbilityCard.new(
			StringName("ability-copy-%03d" % index), state.config.ability_definitions[index]
		))
	var scripted_draws: Array[AbilityCard] = []
	for id in [
		# Opening player and bot hands, then each subsequent Start draw in seat order.
		&"rise_ascendancy", &"mirror_rank", &"group_buff",
		&"rank_nudge", &"low_roll",
		&"momentary_lock", &"against_the_cycle", &"suit_exchange",
		&"against_the_cycle", &"suit_exchange", &"high_roll",
		&"suit_imprint", &"ride_the_cycle", &"flush_buff",
	]:
		var index := deck.find_custom(func(card: AbilityCard): return card.definition.id == id)
		assert(index >= 0, "Missing tutorial ability %s" % id)
		scripted_draws.push_front(deck.pop_at(index))
	state.ability_deck = AbilityDeck.new(state.rng.shuffle(deck) + scripted_draws)
	state.players[HOST].ability_hand = state.ability_deck.draw(HOST, 3, state.rng)
	state.players[BOT].ability_hand = state.ability_deck.draw(BOT, 2, state.rng)


func _play_bot(id: StringName, now: int, events: Array[DomainEvent]) -> bool:
	var state := _controller.state
	var player: PlayerState = state.players[id]
	if state.phase == Types.Phase.START and not player.ready:
		_bot_submit(id, Kinds.SET_REPLENISHMENT_REQUEST, {"request": {FLOURISH: 2}}, now, events)
	if state.phase != Types.Phase.HAND_PLAY:
		return super._play_bot(id, now, events)
	if player.hand_locked:
		return false
	var submission: Array = []
	for card in player.hand:
		if card.card_id in player.submission_locked_card_ids:
			continue
		for index in card.eligible_half_indexes(state.active_context):
			var half = card.half_at(index)
			if not half.is_joker() and half.effective_rank() <= 2:
				submission.append({"card_id": str(card.card_id), "half_index": index})
				break
		if not submission.is_empty():
			break
	return (
		_bot_submit(id, Kinds.STAGE_HAND, {"cards": submission}, now, events)
		and _bot_submit(id, Kinds.LOCK_HAND, {}, now, events)
	)
