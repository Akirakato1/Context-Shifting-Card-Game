extends "res://tests/test_case.gd"

const RuntimeSession = preload("res://src/view/app/runtime_game_session.gd")
const Preview = preload("res://src/view/match/score_preview.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const MatchController = preload("res://src/core/match/match_controller.gd")
const Projector = preload("res://src/core/match/snapshot_projector.gd")
const Protocol = preload("res://src/network/game_protocol.gd")
const AbilityCatalog = preload("res://src/core/abilities/ability_catalog.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const Card = preload("res://src/core/cards/full_card_state.gd")
const Half = preload("res://src/core/cards/half_card_state.gd")
const NormalHand = preload("res://src/core/scoring/normal_hand_definition.gd")
const ContextCatalog = preload("res://src/core/scoring/context_hand_catalog.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const GameTypes = preload("res://src/core/common/game_types.gd")
const CONTROLS = preload("res://src/view/match/phase_controls.tscn")


func test_cockpit_preview_matches_host_after_snapshot_decoration_and_network_round_trip() -> void:
	var field := AbilityDefinition.new(
		&"fives_field", AbilityDefinition.Timing.FIELD, [], &"field", 2, &"",
		{"field_rule": "per_selected_rank_set", "ranks": [5], "numerator": 1, "denominator": 2},
		{}, "Fives Field"
	)
	var definitions := AbilityCatalog.build_deck(AbilityCatalog.provisional_deck_recipe())
	definitions.append(field)
	var config := MatchConfig.new(
		[&"one", &"two"], [], 0, 1000, 0, {1: 1000, 2: 1000, 3: 1000, 4: 1000, 5: 1000},
		100, 1000, 1000, definitions, [
			NormalHand.new(&"pair", 20, 2, &"pair", Rational.new(2)),
			NormalHand.new(&"flush_three", 10, 3, &"flush", Rational.new(3)),
		], ContextCatalog.definitions()
	)
	var old_config := config.to_dict()
	old_config["base_score_mode"] = 1
	config = MatchConfig.from_dict(old_config)
	var state := MatchState.create(config, 123)
	state.phase = GameTypes.Phase.HAND_PLAY
	var player = state.players[&"one"]
	var changed := Half.new(&"a:0", 2, 8, 0)
	changed.apply_overrides(1, 5, 2)
	player.hand.assign([
		Card.new(&"a", changed, Half.new(&"a:1", 2, 7, 1)),
		Card.new(&"b", Half.new(&"b:0", 0, 5, 2), Half.new(&"b:1", 2, 5, 1)),
		Card.new(&"c", Half.new(&"c:0", 2, 0, Half.NO_SUIT, 1), Half.new(&"c:1", 0, 7, 1)),
	])
	player.factor_modifiers.append(ScoringTypes.FactorModifier.new(
		&"card_hand", &"family", Rational.new(-1, 2), &"two", &"family_nerf"
	))
	var field_copy = state.players[&"two"].ability_hand.pop_back()
	field_copy.definition = field
	state.ability_deck.play_field(field_copy, &"two")
	var resonance_copy = state.players[&"two"].ability_hand.pop_back()
	for definition in AbilityCatalog.field_designs():
		if definition.id == &"flourish_resonance":
			resonance_copy.definition = definition
			break
	state.ability_deck.play_field(resonance_copy, &"two")
	var selections := [
		{"card_id": "a", "half_index": 0, "joker_choices": []},
		{"card_id": "b", "half_index": 0, "joker_choices": []},
		{"card_id": "c", "half_index": 0, "joker_choices": [{"half_index": 0, "context": 2, "suit": 2}]},
	]
	player.staged_submission.assign(selections)
	player.has_staged_submission = true
	var snapshot := Projector.for_recipient(state, &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	snapshot["lobby_settings"] = config.to_dict()
	var runtime := RuntimeSession.new()
	var model := runtime._decorate_snapshot(snapshot, &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	assert_false(model.lobby_settings.has("ability_definitions"))
	var packet := Protocol.decode(Protocol.encode({
		"v": 1, "kind": "snapshot", "message_id": "score", "match_id": "match", "sender_id": "host",
		"payload": model,
	}))
	assert_true(packet.ok)
	if not packet.ok:
		return
	var controller := MatchController.new(state)
	assert_eq(controller._lock_player_hand(&"one", false), &"")
	var expected := Projector.score_breakdown(player.provisional_score, player.submitted_faces)
	assert_eq(expected.final_score, 113)
	assert_eq(controller._calculate_player_score(player).final_score, 113)
	for render_model in [model, packet.envelope.payload]:
		var preview := Preview.new().evaluate(render_model, selections)
		assert_eq(preview.get("score_breakdown", {}), expected)
	var locked_model := Projector.for_recipient(state, &"one", GameTypes.RecipientRole.ACTIVE_PLAYER)
	assert_true(locked_model.private_hand.is_empty())
	assert_eq(Preview.new().evaluate(locked_model, []).get("score_breakdown", {}), expected)
	var components := [
		{"rank": 5, "suit": 2, "joker": false}, {"rank": 5, "suit": 2, "joker": false},
		{"rank": 0, "suit": 2, "joker": true},
	]
	assert_eq(expected.base_components, components)


func test_cockpit_values_each_own_a_named_contribution_table() -> void:
	var controls = CONTROLS.instantiate()
	controls.table_cockpit = true
	Engine.get_main_loop().root.add_child(controls)
	controls.render({"phase": 3, "ability_catalog": {"named_field": {"display_name": "Heavy Fog"}},
		"submission_preview": {"score_breakdown": {
		"base_value": 5, "base_components": [{"rank": 5, "suit": 2, "joker": false}],
		"card_hand_components": [{
			"source_definition_id": "high_card", "value": {"numerator": 2, "denominator": 1},
		}],
		"card_hand_factor": {"numerator": 2, "denominator": 1}, "final_score": 10,
		"field_components": [{
			"source_definition_id": "named_field", "value": {"numerator": -1, "denominator": 2},
		}],
		"field_unclamped": {"numerator": 1, "denominator": 2},
		"field_factor": {"numerator": 1, "denominator": 1},
		"raw_score": {"numerator": 10, "denominator": 1},
	}}})
	await Engine.get_main_loop().process_frame
	var factors := controls.get_node("HandPlayControls/Preview/Factors")
	for key in ["Base", "Hand", "Context", "Field", "Total"]:
		var number := factors.get_node_or_null("%sValue" % key)
		assert_true(number != null, "%s needs its own hover target" % key)
		if number == null:
			continue
		var motion := InputEventMouseMotion.new()
		motion.position = number.get_global_rect().get_center()
		var viewport: Viewport = controls.get_viewport()
		viewport.push_input(motion, true)
		assert_eq(viewport.gui_get_hovered_control(), number, "%s must receive pointer hover" % key)
		var tooltip = number._make_custom_tooltip("")
		assert_true(tooltip is PanelContainer)
		var table := tooltip.get_child(0) as GridContainer
		assert_eq(table.columns, 2)
		if key == "Base":
			assert_eq(table.get_child(2).tooltip_text, "Rank 5 · Sea")
			assert_true(table.get_child(2).get_parsed_text().begins_with("Rank 5 · "))
			assert_eq(table.get_child(3).text, "5")
		if key == "Hand":
			assert_eq(table.get_child(2).get_parsed_text(), "High Card")
			assert_eq(table.get_child(3).text, "2")
		if key == "Field":
			assert_eq(table.get_child(4).get_parsed_text(), "Heavy Fog")
			assert_eq(table.get_child(5).text, "-1/2")
			assert_eq(table.get_child(6).get_parsed_text(), "Minimum factor")
			assert_eq(table.get_child(7).text, "+1/2")
		tooltip.free()
	controls.queue_free()
	await Engine.get_main_loop().process_frame


func test_cockpit_names_the_scored_hand_and_context_in_the_formula() -> void:
	var controls := CONTROLS.instantiate() as PhaseControls
	controls.table_cockpit = true
	controls.size = Vector2(1246, 410)
	Engine.get_main_loop().root.add_child(controls)
	var normal := [
		{"id": "full_house", "display_name": "Full House"},
		{"id": "flush_5", "display_name": "Five-card Flush"},
	]
	var context := [{"id": "rise_flourish_4", "display_name": "Four Renaissance",
		"requirements_text": "4 Rise / 4 Flourish"}]
	var hand_components := [{"source_definition_id": "full_house"}, {"source_definition_id": "flush_5"}]
	var context_components := [{"source_definition_id": "rise_flourish_4"}]
	controls.render({"phase": 3, "scoring_catalog": {"normal": normal, "context": context},
		"submission_preview": {"score_breakdown": {
			"card_hand_components": hand_components, "context_hand_components": context_components,
			"card_hand_factor": {"numerator": 19, "denominator": 4}, "final_score": 48,
		}},
	})
	await Engine.get_main_loop().process_frame
	var factors := controls.get_node("HandPlayControls/Preview/Factors")
	var hand_name := factors.get_node_or_null("HandName") as Label
	var context_name := factors.get_node_or_null("ContextName") as Label
	assert_true(hand_name != null and context_name != null)
	if hand_name != null and context_name != null:
		assert_eq(hand_name.text, "Full House + Five-card Flush")
		assert_eq(context_name.text, "Four Renaissance")
		assert_eq(factors.get_node("ContextValue").rows[1][0], "Four Renaissance (4 Rise / 4 Flourish)")
		assert_eq(factors.get_node("HandValue").text, "19/4")
	controls.render({"phase": 3, "submission_preview": {"score_breakdown": {"base_value": 6}}})
	if context_name != null:
		assert_eq(context_name.text, "No Context Pattern")
	controls.queue_free()
	await Engine.get_main_loop().process_frame
