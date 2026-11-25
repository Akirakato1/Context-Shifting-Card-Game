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
	var pile_counts := {}
	for context in state.piles:
		pile_counts[str(context)] = {
			"draw_count": state.piles[context].draw_count(),
			"capacity": MatchState.CONTEXT_PILE_CAPACITY,
		}
	var ability_pile_count := {
		"draw_count": state.ability_deck.draw_count(),
		"capacity": state.ability_deck.capacity(),
	}
	if role == GameTypes.RecipientRole.HOST:
		var host_snapshot := state.to_dict()
		host_snapshot["active_contexts"] = Array(active_contexts)
		host_snapshot["active_fields"] = projected_fields
		host_snapshot["pile_counts"] = pile_counts
		host_snapshot["ability_pile_count"] = ability_pile_count
		return host_snapshot
	var can_watch_hands: bool = (
		role == GameTypes.RecipientRole.SPECTATOR
		and state.players.has(recipient_id)
		and state.players[recipient_id].spectator
		and state.phase in [
			GameTypes.Phase.START, GameTypes.Phase.MAIN_1,
			GameTypes.Phase.HAND_PLAY, GameTypes.Phase.MAIN_2,
		]
	)
	var players: Array = []
	var active_score_modifiers: Array = []
	var player_ids := state.ordered_player_ids()
	for player_id in player_ids:
		var player = state.players[player_id]
		var projected_player := {
			"player_id": str(player.player_id), "seat_index": player.seat_index,
			"avatar_id": player.avatar_id if not player.avatar_id.is_empty() else GameTypes.default_avatar_id(player.seat_index),
			"spectator": player.spectator, "active": player.active, "pending": player.pending,
			"connected": player.connected,
			"hand_count": player.hand.size() - (player.submitted_cards.size() if player.submission_revealed else 0),
			"ability_count": player.ability_hand.size(), "match_score": player.match_score,
			"round_wins": player.round_wins, "ready": player.ready,
		}
		if state.phase == GameTypes.Phase.END and player.active and not player.pending:
			projected_player["discard_complete"] = player.end_discard_complete
		if (
			player.submission_revealed
			and player.locked_normal != null
			and player.locked_context != null
		):
			projected_player["revealed_submission"] = _revealed_submission(player)
		if can_watch_hands and player.active and not player.pending:
			projected_player["spectator_hand"] = _spectator_hand(player)
		players.append(projected_player)
		# Played score modifiers are public. The projection omits the consumed copy ID.
		if player.active and not player.pending:
			for modifier in player.factor_modifiers:
				var projected_modifier := _project_modifier(modifier)
				projected_modifier["target_player_id"] = str(player_id)
				active_score_modifiers.append(projected_modifier)
	var snapshot := {
		"round_number": state.round_number, "phase": state.phase,
		"active_context": state.active_context, "context_direction": state.context_direction,
		"active_contexts": Array(active_contexts),
		"players": players, "active_fields": projected_fields, "frozen": state.frozen,
		"active_score_modifiers": active_score_modifiers,
		"pile_counts": pile_counts, "ability_pile_count": ability_pile_count,
		"match_complete": state.match_complete, "winner_id": str(state.winner_id),
		"end_reason": state.end_reason,
		"last_round_winner_id": str(state.last_round_winner_id),
		"phase_started_msec": state.phase_started_msec,
		"phase_deadline_msec": state.phase_deadline_msec,
		"reaction_deadline_msec": state.reaction_deadline_msec,
		"public_history": state.public_history.duplicate(true),
	}
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
		# The submitted cards stay reserved until End discards them into their piles.
		var available_hand: Array = recipient.hand.filter(func(card): return card not in recipient.submitted_cards)
		snapshot["private_hand"] = _private_hand(
			available_hand, active_contexts, recipient.submission_locked_card_ids
		)
		var available_abilities: Array = recipient.ability_hand.filter(
			func(ability): return ability.copy_id not in recipient.end_discard_copy_ids
		)
		snapshot["private_abilities_disabled"] = recipient.abilities_disabled
		snapshot["private_abilities"] = _private_abilities(available_abilities, state.phase, recipient.abilities_disabled)
		var modifiers: Array = []
		for modifier in recipient.factor_modifiers:
			modifiers.append(_project_modifier(modifier))
		snapshot["private_score_modifiers"] = modifiers
		snapshot["required_ability_discards"] = (
			maxi(recipient.ability_hand.size() - state.ability_deck.end_hand_limit, 0)
			if state.phase == GameTypes.Phase.END and not recipient.end_discard_complete else 0
		)
		snapshot["private_staging"] = {
			"pending_manipulation": recipient.pending_manipulation.duplicate(true),
			"completed_manipulation_ids": completed_manipulations,
			"staged_submission": recipient.staged_submission.duplicate(true),
			"hand_locked": recipient.hand_locked,
		}
		if recipient.deadline_submission is Array:
			snapshot["private_staging"]["deadline_submission"] = recipient.deadline_submission.duplicate(true)
		if recipient.hand_locked and recipient.provisional_score != null:
			snapshot["private_staging"]["submitted_score"] = score_breakdown(
				recipient.provisional_score, recipient.submitted_faces
			)
		snapshot["private_connection"] = {
			"reconnect_token": recipient.reconnect_token,
			"disconnect_deadline_msec": recipient.disconnect_deadline_msec,
		}
	return snapshot


