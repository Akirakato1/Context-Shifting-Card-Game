extends RefCounted


static func can_watch(state: MatchState, player_id: StringName) -> bool:
	var player: PlayerState = state.players.get(player_id)
	return player != null and player.spectator and player.connected


static func view_id(id: Variant) -> String:
	return str(id).sha256_text().left(20)


static func is_current(state: MatchState, view: Dictionary) -> bool:
	return view.get("round_number") == state.round_number and view.get("phase") == state.phase


static func from_player(state: MatchState, player_id: StringName, payload: Dictionary) -> Dictionary:
	var player: PlayerState = state.players.get(player_id)
	if (
		player == null or not player.active or player.pending or player.spectator or not player.connected
		or not state.config.match_started or state.match_complete or not is_current(state, payload)
	):
		return {}
	var cards := {}
	for card in player.hand:
		cards[str(card.card_id)] = card
	var abilities := {}
	for ability in player.ability_hand:
		abilities[str(ability.copy_id)] = ability
	var focused := ""
	var raw_focus: Variant = payload.get("focus", "")
	if raw_focus is String or raw_focus is StringName:
		var focus: AbilityState = abilities.get(str(raw_focus))
		if focus != null and not player.abilities_disabled and focus.definition.allows_phase(state.phase):
			focused = view_id(focus.copy_id)
	var sort: Variant = payload.get("sort_context", -1)
	return {
		"round_number": state.round_number, "phase": state.phase,
		"hand_order": _ids(payload.get("hand_order"), cards, 6),
		"flipped": _ids(payload.get("flipped"), cards, 6),
		"ability_order": _ids(payload.get("ability_order"), abilities, 5),
		"staged": selections(payload.get("staged"), cards) if state.phase == GameTypes.Phase.HAND_PLAY else [],
		"mimics": selections(payload.get("mimics"), cards),
		"sort_context": clampi(sort, -1, 2) if sort is int else -1,
		"rank_ascending": payload.get("rank_ascending", true) == true,
		"focus": focused,
		"targeting": not focused.is_empty() and payload.get("targeting") == true,
	}


static func selections(entries: Variant, cards: Dictionary) -> Array:
	var result: Array = []
	if not entries is Array:
		return result
	var seen := {}
	for entry in entries.slice(0, 6):
		if not entry is Dictionary or not entry.get("half_index") is int:
			continue
		var original: Variant = entry.get("card_id")
		if not (original is String or original is StringName):
			continue
		var id := str(original)
		var card: FullCardState = cards.get(id)
		if card == null or seen.has(id) or int(entry.half_index) not in [0, 1]:
			continue
		seen[id] = true
		var mimics: Array = []
		var choices: Variant = entry.get("joker_choices")
		if choices is Array:
			for choice in choices.slice(0, 2):
				if not choice is Dictionary:
					continue
				var half: Variant = choice.get("half_index")
				var context: Variant = choice.get("context")
				var suit: Variant = choice.get("suit")
				var rank: Variant = choice.get("rank", 0)
				if (
					half is int and half in [0, 1] and card.half_at(half).is_joker()
					and HalfCardState.joker_choice_error(context, suit, rank).is_empty()
				):
					mimics.append({"half_index": half, "context": context, "suit": suit, "rank": rank})
		result.append({"view_id": view_id(id), "half_index": entry.half_index, "mimics": mimics})
	return result


static func _ids(values: Variant, allowed: Dictionary, maximum: int) -> Array:
	var result: Array = []
	if values is Array:
		for value in values.slice(0, maximum):
			if (value is String or value is StringName) and allowed.has(str(value)):
				var alias := view_id(value)
				if alias not in result:
					result.append(alias)
	return result


static func action_payload(source: Dictionary) -> Dictionary:
	var result := {}
	for key in ["ability_id", "source_player_id", "target_player_id", "success",
		"changed", "locked", "no_eligible_half", "draw_context_counts"]:
		if source.has(key):
			result[key] = source[key]
	for key in ["replacement_card_ids", "card_ids"]:
		if source.has(key):
			result[key] = source[key].map(view_id)
	if source.has("card_changes"):
		var changes: Array = []
		for entry: Dictionary in source.card_changes:
			var change := {"before": entry.get("before", {}), "after": entry.get("after", {})}
			if entry.has("card_id"):
				change["card_id"] = view_id(entry.card_id)
			if entry.has("half_index"):
				change["half_index"] = entry.half_index
			changes.append(change)
		result["card_changes"] = changes
	return result
