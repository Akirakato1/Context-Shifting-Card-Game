class_name SnapshotProjector
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const MatchState = preload("res://src/core/match/match_state.gd")


static func for_recipient(
	state: MatchState,
	recipient_id: StringName,
	role: int
) -> Dictionary:
	if role == GameTypes.RecipientRole.HOST:
		return state.to_dict()
	var players: Array = []
	var player_ids: Array = state.players.keys()
	player_ids.sort()
	for player_id in player_ids:
		var player = state.players[player_id]
		var projected_player := {
			"player_id": str(player.player_id), "seat_index": player.seat_index,
			"spectator": player.spectator, "active": player.active, "pending": player.pending,
			"connected": player.connected, "hand_count": player.hand.size(),
			"ability_count": player.ability_hand.size(), "match_score": player.match_score,
			"round_wins": player.round_wins, "ready": player.ready,
		}
		if player.locked_normal != null and player.locked_context != null:
			projected_player["revealed_submission"] = _revealed_submission(player)
		players.append(projected_player)
	var active_fields: Array = []
	for field in state.ability_deck.active_fields():
		active_fields.append({
			"ability_id": str(field.ability.definition.id),
			"source_player_id": str(field.source_player_id),
			"remaining_rounds": field.remaining_rounds,
		})
	var snapshot := {
		"round_number": state.round_number, "phase": state.phase,
		"active_context": state.active_context, "context_direction": state.context_direction,
		"players": players, "active_fields": active_fields, "frozen": state.frozen,
		"match_complete": state.match_complete, "winner_id": str(state.winner_id),
		"last_round_winner_id": str(state.last_round_winner_id),
		"phase_started_msec": state.phase_started_msec,
		"phase_deadline_msec": state.phase_deadline_msec,
		"reaction_deadline_msec": state.reaction_deadline_msec,
	}
	if state.config.information_visibility == GameTypes.InformationVisibility.PUBLIC:
		var pile_counts := {}
		for context in state.piles:
			pile_counts[str(context)] = {
				"draw_count": state.piles[context].draw_count(),
				"used_count": state.piles[context].used_count(),
			}
		snapshot["pile_counts"] = pile_counts
	if (
		role == GameTypes.RecipientRole.ACTIVE_PLAYER
		and state.players.has(recipient_id)
		and state.players[recipient_id].active
		and not state.players[recipient_id].pending
	):
		var recipient = state.players[recipient_id]
		snapshot["private_player_id"] = str(recipient_id)
		snapshot["private_hand"] = _private_hand(recipient.hand)
		snapshot["private_abilities"] = _private_abilities(recipient.ability_hand)
		snapshot["private_staging"] = {
			"pending_manipulation": recipient.pending_manipulation.duplicate(true),
			"staged_submission": recipient.staged_submission.duplicate(true),
			"hand_locked": recipient.hand_locked,
		}
	return snapshot


static func _revealed_submission(player) -> Dictionary:
	var result := {
		"cards": player.submitted_card_views.duplicate(true),
		"normal_category": str(player.locked_normal.category_id),
		"context_category": str(player.locked_context.category_id),
		"finalized_score": player.finalized_score,
	}
	if player.provisional_score != null:
		result["base_value"] = player.provisional_score.base_value
		result["provisional_score"] = player.provisional_score.final_score
	return result

static func _private_hand(hand: Array) -> Array:
	var result: Array = []
	for card in hand:
		result.append({
			"card_id": str(card.card_id),
			"first": _private_half(card.first), "second": _private_half(card.second),
		})
	return result


static func _private_half(half) -> Dictionary:
	return {
		"copy_id": str(half.copy_id), "base_context": half.base_context,
		"base_rank": half.base_rank, "base_suit": half.base_suit, "kind": half.kind,
		"effective_context": half.effective_context(), "effective_rank": half.effective_rank(),
		"effective_suit": half.effective_suit(),
	}


static func _private_abilities(abilities: Array) -> Array:
	var result: Array = []
	for ability in abilities:
		result.append({
			"copy_id": str(ability.copy_id), "ability_id": str(ability.definition.id),
		})
	return result
