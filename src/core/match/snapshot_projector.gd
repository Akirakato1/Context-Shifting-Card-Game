class_name SnapshotProjector
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const FieldEffectResolver = preload("res://src/core/abilities/field_effect_resolver.gd")


static func for_recipient(
	state: MatchState,
	recipient_id: StringName,
	role: int
) -> Dictionary:
	var active_contexts := FieldEffectResolver.active_contexts(
		state.active_context, state.ability_deck.active_fields()
	)
	var projected_fields := _active_fields(state)
	if role == GameTypes.RecipientRole.HOST:
		var host_snapshot := state.to_dict()
		host_snapshot["active_contexts"] = Array(active_contexts)
		host_snapshot["active_fields"] = projected_fields
		return host_snapshot
	var players: Array = []
	var player_ids := state.ordered_player_ids()
	for player_id in player_ids:
		var player = state.players[player_id]
		var projected_player := {
			"player_id": str(player.player_id), "seat_index": player.seat_index,
			"spectator": player.spectator, "active": player.active, "pending": player.pending,
			"connected": player.connected, "hand_count": player.hand.size(),
			"ability_count": player.ability_hand.size(), "match_score": player.match_score,
			"round_wins": player.round_wins, "ready": player.ready,
		}
		if (
			player.submission_revealed
			and player.locked_normal != null
			and player.locked_context != null
		):
			projected_player["revealed_submission"] = _revealed_submission(player)
		players.append(projected_player)
	var snapshot := {
		"round_number": state.round_number, "phase": state.phase,
		"active_context": state.active_context, "context_direction": state.context_direction,
		"active_contexts": Array(active_contexts),
		"players": players, "active_fields": projected_fields, "frozen": state.frozen,
		"match_complete": state.match_complete, "winner_id": str(state.winner_id),
		"last_round_winner_id": str(state.last_round_winner_id),
		"phase_started_msec": state.phase_started_msec,
		"phase_deadline_msec": state.phase_deadline_msec,
		"reaction_deadline_msec": state.reaction_deadline_msec,
		"public_history": state.public_history.duplicate(true),
	}
	var pile_counts := {}
	for context in state.piles:
		pile_counts[str(context)] = {
			"draw_count": state.piles[context].draw_count(),
		}
	snapshot["pile_counts"] = pile_counts
	if state.config.information_visibility == GameTypes.InformationVisibility.PUBLIC:
		var replacement_requests := {}
		for player_id in state.start_requests:
			var request := {}
			for context in state.start_requests[player_id]:
				request[str(context)] = state.start_requests[player_id][context]
			replacement_requests[str(player_id)] = request
		snapshot["replacement_requests"] = replacement_requests
	if (
		role == GameTypes.RecipientRole.ACTIVE_PLAYER
		and state.players.has(recipient_id)
		and state.players[recipient_id].active
		and not state.players[recipient_id].pending
	):
		var recipient = state.players[recipient_id]
		var completed_manipulations: Array = []
		for ability_id in recipient.completed_manipulation_ids:
			completed_manipulations.append(str(ability_id))
		snapshot["private_player_id"] = str(recipient_id)
		snapshot["private_hand"] = _private_hand(
			recipient.hand, active_contexts, recipient.submission_locked_card_ids
		)
		snapshot["private_abilities"] = _private_abilities(
			recipient.ability_hand, state.phase
		)
		snapshot["required_ability_discards"] = (
			maxi(recipient.ability_hand.size() - state.ability_deck.end_hand_limit, 0)
			if state.phase == GameTypes.Phase.END else 0
		)
		snapshot["private_staging"] = {
			"pending_manipulation": recipient.pending_manipulation.duplicate(true),
			"completed_manipulation_ids": completed_manipulations,
			"staged_submission": recipient.staged_submission.duplicate(true),
			"hand_locked": recipient.hand_locked,
		}
		snapshot["private_connection"] = {
			"reconnect_token": recipient.reconnect_token,
			"disconnect_deadline_msec": recipient.disconnect_deadline_msec,
		}
	return snapshot


static func _active_fields(state: MatchState) -> Array:
	var result: Array = []
	for field in state.ability_deck.active_fields():
		result.append({
			"ability_id": str(field.ability.definition.id),
			"source_player_id": str(field.source_player_id),
			"remaining_rounds": field.remaining_rounds,
			"persistent": field.is_persistent(),
		})
	return result


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
		result["score_breakdown"] = _public_score_breakdown(player.provisional_score)
	return result


static func _public_score_breakdown(value) -> Dictionary:
	var card_components: Array = []
	for component in value.card_hand_components: card_components.append(_public_component(component))
	var context_components: Array = []
	for component in value.context_hand_components: context_components.append(_public_component(component))
	var field_components: Array = []
	for component in value.field_components: field_components.append(_public_component(component))
	var modifiers: Array = []
	for modifier in value.applied_modifiers:
		modifiers.append({"factor_id": str(modifier.factor_id), "category_id": str(modifier.category_id),
			"delta": _public_rational(modifier.delta), "source_definition_id": str(modifier.source_definition_id)})
	return {
		"base_value": value.base_value,
		"card_hand_components": card_components, "context_hand_components": context_components,
		"field_components": field_components, "applied_modifiers": modifiers,
		"card_hand_unclamped": _public_rational(value.card_hand_unclamped),
		"card_hand_factor": _public_rational(value.card_hand_factor),
		"context_hand_unclamped": _public_rational(value.context_hand_unclamped),
		"context_hand_factor": _public_rational(value.context_hand_factor),
		"field_unclamped": _public_rational(value.field_unclamped),
		"field_factor": _public_rational(value.field_factor),
		"raw_score": _public_rational(value.raw_score), "final_score": value.final_score,
	}


static func _public_component(component) -> Dictionary:
	return {"factor_id": str(component.factor_id), "category_id": str(component.category_id),
		"source_definition_id": str(component.source_definition_id), "value": _public_rational(component.value)}


static func _public_rational(value) -> Dictionary:
	return {"numerator": value.numerator, "denominator": value.denominator}

static func _private_hand(
	hand: Array,
	active_contexts: PackedInt32Array,
	locked_card_ids: Array[StringName]
) -> Array:
	var result: Array = []
	for card in hand:
		var eligible_indexes: Array = []
		for half_index in card.eligible_half_indexes_for_contexts(active_contexts):
			eligible_indexes.append(half_index)
		result.append({
			"card_id": str(card.card_id),
			"first": _private_half(card.first), "second": _private_half(card.second),
			"eligible_half_indexes": eligible_indexes,
			"submission_locked": locked_card_ids.has(card.card_id),
		})
	return result


static func _private_half(half) -> Dictionary:
	return {
		"copy_id": str(half.copy_id), "base_context": half.base_context,
		"base_rank": half.base_rank, "base_suit": half.base_suit, "kind": half.kind,
		"effective_context": half.effective_context(), "effective_rank": half.effective_rank(),
		"effective_suit": half.effective_suit(),
	}


static func _private_abilities(abilities: Array, phase: int) -> Array:
	var result: Array = []
	for ability in abilities:
		result.append({
			"copy_id": str(ability.copy_id), "ability_id": str(ability.definition.id),
			"legal": ability.definition.allows_phase(phase),
		})
	return result
