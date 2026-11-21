extends "res://tests/test_case.gd"

const MATCH_SCREEN_PATH := "res://src/view/match/match_screen.tscn"


func test_table_renders_four_fixed_seats_local_hand_and_hidden_opponents() -> void:
	var table = await _mount_match()
	if table == null:
		return
	table.render(_active_player_model())
	assert_eq(table.get_node("Center/ContextClock/Direction").text, "Rise  →  Flourish  →  Fall")
	assert_eq(table.get_node("Center/ContextClock/Active").text, "ACTIVE  Flourish")
	assert_eq(table.get_node("Center/Piles/PileRise/Name").text, "Rise")
	assert_eq(table.get_node("Center/Piles/PileFlourish/Name").text, "Flourish")
	assert_eq(table.get_node("Center/Piles/PileFall/Name").text, "Fall")
	assert_eq(table.get_node("TableLayer/TopSeat").seat_position, &"top")
	assert_eq(table.get_node("TableLayer/LeftSeat").seat_position, &"left")
	assert_eq(table.get_node("TableLayer/RightSeat").seat_position, &"right")
	assert_eq(table.get_node("TableLayer/BottomSeat").seat_position, &"bottom")
	assert_eq(table.get_node("TableLayer/BottomSeat").visible_card_count(), 6)
	assert_eq(table.get_node("TableLayer/LeftSeat").hidden_card_count(), 4)
	assert_eq(table.get_node("TableLayer/TopSeat").hidden_card_count(), 6)
	assert_eq(table.get_node("TableLayer/RightSeat").hidden_card_count(), 5)
	assert_eq(table.get_node("TableLayer/BottomSeat/Info/Name").text, "YOU  ·  Mira")
	assert_eq(table.get_node("TableLayer/TopSeat/Info/Status").text, "READY")
	await _unmount(table)


func test_local_and_revealed_cards_render_effective_faces_and_active_half() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var model := _active_player_model()
	model.players[1]["revealed_submission"] = {
		"cards": [_revealed_card("r1", 2, 9, 1, 0, 4, 2, 1)],
		"normal_category": "pair",
		"context_category": "all_contexts_1",
		"base_value": 18,
		"provisional_score": 27,
		"finalized_score": 31,
	}
	table.render(model)
	var local_card = table.get_node("TableLayer/BottomSeat").card_at(0)
	assert_eq(local_card.first_face_text(), "Rise  7  ONE")
	assert_eq(local_card.second_face_text(), "Flourish  4  THREE")
	assert_eq(local_card.active_half_index, 1)
	var revealed = table.get_node("TableLayer/TopSeat").card_at(0)
	assert_eq(revealed.first_face_text(), "Fall  9  TWO")
	assert_eq(revealed.second_face_text(), "Rise  4  THREE")
	assert_eq(table.get_node("TableLayer/TopSeat/ScoreSummary").text, "Pair  ×  All Contexts ×1   ·   31 pts")
	await _unmount(table)


func test_public_information_shows_piles_requests_and_spectator_has_no_local_hand() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var public_model := _active_player_model()
	public_model["replacement_requests"] = {"p2": {"0": 2, "1": 1, "2": 3}}
	table.render(public_model)
	assert_eq(table.get_node("Center/Piles/PileRise/Count").text, "68 left")
	assert_true(table.get_node("TableLayer/TopSeat/Request").visible)
	assert_eq(table.get_node("TableLayer/TopSeat/Request").text, "DRAW  Rise 2 · Flourish 1 · Fall 3")

	var private_model := _active_player_model()
	private_model.erase("pile_counts")
	private_model.erase("replacement_requests")
	table.render(private_model)
	assert_eq(table.get_node("Center/Piles/PileRise/Count").text, "Hidden")
	assert_false(table.get_node("TableLayer/TopSeat/Request").visible)

	var spectator_model := _active_player_model()
	spectator_model.erase("private_player_id")
	spectator_model.erase("private_hand")
	table.render(spectator_model)
	assert_false(table.get_node("TableLayer/BottomSeat/Hand").visible)
	assert_eq(table.get_node("Header/Spectators").text, "SPECTATORS  2 / 4")
	await _unmount(table)