static func _active_fields(state: MatchState) -> Array:
	var result: Array = []
	for field in state.ability_deck.active_fields():
		var parameters: Dictionary = field.ability.definition.effect_parameters
		var projected := {
			"ability_id": str(field.ability.definition.id),
			"source_player_id": str(field.source_player_id),
			"remaining_rounds": field.remaining_rounds,
			"persistent": field.is_persistent(),
		}
		if parameters.has("field_rule"):
			parameters["field_rule"] = str(parameters.field_rule)
			projected["effect_parameters"] = parameters
		result.append(projected)
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
		result["score_breakdown"] = score_breakdown(player.provisional_score)
	return result


static func _spectator_hand(player) -> Array:
	var result: Array = []
	for index in player.hand.size():
		var card = player.hand[index]
		if player.submission_revealed and card in player.submitted_cards:
			continue
		result.append({
			"view_id": "%d-%d" % [player.seat_index, index],
			"first": _spectator_half(card.first),
			"second": _spectator_half(card.second),
		})
	return result


static func _spectator_half(half) -> Dictionary:
	return {
		"effective_context": half.effective_context(),
		"effective_rank": half.effective_rank(),
		"effective_suit": half.effective_suit(),
		"kind": half.effective_kind(),
	}


static func score_breakdown(value, selected_faces: Array = []) -> Dictionary:
	var base_components: Array = []
	for face in selected_faces:
		base_components.append({"rank": face.rank, "suit": face.suit, "joker": face.is_joker})
	var card_components: Array = []
	for component in value.card_hand_components: card_components.append(_public_component(component))
	var context_components: Array = []
	for component in value.context_hand_components: context_components.append(_public_component(component))
	var field_components: Array = []
	for component in value.field_components: field_components.append(_public_component(component))
	var modifiers: Array = []
	for modifier in value.applied_modifiers:
		modifiers.append(_project_modifier(modifier))
	return {
		"base_value": value.base_value,
		"base_components": base_components,
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


static func _project_modifier(modifier) -> Dictionary:
	return {"factor_id": str(modifier.factor_id), "category_id": str(modifier.category_id),
		"delta": _public_rational(modifier.delta), "source_definition_id": str(modifier.source_definition_id)}


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
	var face := {
		"copy_id": str(half.copy_id), "base_context": half.base_context,
		"base_rank": half.base_rank, "base_suit": half.base_suit, "kind": half.effective_kind(),
		"effective_context": half.effective_context(), "effective_rank": half.effective_rank(),
		"effective_suit": half.effective_suit(),
	}
	if half.is_joker() and half.joker_suit >= 0:
		face["joker_context"] = half.joker_context
		face["joker_suit"] = half.joker_suit
		face["joker_rank"] = half.joker_rank
	return face


static func _private_abilities(abilities: Array, phase: int, disabled: bool) -> Array:
	var result: Array = []
	for ability in abilities:
		result.append({
			"copy_id": str(ability.copy_id), "ability_id": str(ability.definition.id),
			"legal": not disabled and ability.definition.allows_phase(phase),
		})
	return result
