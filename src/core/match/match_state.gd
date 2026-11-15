class_name MatchState
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const RandomSource = preload("res://src/core/common/random_source.gd")
const HalfCardState = preload("res://src/core/cards/half_card_state.gd")
const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const ContextPile = preload("res://src/core/cards/context_pile.gd")
const CardFactory = preload("res://src/core/cards/card_factory.gd")
const AbilityState = preload("res://src/core/abilities/ability_state.gd")
const AbilityDeckState = preload("res://src/core/abilities/ability_deck_state.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const PlayerState = preload("res://src/core/match/player_state.gd")
const Rational = preload("res://src/core/common/rational.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")

var config: MatchConfig
var seed: int
var rng: RandomSource
var piles: Dictionary = {}
var ability_deck: AbilityDeckState
var players: Dictionary = {}
var seat_order: Array[StringName] = []
var round_number := 1
var active_context := GameTypes.Context.A
var context_direction := GameTypes.ContextDirection.FORWARD
var phase := GameTypes.Phase.START
var winner_id: StringName = &""
var match_complete := false
var start_ability_drawn_round := 0
var start_prepared_round := 0
var phase_started_msec := -1
var phase_deadline_msec := -1
var reaction_deadline_msec := -1
var last_round_winner_id: StringName = &""
var host_player_id: StringName = &""
var frozen := false
var freeze_started_msec := -1


static func create(match_config: MatchConfig, match_seed: int) -> MatchState:
	assert(match_config.validate().is_empty(), "invalid match config: %s" % match_config.validate())
	var state := _new_state()
	state.config = match_config
	state.seed = match_seed
	state.rng = RandomSource.new(match_seed)
	state.piles = state._build_piles()
	var ability_cards: Array[AbilityState] = []
	var definitions := match_config.ability_definitions
	for index in range(definitions.size()):
		ability_cards.append(AbilityState.new(
			StringName("ability-copy-%03d" % index), definitions[index]
		))
	ability_cards.assign(state.rng.shuffle(ability_cards))
	state.ability_deck = AbilityDeckState.new(ability_cards)
	state.seat_order = match_config.active_player_ids
	state.host_player_id = state.seat_order[0]
	for index in range(state.seat_order.size()):
		var player_id := state.seat_order[index]
		var player := PlayerState.new(player_id, index)
		player.hand = CardFactory.build_opening_hand(state.piles, state.rng)
		player.ability_hand = state.ability_deck.draw(
			player_id, state.ability_deck.starting_hand_size, state.rng
		)
		state.players[player_id] = player
	for spectator_id in match_config.spectator_ids:
		state.players[spectator_id] = PlayerState.new(spectator_id, -1, true)
	match_config.lock_for_match()
	return state


func deal_start_abilities() -> void:
	if start_ability_drawn_round == round_number:
		return
	for player_id in seat_order:
		var player: PlayerState = players[player_id]
		if not player.active or player.pending:
			continue
		player.ability_hand.append_array(ability_deck.draw(
			player_id, ability_deck.start_draw_count, rng
		))
	start_ability_drawn_round = round_number


func resolve_round(final_scores: Dictionary) -> StringName:
	var highest := -1
	var leaders: Array[StringName] = []
	for player_id in seat_order:
		var player: PlayerState = players[player_id]
		if not player.active: continue
		var score: int = final_scores.get(player_id, 0)
		if score > highest:
			highest = score
			leaders = [player_id]
		elif score == highest:
			leaders.append(player_id)
	if leaders.size() != 1:
		return &""
	var round_winner_id := leaders[0]
	var round_winner: PlayerState = players[round_winner_id]
	if config.victory_mode == GameTypes.VictoryMode.SCORE_RACE:
		round_winner.match_score += max(highest, 0)
		if round_winner.match_score >= config.victory_target:
			_set_winner(round_winner_id)
	else:
		round_winner.round_wins += 1
		if round_winner.round_wins >= config.victory_target:
			_set_winner(round_winner_id)
	return round_winner_id


func remove_active_player(player_id: StringName) -> void:
	if not players.has(player_id): return
	var player: PlayerState = players[player_id]
	if not player.active: return
	player.active = false
	player.ready = false
	player.match_score = 0
	player.round_wins = 0
	var remaining := active_player_ids()
	if remaining.size() == 1:
		_set_winner(remaining[0])


func active_player_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for player_id in seat_order:
		if players[player_id].active:
			result.append(player_id)
	return result


func to_dict() -> Dictionary:
	var player_ids: Array = players.keys()
	player_ids.sort()
	var serialized_players: Array = []
	for player_id in player_ids:
		var player: PlayerState = players[player_id]
		var serialized_hand: Array = []
		for card in player.hand: serialized_hand.append(_serialize_full_card(card))
		var ability_ids: Array = []
		for ability in player.ability_hand: ability_ids.append(str(ability.copy_id))
		var modifiers: Array = []
		for modifier in player.score_modifiers:
			modifiers.append({
				"operation": str(modifier.operation), "numerator": modifier.value.numerator,
				"denominator": modifier.value.denominator, "source_id": str(modifier.source_id),
			})
		var completed_manipulations: Array = []
		for ability_id in player.completed_manipulation_ids:
			completed_manipulations.append(str(ability_id))
		serialized_players.append({
			"player_id": str(player.player_id), "seat_index": player.seat_index,
			"spectator": player.spectator, "active": player.active, "pending": player.pending,
			"connected": player.connected, "ready": player.ready, "hand": serialized_hand,
			"ability_hand": ability_ids, "match_score": player.match_score,
			"round_wins": player.round_wins, "replenishment_needed": player.replenishment_needed,
			"score_modifiers": modifiers,
			"pending_manipulation": player.pending_manipulation.duplicate(true),
			"staged_submission": player.staged_submission.duplicate(true),
			"has_staged_submission": player.has_staged_submission,
			"hand_locked": player.hand_locked,
			"submitted_card_ids": player.submitted_cards.map(func(card: FullCardState): return str(card.card_id)),
			"completed_manipulation_ids": completed_manipulations,
			"finalized_score": player.finalized_score,
			"end_discard_complete": player.end_discard_complete,
			"activation_round": player.activation_round,
			"disconnect_deadline_msec": player.disconnect_deadline_msec,
			"reconnect_token": player.reconnect_token,
		})
	var serialized_piles := {}
	for context in piles:
		var pile: ContextPile = piles[context]
		serialized_piles[str(context)] = {
			"draw": _serialize_halves(pile.snapshot_draw_cards()),
			"used": _serialize_halves(pile.snapshot_used_cards()),
		}
	var seats: Array = []
	for id in seat_order: seats.append(str(id))
	return {
		"config": config.to_dict(), "seed": seed, "rng_state": rng.state_token(),
		"piles": serialized_piles, "ability_deck": ability_deck.to_dict(),
		"players": serialized_players, "seat_order": seats, "round_number": round_number,
		"active_context": active_context, "context_direction": context_direction, "phase": phase,
		"winner_id": str(winner_id), "match_complete": match_complete,
		"start_ability_drawn_round": start_ability_drawn_round,
		"start_prepared_round": start_prepared_round,
		"phase_started_msec": phase_started_msec, "phase_deadline_msec": phase_deadline_msec,
		"reaction_deadline_msec": reaction_deadline_msec,
		"last_round_winner_id": str(last_round_winner_id),
		"host_player_id": str(host_player_id), "frozen": frozen,
		"freeze_started_msec": freeze_started_msec,
	}


static func from_dict(data: Dictionary) -> MatchState:
	var state := _new_state()
	state.config = MatchConfig.from_dict(data.config)
	state.seed = data.seed
	state.rng = RandomSource.new(state.seed)
	state.rng.restore_state_token(data.rng_state)
	for context_key: String in data.piles:
		var context := int(context_key)
		var pile_data: Dictionary = data.piles[context_key]
		var draw_cards := state._deserialize_halves(pile_data.draw)
		var pile := ContextPile.new(context, draw_cards)
		for used in state._deserialize_halves(pile_data.used): pile.discard(used)
		state.piles[context] = pile
	state.ability_deck = AbilityDeckState.new([])
	state.ability_deck.load_dict(data.ability_deck)
	for id: String in data.seat_order: state.seat_order.append(StringName(id))
	for player_data: Dictionary in data.players:
		var player := PlayerState.new(
			StringName(player_data.player_id), player_data.seat_index, player_data.spectator
		)
		player.active = player_data.active
		player.pending = player_data.pending
		player.connected = player_data.connected
		player.ready = player_data.ready
		for card_data: Dictionary in player_data.hand:
			player.hand.append(state._deserialize_full_card(card_data))
		for copy_id: String in player_data.ability_hand:
			player.ability_hand.append(state.ability_deck.card_by_id(StringName(copy_id)))
		player.match_score = player_data.match_score
		player.round_wins = player_data.round_wins
		player.replenishment_needed = player_data.replenishment_needed
		for modifier_data: Dictionary in player_data.get("score_modifiers", []):
			player.score_modifiers.append(ScoringTypes.ScoreModifier.new(
				StringName(modifier_data.operation),
				Rational.new(modifier_data.numerator, modifier_data.denominator),
				StringName(modifier_data.source_id)
			))
		player.pending_manipulation = player_data.get("pending_manipulation", {}).duplicate(true)
		player.staged_submission.assign(player_data.get("staged_submission", []))
		player.has_staged_submission = player_data.get("has_staged_submission", false)
		player.hand_locked = player_data.get("hand_locked", false)
		for submitted_id: String in player_data.get("submitted_card_ids", []):
			for card in player.hand:
				if card.card_id == StringName(submitted_id):
					player.submitted_cards.append(card)
					break
		for ability_id: String in player_data.get("completed_manipulation_ids", []):
			player.completed_manipulation_ids.append(StringName(ability_id))
		player.finalized_score = player_data.get("finalized_score", 0)
		player.end_discard_complete = player_data.get("end_discard_complete", false)
		player.activation_round = player_data.get("activation_round", 0)
		player.disconnect_deadline_msec = player_data.get("disconnect_deadline_msec", -1)
		player.reconnect_token = player_data.get("reconnect_token", "")
		state.players[player.player_id] = player
	state.round_number = data.round_number
	state.active_context = data.active_context
	state.context_direction = data.context_direction
	state.phase = data.phase
	state.winner_id = StringName(data.winner_id)
	state.match_complete = data.match_complete
	state.start_ability_drawn_round = data.start_ability_drawn_round
	state.start_prepared_round = data.get("start_prepared_round", 0)
	state.phase_started_msec = data.get("phase_started_msec", -1)
	state.phase_deadline_msec = data.get("phase_deadline_msec", -1)
	state.reaction_deadline_msec = data.get("reaction_deadline_msec", -1)
	state.last_round_winner_id = StringName(data.get("last_round_winner_id", ""))
	state.host_player_id = StringName(data.get("host_player_id", ""))
	state.frozen = data.get("frozen", false)
	state.freeze_started_msec = data.get("freeze_started_msec", -1)
	return state


func _build_piles() -> Dictionary:
	var result := {}
	for context in range(GameTypes.Context.A, GameTypes.Context.C + 1):
		var cards: Array[HalfCardState] = []
		for rank in range(1, 11):
			for suit in range(GameTypes.Suit.ONE, GameTypes.Suit.THREE + 1):
				for copy_index in range(3):
					cards.append(HalfCardState.new(
						StringName("%d-%d-%d-%d" % [context, rank, suit, copy_index]),
						context, rank, suit
					))
		var shuffled: Array[HalfCardState] = []
		shuffled.assign(rng.shuffle(cards))
		result[context] = ContextPile.new(context, shuffled)
	return result


func _set_winner(player_id: StringName) -> void:
	winner_id = player_id
	match_complete = true
	phase = GameTypes.Phase.COMPLETE


static func _new_state() -> MatchState:
	var script: Script = load("res://src/core/match/match_state.gd")
	var state: MatchState = script.new()
	return state


func _serialize_half(card: HalfCardState) -> Dictionary:
	return {
		"copy_id": str(card.copy_id), "base_context": card.base_context,
		"base_rank": card.base_rank, "base_suit": card.base_suit,
		"effective_context": card.effective_context(), "effective_rank": card.effective_rank(),
		"effective_suit": card.effective_suit(),
	}


func _serialize_halves(cards: Array[HalfCardState]) -> Array:
	var result: Array = []
	for card in cards: result.append(_serialize_half(card))
	return result


func _deserialize_halves(items: Array) -> Array[HalfCardState]:
	var result: Array[HalfCardState] = []
	for data: Dictionary in items: result.append(_deserialize_half(data))
	return result


func _deserialize_half(data: Dictionary) -> HalfCardState:
	var card := HalfCardState.new(
		StringName(data.copy_id), data.base_context, data.base_rank, data.base_suit
	)
	if (
		data.effective_context != data.base_context or data.effective_rank != data.base_rank
		or data.effective_suit != data.base_suit
	):
		card.apply_overrides(data.effective_context, data.effective_rank, data.effective_suit)
	return card


func _serialize_full_card(card: FullCardState) -> Dictionary:
	return {"card_id": str(card.card_id), "first": _serialize_half(card.first), "second": _serialize_half(card.second)}


func _deserialize_full_card(data: Dictionary) -> FullCardState:
	return FullCardState.new(
		StringName(data.card_id), _deserialize_half(data.first), _deserialize_half(data.second)
	)