func test_context_score_progress_fields_and_nil_round_render_clearly() -> void:
	var table = await _mount_match()
	if table == null:
		return
	var model := _active_player_model()
	model["context_direction"] = -1
	model["victory_mode"] = 0
	model["victory_target"] = 100
	model["last_round_nil"] = true
	model["active_fields"] = [
		{"ability_id": "reverse_clock", "source_player_id": "p3", "remaining_rounds": 2},
	]
	model.players[0]["provisional_score"] = {
		"normal_category": "three_kind",
		"context_category": "no_context_pattern",
		"base_value": 21,
		"final_score": 42,
	}
	table.render(model)
	assert_eq(table.get_node("Header/Phase").text, "HAND PLAY")
	assert_eq(table.get_node("Header/Round").text, "ROUND 4")
	assert_eq(table.get_node("Header/Timer").text, "12.4s")
	assert_eq(table.get_node("Center/ContextClock/Direction").text, "Fall  ←  Flourish  ←  Rise")
	assert_eq(table.get_node("Center/ContextClock/Active").text, "ACTIVE  Flourish")
	assert_eq(table.get_node("TableLayer/BottomSeat/ScoreSummary").text, "Three of a Kind  ×  No Context Pattern ×1   ·   42 provisional")
	assert_eq(table.get_node("Header/Progress").text, "SCORE RACE  ·  36 / 100")
	assert_eq(table.get_node("Center/Fields/FieldRows").get_child_count(), 1)
	assert_eq(table.get_node("Center/RoundResult").text, "NIL ROUND  ·  no progress awarded")

	model["victory_mode"] = 1
	model["victory_target"] = 5
	table.render(model)
	assert_eq(table.get_node("Header/Progress").text, "ROUND-WIN RACE  ·  2 / 5")
	await _unmount(table)


func _active_player_model() -> Dictionary:
	return {
		"round_number": 4,
		"phase": 3,
		"active_context": 1,
		"context_direction": 1,
		"phase_deadline_msec": 12400,
		"now_msec": 0,
		"private_player_id": "p1",
		"private_hand": [
			_private_card("c1", 0, 7, 0, 1, 4, 2),
			_private_card("c2", 0, 2, 1, 2, 8, 0),
			_private_card("c3", 0, 5, 2, 1, 1, 0),
			_private_card("c4", 1, 9, 1, 2, 3, 2),
			_private_card("c5", 2, 6, 0, 0, 10, 1),
			_private_card("c6", 1, 4, 2, 2, 7, 1),
		],
		"players": [
			{"player_id": "p1", "name": "Mira", "seat_index": 0, "active": true, "spectator": false, "connected": true, "ready": false, "hand_count": 6, "match_score": 36, "round_wins": 2},
			{"player_id": "p2", "name": "North", "seat_index": 1, "active": true, "spectator": false, "connected": true, "ready": true, "hand_count": 6, "match_score": 18, "round_wins": 1},
			{"player_id": "p3", "name": "West", "seat_index": 2, "active": true, "spectator": false, "connected": true, "ready": false, "hand_count": 4, "match_score": 9, "round_wins": 0},
			{"player_id": "p4", "name": "East", "seat_index": 3, "active": true, "spectator": false, "connected": false, "ready": false, "hand_count": 5, "match_score": 6, "round_wins": 0},
			{"player_id": "s1", "name": "Watcher", "seat_index": -1, "active": false, "spectator": true, "connected": true, "ready": false, "hand_count": 0, "match_score": 0, "round_wins": 0},
			{"player_id": "s2", "name": "Viewer", "seat_index": -1, "active": false, "spectator": true, "connected": true, "ready": false, "hand_count": 0, "match_score": 0, "round_wins": 0},
		],
		"pile_counts": {
			"0": {"draw_count": 68, "used_count": 23},
			"1": {"draw_count": 71, "used_count": 20},
			"2": {"draw_count": 65, "used_count": 26},
		},
		"active_fields": [],
		"victory_mode": 0,
		"victory_target": 100,
	}


func _private_card(
	card_id: String,
	first_context: int,
	first_rank: int,
	first_suit: int,
	second_context: int,
	second_rank: int,
	second_suit: int
) -> Dictionary:
	return {
		"card_id": card_id,
		"first": _half(first_context, first_rank, first_suit),
		"second": _half(second_context, second_rank, second_suit),
	}


func _revealed_card(
	card_id: String,
	first_context: int,
	first_rank: int,
	first_suit: int,
	second_context: int,
	second_rank: int,
	second_suit: int,
	selected_half_index: int
) -> Dictionary:
	return {
		"card_id": card_id,
		"selected_half_index": selected_half_index,
		"halves": [
			{"context": first_context, "rank": first_rank, "suit": first_suit, "joker": false},
			{"context": second_context, "rank": second_rank, "suit": second_suit, "joker": false},
		],
	}


func _half(context: int, rank: int, suit: int) -> Dictionary:
	return {
		"effective_context": context,
		"effective_rank": rank,
		"effective_suit": suit,
		"kind": 0,
	}


func _mount_match() -> Variant:
	if not ResourceLoader.exists(MATCH_SCREEN_PATH):
		assert_true(false, "%s must exist" % MATCH_SCREEN_PATH)
		return null
	var node = load(MATCH_SCREEN_PATH).instantiate()
	Engine.get_main_loop().root.add_child(node)
	await Engine.get_main_loop().process_frame
	return node


func _unmount(node: Node) -> void:
	node.queue_free()
	await Engine.get_main_loop().process_frame
