extends RefCounted


static func players(snapshot: Dictionary) -> Array:
	if snapshot.get("local_role") != "spectator":
		return []
	return snapshot.get("players", []).filter(func(row: Dictionary) -> bool:
		return row.has("spectator_abilities") and bool(row.get("connected", true))
	)


static func project(snapshot: Dictionary, player: Dictionary, view: Dictionary) -> Dictionary:
	var model := snapshot.duplicate()
	var player_id := str(player.player_id)
	var authority: Dictionary = player.get("spectator_staging", {})
	var locked := bool(authority.get("locked", false))
	var observed_staging: Array = authority.get("selections", [])
	if not locked and view.has("staged"):
		observed_staging = view.staged
	var staged: Array = []
	var staged_ids := {}
	for selection: Dictionary in observed_staging:
		var id := str(selection.view_id)
		staged_ids[id] = true
		staged.append({
			"card_id": id, "half_index": selection.half_index, "joker_choices": selection.get("mimics", []),
		})
	var mimics := {}
	for entry: Dictionary in view.get("mimics", []):
		mimics[entry.view_id] = entry.get("mimics", [])
	for entry: Dictionary in observed_staging:
		if not mimics.has(entry.view_id):
			mimics[entry.view_id] = entry.get("mimics", [])
	var hand: Array = []
	for card: Dictionary in player.get("spectator_hand", []):
		var id := str(card.view_id)
		if locked and (staged_ids.has(id) or bool(card.get("locked", false))):
			continue
		var visible_card := card.duplicate(true)
		visible_card["card_id"] = id
		for index in 2:
			var half: Dictionary = visible_card.first if index == 0 else visible_card.second
			var choice: Dictionary = half.get("mimic", {})
			for draft: Dictionary in mimics.get(id, []):
				if int(draft.half_index) == index:
					choice = draft
					break
			if not choice.is_empty():
				half["joker_context"] = choice.context
				half["joker_suit"] = choice.suit
				half["joker_rank"] = choice.rank
		hand.append(visible_card)
	var abilities: Array = []
	var focus := str(view.get("focus", authority.get("active_ability", "")))
	var focused_ability := {}
	for reference: Dictionary in player.get("spectator_abilities", []):
		var ability := reference.duplicate()
		ability["copy_id"] = str(reference.view_id)
		abilities.append(ability)
		if ability.copy_id == focus:
			focused_ability = snapshot.get("ability_catalog", {}).get(str(ability.ability_id), {})
	var modifiers: Array = snapshot.get("active_score_modifiers", []).filter(func(modifier: Dictionary) -> bool:
		return modifier.get("target_player_id") == player_id
	)
	model.merge({
		"watching": true, "private_player_id": player_id, "private_hand": hand,
		"private_staging": {
			"hand_locked": locked, "staged_submission": staged, "submitted_score": authority.get("score", {}),
		},
		"private_abilities": abilities, "required_ability_discards": 0,
		"required_half_count": maxi(0, 6 - hand.size()) * 2,
		"private_abilities_disabled": player.get("spectator_abilities_disabled", false),
		"private_score_modifiers": modifiers,
		"watch_layout": view, "watch_focus": focus, "watch_ability": focused_ability,
	}, true)
	return model
