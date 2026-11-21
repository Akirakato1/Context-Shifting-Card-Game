extends Control

@onready var _table = $MatchScreen


func _ready() -> void:
	_table.render(_fixture_model())
	_capture_if_requested.call_deferred()


func _capture_if_requested() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--dump-layout":
			await get_tree().process_frame
			for path in ["Header", "TableLayer/TopSeat", "Center", "PhaseControls", "AbilityPanel/ToggleButton"]:
				var control: Control = _table.get_node(path)
				print("UI_LAYOUT %s %s visible=%s" % [path, control.get_global_rect(), control.visible])
			get_tree().quit()
			return
		if not argument.begins_with("--capture-ui="):
			continue
		var output_path := argument.trim_prefix("--capture-ui=")
		await get_tree().process_frame
		await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		if image == null:
			push_error("The active renderer did not provide a viewport image")
			get_tree().quit(1)
			return
		var error := image.save_png(output_path)
		if error != OK:
			push_error("Could not save UI fixture capture to %s" % output_path)
		get_tree().quit(0 if error == OK else 1)


func _fixture_model() -> Dictionary:
	var hand: Array = [
		_card("c1", _half(0, 7, 0), _half(1, 4, 2)),
		_card("c2", _half(0, 2, 1), _half(0, 8, 0)),
		_card("c3", _half(1, 5, 2), _half(2, 1, 0)),
		_card("c4", _joker(), _half(0, 9, 1)),
		_card("c5", _half(0, 6, 0), _half(2, 10, 1)),
		_card("c6", _half(0, 4, 2), _half(1, 7, 1)),
	]
	return {
		"phase": 3, "round_number": 4, "active_context": 0, "context_direction": 1,
		"phase_deadline_msec": 30000, "now_msec": 12400, "reaction_deadline_msec": -1,
		"private_player_id": "p1", "private_hand": hand,
		"private_abilities": [
			{"copy_id": "a1", "ability_id": "mirror_rank"},
			{"copy_id": "a2", "ability_id": "pair_boost"},
			{"copy_id": "a3", "ability_id": "reverse_clock"},
		],
		"ability_catalog": {
			"mirror_rank": {
				"label": "Mirror Rank", "rules_text": "Select 1 full card. Mirror both ranks: 1↔10 through 5↔6.",
				"timing": 0, "choice_schema": {"steps": [
				{"key": "cards", "kind": "full_card", "count": 1, "prompt": "Select 1 full card"},
			]}},
			"pair_boost": {"label": "Pair Boost", "rules_text": "Fixture buff.", "timing": 2, "choice_schema": {}},
			"reverse_clock": {"label": "Reverse Clock", "rules_text": "Fixture field.", "timing": 1, "choice_schema": {}},
		},
		"private_staging": {"pending_manipulation": {}, "completed_manipulation_ids": [], "staged_submission": [], "hand_locked": false},
		"players": [
			_player("p1", "Mira", 0, 36, 2, 6, false),
			_player("p2", "North Star", 1, 24, 1, 6, true),
			_player("p3", "West Wind", 2, 18, 1, 5, false),
			_player("p4", "East Light", 3, 12, 0, 6, false),
			{"player_id": "s1", "name": "Watcher", "seat_index": -1, "spectator": true, "active": false, "connected": true},
		],
		"active_fields": [
			{"ability_id": "slow_clock", "source_player_id": "p3", "remaining_rounds": 2},
		],
		"recent_public_abilities": [
			{"ability_id": "pair_breaker", "source_player_id": "p2", "target_player_id": "p1"},
		],
		"frozen": false, "victory_mode": 0, "victory_target": 100,
		"pile_counts": {"0": {"draw_count": 68}, "1": {"draw_count": 71}, "2": {"draw_count": 65}},
		"submission_preview": {
			"valid": true, "base_value": 0, "normal_category": "Pass",
			"normal_multiplier": "×1", "context_category": "No Context Pattern",
			"context_multiplier": "×1", "projected_score": 0,
		},
	}


func _player(
	id: String, display_name: String, seat: int, score: int,
	wins: int, hand_count: int, ready: bool
) -> Dictionary:
	return {
		"player_id": id, "name": display_name, "seat_index": seat,
		"spectator": false, "active": true, "pending": false,
		"connected": true, "ready": ready, "hand_count": hand_count,
		"ability_count": 2, "match_score": score, "round_wins": wins,
	}


func _card(id: String, first: Dictionary, second: Dictionary) -> Dictionary:
	return {"card_id": id, "first": first, "second": second}


func _half(context: int, rank: int, suit: int) -> Dictionary:
	return {"effective_context": context, "effective_rank": rank, "effective_suit": suit, "kind": 0}


func _joker() -> Dictionary:
	return {"effective_context": 0, "effective_rank": 0, "effective_suit": -1, "kind": 1}
