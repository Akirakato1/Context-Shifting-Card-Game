extends "res://tests/test_case.gd"

const RESULTS_PATH := "res://src/view/results/results_screen.tscn"


func test_results_reports_victory_or_defeat_for_the_local_player() -> void:
	var results = await _mount()
	var model := _result_model()
	model["private_player_id"] = "p1"
	results.render(model)
	assert_eq(results.get_node("Layout/Eyebrow").text, "Victory")
	model["private_player_id"] = "p2"
	results.render(model)
	assert_eq(results.get_node("Layout/Eyebrow").text, "Defeat")
	model.erase("private_player_id")
	results.render(model)
	assert_eq(results.get_node("Layout/Eyebrow").text, "Match Complete")
	await _unmount(results)


func test_normal_winner_nil_note_and_final_standings_render() -> void:
	var results = await _mount()
	if results == null:
		return
	results.render(_result_model())
	assert_eq(results.get_node("Layout/Title").text, "MIRA WINS")
	assert_true(results.get_node("Layout/Summary").text.contains("score race"))
	assert_true(results.get_node("Layout/NilNote").visible)
	assert_true(results.get_node("Layout/NilNote").text.contains("previous round was nil"))
	assert_eq(results.get_node("Layout/Standings").get_child_count(), 4)
	assert_true(results.get_node("Layout/Standings").get_child(0).text.begins_with("1   Mira"))
	assert_eq(results.get_node("Layout/Room").text, "ROOM ABC234  ·  occupants stay together for a rematch")
	assert_true(results.get_node("Layout/Actions/RematchButton").visible)
	await _unmount(results)


func test_last_player_standing_and_host_loss_have_distinct_outcomes() -> void:
	var results = await _mount()
	if results == null:
		return
	var forfeit_model := _result_model()
	forfeit_model["end_reason"] = "last_player_standing"
	results.render(forfeit_model)
	assert_true(results.get_node("Layout/Summary").text.contains("last player standing"))

	var host_loss := _result_model()
	host_loss["winner_id"] = ""
	host_loss["end_reason"] = "host_disconnect"
	results.render(host_loss)
	assert_eq(results.get_node("Layout/Title").text, "MATCH ENDED")
	assert_true(results.get_node("Layout/Summary").text.contains("host disconnected"))
	assert_false(results.get_node("Layout/Actions/RematchButton").visible)
	assert_true(results.get_node("Layout/Actions/MenuButton").visible)
	await _unmount(results)


func test_rematch_and_lobby_actions_emit_once_and_preserve_room_occupants() -> void:
	var results = await _mount()
	if results == null:
		return
	var rematches: Array[Dictionary] = []
	var lobbies: Array[Dictionary] = []
	results.rematch_requested.connect(func(payload: Dictionary): rematches.append(payload))
	results.return_to_lobby_requested.connect(func(payload: Dictionary): lobbies.append(payload))
	results.render(_result_model())
	results.get_node("Layout/Actions/RematchButton").pressed.emit()
	results.get_node("Layout/Actions/RematchButton").pressed.emit()
	assert_eq(rematches.size(), 1)
	assert_eq(rematches[0].room_code, "ABC234")
	assert_eq(rematches[0].occupant_ids, ["p1", "p2", "p3", "p4", "s1"])
	assert_eq(rematches[0].reset_values, {"round_number": 1, "match_scores": 0, "round_wins": 0})
	assert_false(rematches[0].host_settings_unlocked)

	results.render(_result_model())
	results.get_node("Layout/Actions/LobbyButton").pressed.emit()
	assert_eq(lobbies.size(), 1)
	assert_eq(lobbies[0].room_code, "ABC234")
	assert_true(lobbies[0].host_settings_unlocked)
	await _unmount(results)


func test_non_host_sees_waiting_rematch_state() -> void:
	var results = await _mount()
	if results == null:
		return
	var model := _result_model()
	model["is_host"] = false
	results.render(model)
	assert_false(results.get_node("Layout/Actions/RematchButton").visible)
	assert_true(results.get_node("Layout/Waiting").visible)
	assert_true(results.get_node("Layout/Waiting").text.contains("host"))
	assert_true(results.get_node("Layout/Waiting").text.contains("rematch"))

	model["local_role"] = "spectator"
	results.render(model)
	assert_eq(results.get_node("Layout/Eyebrow").text, "Match Complete")
	assert_false(results.get_node("Layout/Actions/RematchButton").visible)
	assert_false(results.get_node("Layout/Actions/LobbyButton").visible)
	await _unmount(results)


func _result_model() -> Dictionary:
	return {
		"match_complete": true,
		"winner_id": "p1",
		"end_reason": "victory_target",
		"victory_mode": 0,
		"victory_target": 50,
		"last_round_nil": true,
		"room_code": "ABC234",
		"is_host": true,
		"players": [
			{"player_id": "p1", "name": "Mira", "spectator": false, "match_score": 54, "round_wins": 3},
			{"player_id": "p2", "name": "North", "spectator": false, "match_score": 41, "round_wins": 2},
			{"player_id": "p3", "name": "West", "spectator": false, "match_score": 33, "round_wins": 1},
			{"player_id": "p4", "name": "East", "spectator": false, "match_score": 15, "round_wins": 0},
			{"player_id": "s1", "name": "Watcher", "spectator": true, "match_score": 0, "round_wins": 0},
		],
	}


func _mount() -> Variant:
	if not ResourceLoader.exists(RESULTS_PATH):
		assert_true(false, "%s must exist" % RESULTS_PATH)
		return null
	var node = load(RESULTS_PATH).instantiate()
	Engine.get_main_loop().root.add_child(node)
	await Engine.get_main_loop().process_frame
	return node


func _unmount(node: Node) -> void:
	node.queue_free()
	await Engine.get_main_loop().process_frame
