class_name MatchScreen
extends Control

signal intent_requested(kind: StringName, payload: Dictionary)
signal connection_action_requested(action: StringName)
signal settings_requested
signal leave_requested

const GameTypes = preload("res://src/core/common/game_types.gd")
const MatchState = preload("res://src/core/match/match_state.gd")
const Rules := preload("res://src/view/help/rules_and_cards_modal.tscn")
const AbilityDefinition := preload("res://src/core/abilities/ability_definition.gd")
const TableScenery := preload("res://src/view/match/table_scenery.gd")
const TableAbilityTargets := preload("res://src/view/match/table_ability_targets.gd")
const CardInteractionAudio := preload("res://src/view/match/card_interaction_audio.gd")
const GameplayPreferences := preload("res://src/view/app/gameplay_preferences.gd")
const AbilityFocusShader := preload("res://src/view/match/ability_focus.gdshader")
const AbilityEffectAnimation := preload("res://src/view/match/ability_effect_animation.gd")
const MAX_FOCUS_REGIONS := 6
const PHASE_NAMES := ["SETUP", "START", "MAIN PHASE 1", "HAND PLAY", "MAIN PHASE 2", "END", "COMPLETE"]
const OPENING_DRAW_WINDOW_MSEC := 2000
const DRAW_STAGGER := 0.15
const CONTEXT_EMBLEMS := [
	preload("res://assets/artwork/context_emblems/context_emblem_rish.png"),
	preload("res://assets/artwork/context_emblems/context_emblem_flourish.png"),
	preload("res://assets/artwork/context_emblems/context_emblem_fall.png"),
]

var _model: Dictionary = {}
var _active_ability: Dictionary = {}
var _active_copy_id: StringName = &""
var _active_ability_phase := -1
var _primed_ability: Dictionary = {}
var _primed_copy_id: StringName
var _ability_commit_pending := false
var _target_step: StringName
var _eligible_seats: Array = []
var _selected_seats: Array = []
var _focus_regions := PackedVector4Array()
var _table_targets := TableAbilityTargets.new()
var _ability_focus := ColorRect.new()
var _focus_material := ShaderMaterial.new()
var _card_audio := CardInteractionAudio.new()
var _ability_effects := AbilityEffectAnimation.new()
var _connection_action: StringName = &""
var _timer_local_deadline_msec := -1
var _rules: Control
var _field_details: AcceptDialog
var _selected_sort := -1
var _history_items: Array[String] = []
var _draw_generation := 0
var _draw_speed := GameplayPreferences.DRAW_NORMAL

@export_group("Artwork")
@export var show_placeholder_guides := true
@export var phase_badge_art: StyleBoxTexture
@export var match_score_art: StyleBoxTexture
@export var opponent_seat_art: StyleBoxTexture
@export var reveal_panel_art: StyleBoxTexture
@export var history_panel_art: StyleBoxTexture
@export var context_sort_art: Array[Texture2D]

@onready var _phase: Label = $PhaseBadge/Phase
@onready var _phase_instruction: Label = $PhaseInstruction
@onready var _round: Label = $Header/Round
@onready var _timer: Label = $Header/Timer
@onready var _progress: Label = $MatchScore/Progress
@onready var _spectators: Label = $Header/Spectators
@onready var _top_seat = $TableLayer/TopSeat
@onready var _left_seat = $TableLayer/LeftSeat
@onready var _right_seat = $TableLayer/RightSeat
@onready var _bottom_seat = $TableLayer/BottomSeat
@onready var _active_effects = $Center/Fields
@onready var _round_result: Label = $Center/RoundResult
@onready var _phase_controls = $PhaseControls
@onready var _ability_panel: AbilityPanel = $AbilityPanel
@onready var _targeting_overlay: TargetingOverlay = $TargetingOverlay
@onready var _history_toggle: Button = $AbilityHistory/Toggle
@onready var _history_drawer: PanelContainer = $AbilityHistory/Drawer
@onready var _history_rows: VBoxContainer = $AbilityHistory/Drawer/Margin/Layout/Scroll/Rows
@onready var _draw_animation = $DrawAnimation
@onready var _connection_overlay: Control = $ConnectionOverlay
@onready var _connection_message: Label = $ConnectionOverlay/Panel/Layout/Message
@onready var _connection_action_button: Button = $ConnectionOverlay/Panel/Layout/ActionButton


func _ready() -> void:
	_configure_artwork()
	_phase_instruction.add_theme_font_override("font", _phase_controls.score_font)
	_timer.add_theme_font_override("font", _phase_controls.score_font)
	_card_audio.name = "CardInteractionAudio"
	add_child(_card_audio)
	_table_targets.name = "TableAbilityTargets"
	add_child(_table_targets)
	# The lower semicircle overlaps the cockpit's bounds. Its hit polygon wins
	# there only while the ability is asking for a board target.
	move_child(_table_targets, _connection_overlay.get_index())
	_table_targets.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_table_targets.target_requested.connect(_on_seat_target_requested)
	_ability_focus.name = "AbilityFocus"
	_ability_focus.z_index = 20
	_ability_focus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ability_focus.hide()
	_focus_material.shader = AbilityFocusShader
	_ability_focus.material = _focus_material
	add_child(_ability_focus)
	move_child(_ability_focus, _connection_overlay.get_index())
	_ability_focus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ability_effects.name = "AbilityEffects"
	add_child(_ability_effects)
	_ability_effects.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for seat in [_top_seat, _left_seat, _right_seat]:
		seat.ability_target_requested.connect(_on_seat_target_requested)
	$RoundReveal/Content/HandName.add_theme_font_override("font", _phase_controls.score_font)
	_rules = Rules.instantiate()
	add_child(_rules)
	_field_details = AcceptDialog.new()
	_field_details.dialog_autowrap = true
	add_child(_field_details)
	_active_effects.details_requested.connect(_show_field_details)
	$MenuButton.pressed.connect(func():
		_cancel_ability_focus()
		if _history_drawer.visible:
			_toggle_history()
		$MatchMenu.visible = not $MatchMenu.visible
	)
	$HelpButton.pressed.connect(func():
		_cancel_ability_focus()
		$MatchMenu.hide()
		_rules.open()
	)
	$MatchMenu/Options/Settings.pressed.connect(func():
		$MatchMenu.hide()
		settings_requested.emit()
	)
	$MatchMenu/Options/Leave.pressed.connect(func():
		$MatchMenu.hide()
		$ConfirmLeave.popup_centered()
	)
	$ConfirmLeave.confirmed.connect(func(): leave_requested.emit())
	_history_toggle.pressed.connect(_toggle_history)
	$SortControls/Rank.pressed.connect(_on_rank_sort_pressed)
	for i in 3:
		var button: Button = $SortControls.get_child(i)
		button.pressed.connect(_on_sort_pressed.bind(i))
		button.icon = CONTEXT_EMBLEMS[i]
		button.add_theme_font_override("font", _phase_controls.score_font)
		button.add_theme_font_size_override("font_size", 23)
		button.add_theme_constant_override("icon_max_width", 25)
		button.add_theme_constant_override("h_separation", 3)
		button.expand_icon = true
		if show_placeholder_guides or (i < context_sort_art.size() and context_sort_art[i] != null):
			var disc := TextureRect.new()
			var has_art := i < context_sort_art.size() and context_sort_art[i] != null
			disc.texture = context_sort_art[i] if has_art else preload("res://assets/artwork/board/figma/sort_button.svg")
			disc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			disc.show_behind_parent = true
			button.add_child(disc)
			disc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			if not has_art:
				disc.modulate = Color("586b7f")
				button.toggled.connect(func(pressed: bool):
					disc.modulate = Color("98743a") if pressed else Color("586b7f"))
	_refresh_sort_buttons()
	var start_piles: Array[Control] = [$Center/Piles/PileRise, $Center/Piles/PileFlourish, $Center/Piles/PileFall]
	_phase_controls.attach_start_keypads(start_piles)
	resized.connect(_position_cockpit)
	var toggle: Button = $AbilityPanel/ToggleButton
	toggle.offset_top = -88
	$AbilityPanel/DetailsMode.offset_top = toggle.offset_top
	_position_cockpit()
	_top_seat.seat_position = &"top"
	_left_seat.seat_position = &"left"
	_right_seat.seat_position = &"right"
	_bottom_seat.seat_position = &"bottom"
	if not _phase_controls.intent_requested.is_connected(_on_phase_intent_requested):
		_phase_controls.intent_requested.connect(_on_phase_intent_requested)
	_phase_controls.card_target_requested.connect(_targeting_overlay.select_value)
	_phase_controls.half_target_requested.connect(_on_half_target_requested)
	_phase_controls.hand_reordered_manually.connect(_clear_context_sort)
	_phase_controls.interaction_sound.connect(_card_audio.play)
	_ability_panel.interaction_sound.connect(_card_audio.play)
	_draw_animation.sound_requested.connect(_card_audio.play)
	$RoundReveal.sound_requested.connect(_card_audio.play)
	_ability_panel.ability_primed.connect(_on_ability_primed)
	_ability_panel.ability_cancel_requested.connect(_cancel_ability_focus)
	_ability_panel.ability_activated.connect(_on_ability_activated)
	_ability_panel.discards_confirmed.connect(func(copy_ids: Array[String]):
		_on_phase_intent_requested(&"choose_ability_discards", {"copy_ids": copy_ids})
	)
	_targeting_overlay.commit_requested.connect(_on_targeting_commit_requested)
	_targeting_overlay.closed.connect(_on_targeting_closed)
	_targeting_overlay.selection_changed.connect(_on_targeting_selection_changed)


func _configure_artwork() -> void:
	$TableScenery.show_placeholder_guides = show_placeholder_guides
	$Backdrop.visible = show_placeholder_guides
	_phase_controls.show_placeholder_guides = show_placeholder_guides
	for seat in [_top_seat, _left_seat, _right_seat, _bottom_seat]:
		seat.show_placeholder_guides = show_placeholder_guides
		seat.seat_art = opponent_seat_art
	var art_by_panel := {
		$PhaseBadge: phase_badge_art, $MatchScore: match_score_art, $RoundReveal: reveal_panel_art,
		_history_drawer: history_panel_art,
	}
	for panel: PanelContainer in art_by_panel:
		var artwork: StyleBoxTexture = art_by_panel[panel]
		if artwork != null:
			panel.add_theme_stylebox_override("panel", artwork)
		elif not show_placeholder_guides:
			panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


func render(model: Dictionary) -> void:
	if not _model.is_empty() and (
		_model.get("private_player_id") != model.get("private_player_id")
		or (bool(model.get("frozen", false)) and not bool(_model.get("frozen", false)))
	):
		_cancel_draws()
	var draws := _incoming_draws(model)
	var origins: Array[Vector2] = []
	if not draws.is_empty() and not _model.is_empty():
		origins = _pile_origins()
	_play_new_round_result(model)
	_model = model.duplicate(true)
	for card: Dictionary in draws.get("cards", []):
		_phase_controls.set_draw_pending(StringName(card.card_id), true)
	for ability: Dictionary in draws.get("abilities", []):
		_ability_panel.set_draw_pending(StringName(ability.copy_id), true)
	_rules.render(_model)
	_render_header()
	_render_context_and_piles()
	_active_effects.render(_model, _phase_controls.score_font)
	_render_seats()
	_render_phase_controls()
	_render_abilities()
	_render_connection_state()
	$RoundReveal.render(_model)
	if not draws.is_empty():
		_play_draws.call_deferred(draws, origins, _draw_generation)


func _play_new_round_result(model: Dictionary) -> void:
	var player := str(model.get("private_player_id", ""))
	var winner := str(model.get("last_round_winner_id", ""))
	if player.is_empty() or winner.is_empty() or player != str(_model.get("private_player_id", "")):
		return
	var phase := int(model.get("phase", -1))
	var previous_phase := int(_model.get("phase", -1))
	var entered_end := phase == GameTypes.Phase.END and previous_phase != GameTypes.Phase.END
	# When no discards are due, a finalized round goes straight to the next Start.
	var skipped_end := (
		phase == GameTypes.Phase.START and previous_phase == GameTypes.Phase.MAIN_2
		and int(model.get("round_number", 0)) > int(_model.get("round_number", 0))
	)
	if entered_end or skipped_end:
		_card_audio.play(&"round_win" if winner == player else &"round_loss")


func set_draw_speed(speed: int) -> void:
	_draw_speed = speed
	if speed == GameplayPreferences.DRAW_SKIP:
		_cancel_draws()
	else:
		_draw_animation.set_playback_speed(float(speed))


func handle_match_hotkey(action: StringName, repeat: bool) -> bool:
	if (
		_connection_overlay.visible or _rules.visible or _field_details.visible
		or $MatchMenu.visible or $ConfirmLeave.visible or _targeting_overlay.visible
	):
		return false
	if repeat:
		return true
	match action:
		GameplayPreferences.HOTKEY_READY:
			if _phase_controls.visible:
				_phase_controls.trigger_ready_shortcut()
		GameplayPreferences.HOTKEY_ABILITIES:
			var toggle: Button = $AbilityPanel/ToggleButton
			if toggle.is_visible_in_tree() and not toggle.disabled:
				toggle.pressed.emit()
		GameplayPreferences.HOTKEY_HISTORY:
			_toggle_history()
	return true


func _incoming_draws(model: Dictionary) -> Dictionary:
	if _draw_speed == GameplayPreferences.DRAW_SKIP:
		return {}
	if not model.has("server_now_msec") or str(model.get("private_player_id", "")).is_empty():
		return {}
	if bool(model.get("frozen", false)) or bool(_model.get("frozen", false)):
		return {}
	if _model.is_empty():
		var started := int(model.get("phase_started_msec", -1))
		var age := int(model.get("server_now_msec", -1)) - started
		if (int(model.get("round_number", 0)) != 1 or int(model.get("phase", 0)) != GameTypes.Phase.MAIN_1
			or started < 0 or age < 0 or age > OPENING_DRAW_WINDOW_MSEC):
			return {}
	elif model.get("private_player_id") != _model.get("private_player_id") and not (
		str(_model.get("private_player_id", "")).is_empty() and _model.get("local_role") == "active"
	):
		return {}
	var cards := _new_draw_items(model, "private_hand", "card_id")
	var abilities := _new_draw_items(model, "private_abilities", "copy_id")
	return {} if cards.is_empty() and abilities.is_empty() else {"cards": cards, "abilities": abilities}


func _new_draw_items(model: Dictionary, inventory_key: String, id_key: String) -> Array:
	var existing := {}
	for item: Dictionary in _model.get(inventory_key, []):
		existing[str(item.get(id_key, ""))] = true
	return model.get(inventory_key, []).filter(func(item: Dictionary):
		var id := str(item.get(id_key, ""))
		return not id.is_empty() and not existing.has(id)
	)


func _pile_origins() -> Array[Vector2]:
	var origins: Array[Vector2] = []
	for context in 3:
		origins.append(get_node("Center/Piles/Pile%s" % _context_name(context)).draw_origin())
	origins.append($Center/Piles/PileAbility.draw_origin())
	return origins


func _play_draws(draws: Dictionary, origins: Array, generation: int) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree() or generation != _draw_generation:
		return
	if origins.is_empty():
		origins = _pile_origins()
	var delay := 0.0
	for card: Dictionary in draws.cards:
		var id := StringName(card.card_id)
		var sources: Array[Vector2] = []
		for half_key in ["first", "second"]:
			var half: Dictionary = card.get(half_key, {})
			var context := int(half.get("base_context", half.get("effective_context", 0)))
			sources.append(origins[clampi(context, 0, 2)])
		var destination := func(): return _phase_controls.card_widget(id)
		var flight: Control = _draw_animation.play_hand_draw(card, sources, destination, delay)
		_track_draw_landing(flight, id, false, generation)
		delay += DRAW_STAGGER
	var catalog: Dictionary = _model.get("ability_catalog", {})
	for ability: Dictionary in draws.abilities:
		var id := StringName(ability.copy_id)
		var card := ability.duplicate(true)
		card.merge(catalog.get(str(ability.get("ability_id", "")), {}), true)
		var destination := func(): return _ability_panel.draw_destination(id)
		var flight: Control = _draw_animation.play_ability_draw(card, origins[3], destination, delay)
		_track_draw_landing(flight, id, true, generation)
		delay += DRAW_STAGGER


func _track_draw_landing(flight: Control, id: StringName, ability: bool, generation: int) -> void:
	if flight != null:
		flight.connect(&"landed", _reveal_draw_destination.bind(id, ability, generation), CONNECT_ONE_SHOT)
		flight.tree_exited.connect(_reveal_draw_destination.bind(id, ability, generation), CONNECT_ONE_SHOT)
	else:
		_reveal_draw_destination(id, ability, generation)


func _reveal_draw_destination(id: StringName, ability: bool, generation: int) -> void:
	if generation != _draw_generation or not is_inside_tree():
		return
	if ability:
		_ability_panel.set_draw_pending(id, false)
	else:
		_phase_controls.set_draw_pending(id, false)


func _cancel_draws() -> void:
	_draw_generation += 1
	_draw_animation.cancel()
	_phase_controls.clear_pending_draws()
	_ability_panel.clear_pending_draws()


func _process(_delta: float) -> void:
	if _timer_local_deadline_msec >= 0:
		_update_timer(maxi(0, _timer_local_deadline_msec - Time.get_ticks_msec()))
	if _ability_focus.visible:
		_update_focus_regions()


func handle_command_result(
	kind: StringName,
	accepted: bool,
	error_code: StringName,
	authoritative_phase: int
) -> void:
	_phase_controls.handle_command_result(kind, accepted, error_code, authoritative_phase)
	if kind == &"choose_ability_discards" and not accepted:
		_ability_panel.discard_rejected(error_code)
	if not accepted and kind in [
		&"stage_hand", &"lock_hand", &"stage_manipulation", &"commit_manipulation",
		&"play_public_ability", &"configure_joker",
	]:
		_card_audio.play(&"invalid")
	if kind == &"stage_manipulation" and not accepted:
		if _targeting_overlay.visible:
			_targeting_overlay.cancel(&"rejected")
		else:
			_clear_active_ability()
	elif kind in [&"commit_manipulation", &"play_public_ability"]:
		_ability_commit_pending = false
		if accepted:
			_card_audio.play(&"play")
			_clear_active_ability()
		elif (
			authoritative_phase == int(_model.get("phase", -1))
			and _active_ability_still_legal()
			and not _active_ability.get("choice_schema", {}).get("steps", []).is_empty()
		):
			_targeting_overlay.reopen()
		else:
			_clear_active_ability()


func _render_header() -> void:
	var phase_index := int(_model.get("phase", 0))
	_phase.text = PHASE_NAMES[phase_index] if phase_index >= 0 and phase_index < PHASE_NAMES.size() else "UNKNOWN"
	var has_player := not str(_model.get("private_player_id", "")).is_empty()
	_phase_instruction.visible = has_player and phase_index in [
		GameTypes.Phase.MAIN_1, GameTypes.Phase.HAND_PLAY, GameTypes.Phase.MAIN_2,
	]
	_round.text = "ROUND %d" % int(_model.get("round_number", 0))
	var deadline := int(_model.get("phase_deadline_msec", -1))
	var server_now := int(_model.get(
		"server_now_msec", _model.get("now_msec", deadline)
	))
	var remaining := maxi(0, deadline - server_now) if deadline >= 0 else 0
	_timer_local_deadline_msec = Time.get_ticks_msec() + remaining if deadline >= 0 else -1
	_update_timer(remaining)
	var spectator_count := 0
	for player in _model.get("players", []):
		if player is Dictionary and bool(player.get("spectator", false)):
			spectator_count += 1
	_spectators.text = "SPECTATORS  %d / 4" % spectator_count
	var progress_player := _progress_player()
	var victory_mode := int(_model.get("victory_mode", _lobby_setting("victory_mode", 0)))
	var target := int(_model.get("victory_target", _lobby_setting("victory_target", 10)))
	if victory_mode == 1:
		_progress.text = "ROUND-WIN RACE  ·  %d / %d" % [int(progress_player.get("round_wins", 0)), target]
	else:
		_progress.text = "SCORE RACE  ·  %d / %d" % [int(progress_player.get("match_score", 0)), target]


func _update_timer(remaining_msec: int) -> void:
	if _timer_local_deadline_msec >= 0:
		_timer.text = "%.1fs" % (remaining_msec / 1000.0)
	else:
		_timer.text = "UNTIMED" if bool(_model.get("is_practice", false)) else "—"


func _render_context_and_piles() -> void:
	var active_context := int(_model.get("active_context", 0))
	var active_contexts := _active_contexts()
	var direction := int(_model.get("context_direction", 1))
	var is_selecting_hand := int(_model.get("phase", 0)) == GameTypes.Phase.HAND_PLAY and not str(_model.get("private_player_id", "")).is_empty()
	$TableScenery.render(active_context, direction, active_contexts, is_selecting_hand)
	var counts: Dictionary = _model.get("pile_counts", {})
	for context in 3:
		var pile = get_node("Center/Piles/Pile%s" % _context_name(context))
		var data: Dictionary = counts.get(str(context), counts.get(context, {}))
		var count := int(data.get("draw_count", -1))
		pile.render(count, int(data.get("capacity", MatchState.CONTEXT_PILE_CAPACITY)), context in active_contexts)
	var ability_deck: Dictionary = _model.get("ability_pile_count", {})
	var ability_count := int(ability_deck.get("draw_count", -1))
	$Center/Piles/PileAbility.render(ability_count, int(ability_deck.get("capacity", maxi(ability_count, 1))))
	_round_result.visible = bool(_model.get("last_round_nil", false))
	_round_result.text = "NIL ROUND  ·  no progress awarded" if _round_result.visible else ""


func _show_field_details(field_name: String, rules: String) -> void:
	_field_details.title = field_name
	_field_details.dialog_text = rules
	_field_details.popup_centered(Vector2i(440, 150))


func _render_seats() -> void:
	var active_players: Array = []
	for player in _model.get("players", []):
		if player is Dictionary and not bool(player.get("spectator", false)):
			active_players.append(player)
	active_players.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("seat_index", 0)) < int(b.get("seat_index", 0)))
	var private_id := str(_model.get("private_player_id", ""))
	var viewing_as_spectator := private_id.is_empty()
	var local_player: Dictionary = {}
	var opponents: Array = []
	for player in active_players:
		if not private_id.is_empty() and str(player.get("player_id", "")) == private_id:
			local_player = player
		else:
			opponents.append(player)
	if local_player.is_empty() and not active_players.is_empty():
		local_player = active_players[0]
		opponents = active_players.slice(1)
	var phase := int(_model.get("phase", GameTypes.Phase.SETUP))
	var victory_mode := int(_model.get("victory_mode", GameTypes.VictoryMode.SCORE_RACE))
	var requests: Dictionary = _model.get("replacement_requests", {})
	var context_catalog: Array = _model.get("scoring_catalog", {}).get("context", [])
	_bottom_seat.visible = viewing_as_spectator or phase in [GameTypes.Phase.MAIN_2, GameTypes.Phase.END]
	_bottom_seat.offset_top = 42.0 if phase == GameTypes.Phase.MAIN_2 else 0.0
	_bottom_seat.offset_bottom = _bottom_seat.offset_top + 53.0
	_bottom_seat.render(
		local_player, phase, viewing_as_spectator, not viewing_as_spectator,
		victory_mode, _request_for(requests, local_player), context_catalog
	)
	var opponent_seats := [_top_seat, _left_seat, _right_seat]
	for index in opponent_seats.size():
		var player: Dictionary = opponents[index] if index < opponents.size() else {}
		opponent_seats[index].render(
			player, phase, viewing_as_spectator, false, victory_mode, _request_for(requests, player), context_catalog
		)


func _active_contexts() -> Array:
	var result: Array = _model.get("active_contexts", [])
	if result.is_empty():
		result = [int(_model.get("active_context", 0))]
	return result


func present_ability_events(events: Array) -> void:
	var scenery: Control = $TableScenery
	var view_scale := scenery.size / TableScenery.BASE
	var transform := _ability_effects.get_global_transform().affine_inverse()
	var scenery_to_effects := transform * scenery.get_global_transform()
	var seats := {}
	for seat in [_top_seat, _left_seat, _right_seat, _bottom_seat]:
		var id: String = seat.player_id()
		if id.is_empty():
			continue
		var bounds: Rect2 = seat.ability_target_rect() if seat.visible else _phase_controls.hand_focus_rect()
		seats[id] = transform * bounds
	var board := TableScenery.TABLE_RECT
	_ability_effects.set_regions(
		scenery_to_effects * Rect2(board.position * view_scale, board.size * view_scale),
		seats
	)
	_ability_effects.present(events, _model)


func _render_phase_controls() -> void:
	var has_private_player := not str(_model.get("private_player_id", "")).is_empty()
	_phase_controls.visible = has_private_player
	$MatchScore.visible = has_private_player
	$SortControls.visible = has_private_player
	_position_cockpit()
	if not has_private_player:
		return
	_phase_controls.render(_model)
	_phase_controls.set_inputs_locked(bool(_model.get("frozen", false)))


func _position_cockpit() -> void:
	var view_scale := size / TableScenery.BASE
	var ui_scale := maxf(0.25, minf(view_scale.x, view_scale.y))
	var tray := TableScenery.HAND_TRAY_RECT
	_phase_controls.position = Vector2(tray.position.x, TableScenery.SCORE_BAR_TOP) * view_scale
	_phase_controls.scale = Vector2.ONE * ui_scale
	_phase_controls.size = Vector2(tray.size.x * view_scale.x / ui_scale, 410)
	_phase_controls.position_start_keypads()
	_ability_panel.scale = Vector2.ONE * ui_scale
	_ability_panel.position = Vector2(size.x * 0.852, size.y * 0.765 - _ability_panel.size.y * ui_scale)
	var toggle: Button = $AbilityPanel/ToggleButton
	var drawer_top := -get_global_transform().origin.y
	var drawer_bottom := _ability_panel.position.y + (toggle.position.y - 8.0) * ui_scale
	var drawer_left := size.x * 0.844
	var drawer_right := (get_global_transform().affine_inverse() * get_viewport_rect().end).x
	var drawer_position := (Vector2(drawer_left, drawer_top) - _ability_panel.position) / ui_scale
	var drawer_size := Vector2(drawer_right - drawer_left, drawer_bottom - drawer_top) / ui_scale
	_ability_panel.set_drawer_bounds(Rect2(drawer_position, drawer_size))


func _on_sort_pressed(index: int) -> void:
	if _phase_controls.sort_hand(index):
		_selected_sort = index
	else:
		_card_audio.play(&"invalid")
	_refresh_sort_buttons()


func _clear_context_sort() -> void:
	_selected_sort = -1
	for i in 3:
		$SortControls.get_child(i).button_pressed = false
	_refresh_sort_buttons()


func _on_rank_sort_pressed() -> void:
	if not _phase_controls.toggle_rank_sort():
		_card_audio.play(&"invalid")
		return
	_refresh_sort_buttons()


func _refresh_sort_buttons() -> void:
	var ascending: bool = _phase_controls.rank_sort_ascending()
	var arrow := "↑" if ascending else "↓"
	var order := "low to high" if ascending else "high to low"
	$SortControls/Rank.text = "RANK " + arrow
	$SortControls/Rank.tooltip_text = "Top-half rank: " + order
	for i in 3:
		var button: Button = $SortControls.get_child(i)
		button.set_pressed_no_signal(i == _selected_sort)
		button.text = arrow if i == _selected_sort else "↕"
		button.tooltip_text = "%s facing up · rank %s" % [_context_name(i), order]


func _render_abilities() -> void:
	var has_private_player := not str(_model.get("private_player_id", "")).is_empty()
	var phase := int(_model.get("phase", 0))
	var frozen := bool(_model.get("frozen", false))
	var hand_locked := phase == GameTypes.Phase.HAND_PLAY and bool(_model.get("private_staging", {}).get("hand_locked", false))
	_ability_panel.visible = has_private_player
	if has_private_player:
		_ability_panel.render(
			_model.get("private_abilities", []), phase,
			_model.get("ability_catalog", {}), frozen or hand_locked,
			int(_model.get("required_ability_discards", 0)) if phase == GameTypes.Phase.END else 0
		)
	_render_ability_history()
	if not _active_ability.is_empty() and (
		not has_private_player or frozen or phase != _active_ability_phase
		or (not _ability_commit_pending and not _active_ability_still_legal())
	):
		if _targeting_overlay.visible:
			_targeting_overlay.cancel(&"interrupted")
		else:
			_clear_active_ability()
	_refresh_ability_focus()


func _render_ability_history() -> void:
	var player_names := {}
	for player: Dictionary in _model.get("players", []):
		var id := str(player.get("player_id", ""))
		player_names[id] = str(player.get("name", id))
	var catalog: Dictionary = _model.get("ability_catalog", {})
	var events: Array = _model.get("public_history", [])
	var items: Array[String] = []
	for index in range(events.size() - 1, -1, -1):
		var event: Dictionary = events[index]
		var description := _history_description(event, player_names, catalog)
		if description.is_empty():
			continue
		var round_number := int(event.get("payload", {}).get("round_number", event.get("round_number", 0)))
		items.append("Round %d  ·  %s" % [round_number, description] if round_number > 0 else description)
	if items.is_empty():
		for played: Dictionary in _model.get("recent_public_abilities", []):
			items.append(_history_description({"kind": "public_ability_played", "payload": played}, {}, catalog))
	if items.is_empty():
		items.append("No public plays yet.")
	if items == _history_items:
		return
	_history_items = items
	for child in _history_rows.get_children():
		_history_rows.remove_child(child)
		child.queue_free()
	for text in items:
		var row := Label.new()
		row.add_theme_font_override("font", _phase_controls.score_font)
		row.text = text
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_history_rows.add_child(row)


func _toggle_history() -> void:
	_history_drawer.visible = not _history_drawer.visible
	if _history_drawer.visible:
		$MatchMenu.hide()
	_history_toggle.text = "HISTORY  ▼" if _history_drawer.visible else "HISTORY  ▲"


func _history_description(event: Dictionary, names: Dictionary, catalog: Dictionary) -> String:
	var payload: Dictionary = event.get("payload", {})
	var ability_id := str(payload.get("ability_id", "ability"))
	var player_id := str(payload.get("player_id", ""))
	var player_name := str(names.get(player_id, player_id))
	match str(event.get("kind", "")):
		"public_ability_played":
			var source := str(payload.get("source_player_id", "?"))
			var target := str(payload.get("target_player_id", ""))
			var players := str(names.get(source, source))
			if not target.is_empty():
				players += " → %s" % str(names.get(target, target))
			return "%s  ·  %s" % [_history_ability_name(ability_id, catalog), players]
		"field_expired":
			return "%s expired" % _history_ability_name(ability_id, catalog)
		"context_changed", "context_advanced":
			return "Clock moved to %s" % _context_name(int(payload.get("context", 0)))
		"hand_revealed":
			var revealed := "%s passed" % player_name
			if not payload.get("cards", []).is_empty():
				revealed = "%s revealed a hand worth %d provisional points" % [player_name, int(payload.get("provisional_score", 0))]
			var manipulation_names: Array[String] = []
			for id in payload.get("manipulation_ability_ids", []):
				manipulation_names.append(_history_ability_name(str(id), catalog))
			return revealed if manipulation_names.is_empty() else "%s  ·  %s" % [revealed, ", ".join(manipulation_names)]
		"round_finalized":
			var winner := str(payload.get("winner_id", ""))
			var result := "Tied round" if winner.is_empty() else "%s wins" % str(names.get(winner, winner))
			var scores: Dictionary = payload.get("scores", {})
			var terms: Array[String] = []
			for id in scores:
				terms.append("%s %d" % [str(names.get(id, id)), int(scores[id])])
			return result if terms.is_empty() else "%s  ·  %s" % [result, ", ".join(terms)]
	return ""


func _history_ability_name(id: String, catalog: Dictionary) -> String:
	return str(catalog.get(id, {}).get("display_name", id.capitalize()))


func _render_connection_state() -> void:
	var connection: Dictionary = _model.get("connection_state", {})
	var status := str(connection.get("status", "connected"))
	if bool(_model.get("frozen", false)) or status == "reconnecting":
		var remaining := maxi(
			int(connection.get("deadline_msec", 0)) - int(connection.get("now_msec", _model.get("now_msec", 0))), 0
		)
		_connection_overlay.visible = true
		_connection_message.text = "Match paused while a player reconnects  ·  %.1fs remaining" % (remaining / 1000.0)
		_connection_action_button.visible = false
	elif status == "connected":
		_connection_overlay.visible = false
		_connection_action_button.visible = true


func show_connection_failure(reason: StringName) -> void:
	var states := {
		&"forfeit": ["You forfeited this match.", "RETURN TO LOBBY", &"lobby"],
		&"host_lost": ["The host connection was lost. Reconnect before your grace period expires.", "TRY RECONNECT", &"retry"],
		&"direct_connection_failed": ["The direct and relay routes could not establish a connection.", "TRY AGAIN", &"retry"],
		&"relay_unavailable": ["A direct route could not be established, and relay fallback was unavailable.", "TRY AGAIN", &"retry"],
		&"room_closed": ["This room was closed by the host.", "RETURN TO MENU", &"menu"],
	}
	var state: Array = states.get(reason, ["The match connection ended.", "RETURN TO MENU", &"menu"])
	_connection_overlay.visible = true
	_connection_message.text = state[0]
	_connection_action_button.text = state[1]
	_connection_action_button.visible = true
	_connection_action = state[2]
	_cancel_ability_focus()
	_phase_controls.set_inputs_locked(true)


func _on_ability_activated(copy_id: StringName, ability: Dictionary) -> void:
	if _targeting_overlay.visible or _ability_commit_pending:
		_card_audio.play(&"invalid")
		return
	_primed_copy_id = &""
	_primed_ability.clear()
	_active_copy_id = copy_id
	_active_ability = ability.duplicate(true)
	_active_ability_phase = int(_model.get("phase", -1))
	_ability_panel.set_activating_copy(copy_id)
	var timing := int(ability.get("timing", -1))
	var workflow: Dictionary = ability.get("choice_schema", {})
	if workflow.get("steps", []).is_empty():
		_ability_commit_pending = true
		_refresh_ability_focus()
		intent_requested.emit(&"play_public_ability", {"copy_id": str(copy_id), "target_player_id": ""})
		return
	var hand: Array = _model.get("private_hand", [])
	var targets := _active_player_targets(timing == AbilityDefinition.Timing.SABOTAGE)
	if (
		(timing == AbilityDefinition.Timing.HAND_MANIPULATION and hand.is_empty())
		or (timing in [AbilityDefinition.Timing.SABOTAGE, AbilityDefinition.Timing.HAND_SHAPE] and targets.is_empty())
	):
		_card_audio.play(&"invalid")
		_clear_active_ability()
		return
	_card_audio.play(&"select")
	_targeting_overlay.begin(workflow, hand, targets, true)
	if timing == AbilityDefinition.Timing.HAND_MANIPULATION:
		intent_requested.emit(&"stage_manipulation", {"copy_id": str(copy_id)})


func _on_ability_primed(copy_id: StringName, ability: Dictionary) -> void:
	_primed_copy_id = copy_id
	_primed_ability = ability.duplicate(true)
	_refresh_ability_focus()


func _on_targeting_commit_requested(choices: Dictionary) -> void:
	var timing := int(_active_ability.get("timing", -1))
	_ability_commit_pending = true
	if timing == AbilityDefinition.Timing.HAND_MANIPULATION:
		intent_requested.emit(&"commit_manipulation", {"choices": choices.duplicate(true)})
	else:
		intent_requested.emit(&"play_public_ability", {
			"copy_id": str(_active_copy_id),
			"target_player_id": str(_single_choice(choices, "target_player_id", "")),
			"choices": choices.duplicate(true),
		})


func _active_player_targets(opponents_only := false) -> Array:
	var result: Array = []
	var private_id := str(_model.get("private_player_id", ""))
	for player in _model.get("players", []):
		if not player is Dictionary: continue
		if bool(player.get("spectator", false)) or not bool(player.get("active", false)) or bool(player.get("pending", false)):
			continue
		var player_id := str(player.get("player_id", ""))
		if opponents_only and (player_id == private_id or not bool(player.get("connected", true))):
			continue
		result.append({"player_id": player_id,
			"display_name": str(player.get("display_name", player.get("name", player_id)))})
	return result


func _on_targeting_selection_changed(kind: StringName, eligible: Array, selected: Array) -> void:
	_target_step = kind
	if kind == &"player":
		_eligible_seats = eligible
		_selected_seats = selected
	var chosen: Array = _targeting_overlay.hand_choice_values()
	if kind in [&"card", &"full_card", &"half_card"]:
		_phase_controls.set_targeting(kind, eligible, chosen)
	elif kind == &"half_index" and not chosen.is_empty():
		var card_id := str(chosen[0])
		var halves := eligible.map(func(index): return {"card_id": card_id, "half_index": index})
		for index in selected:
			chosen.append({"card_id": card_id, "half_index": index})
		_phase_controls.set_targeting(&"half_card", halves, chosen)
	elif not chosen.is_empty():
		_phase_controls.set_targeting(&"", [], chosen)
	else:
		_phase_controls.clear_targeting()
	_refresh_ability_focus()


func _on_targeting_closed(reason: StringName) -> void:
	if reason == &"committed":
		_refresh_ability_focus()
		return
	var cancels_manipulation := (
		reason == &"cancelled" and int(_active_ability.get("timing", -1)) == AbilityDefinition.Timing.HAND_MANIPULATION
	)
	_clear_active_ability()
	if reason == &"cancelled":
		_card_audio.play(&"unprime")
	if cancels_manipulation:
		intent_requested.emit(&"cancel_manipulation", {})


func _on_half_target_requested(card_id: StringName, half_index: int) -> void:
	if _target_step == &"half_index":
		_targeting_overlay.select_value(half_index)
	else:
		_targeting_overlay.select_value({"card_id": str(card_id), "half_index": half_index})


func _on_seat_target_requested(player_id: String) -> void:
	if _target_step == &"player" and _targeting_overlay.visible and player_id in _eligible_seats:
		_card_audio.play(&"select")
		_targeting_overlay.select_value(player_id)


func _cancel_ability_focus() -> void:
	if _targeting_overlay.visible:
		_targeting_overlay.cancel()
	else:
		_ability_panel.clear_primed_ability()


func _on_connection_action_pressed() -> void:
	connection_action_requested.emit(_connection_action)


func _active_ability_still_legal() -> bool:
	return (
		not _active_copy_id.is_empty() and _active_copy_id in _ability_panel.legal_ability_ids()
		and not _ability_panel.inputs_locked()
		and _active_ability_phase == int(_model.get("phase", -1))
	)


func _single_choice(choices: Dictionary, key: String, fallback: Variant) -> Variant:
	var values: Array = choices.get(key, [])
	return values[0] if not values.is_empty() else fallback


func _clear_active_ability() -> void:
	_active_copy_id = &""
	_active_ability.clear()
	_active_ability_phase = -1
	_ability_commit_pending = false
	_target_step = &""
	_eligible_seats.clear()
	_selected_seats.clear()
	_ability_panel.set_activating_copy(&"")
	_phase_controls.clear_targeting()
	_refresh_ability_focus()


func _refresh_ability_focus() -> void:
	var ability := _active_ability if not _active_ability.is_empty() else _primed_ability
	_phase_instruction.text = "Open Abilities and right-click a playable card."
	if _active_ability.is_empty() and not _primed_ability.is_empty():
		_phase_instruction.text = "Left-click the highlighted ability to play it."
	var timing := int(ability.get("timing", -1))
	var has_focus := not ability.is_empty() and not bool(_model.get("frozen", false))
	_phase_controls.set_ability_focus_held(has_focus)
	var selects_player := has_focus and _target_step == &"player" and _targeting_overlay.visible
	var eligible: Array = []
	if has_focus and timing in [AbilityDefinition.Timing.SABOTAGE, AbilityDefinition.Timing.HAND_SHAPE]:
		for target in _active_player_targets(timing == AbilityDefinition.Timing.SABOTAGE):
			if selects_player and target.player_id in _eligible_seats:
				eligible.append(target.player_id)
			elif not selects_player and (_selected_seats.is_empty() or target.player_id in _selected_seats):
				eligible.append(target.player_id)
	var seats := {}
	for seat in [_top_seat, _left_seat, _right_seat, _bottom_seat]:
		var player_id: String = seat.player_id()
		seats[seat.seat_position] = player_id
		var seat_eligible := timing == AbilityDefinition.Timing.SABOTAGE and player_id in eligible
		seat.set_ability_target(seat_eligible, player_id in _selected_seats, selects_player)
	_table_targets.set_targets(
		seats, eligible if timing == AbilityDefinition.Timing.HAND_SHAPE else [],
		_selected_seats, selects_player
	)
	_ability_focus.visible = has_focus or _ability_panel.discard_focus_rect().has_area()
	if _ability_focus.visible:
		_update_focus_regions()


func _update_focus_regions() -> void:
	if _ability_focus.size.x <= 0.0 or _ability_focus.size.y <= 0.0:
		return
	var ability := _active_ability if not _active_ability.is_empty() else _primed_ability
	var copy_id := _active_copy_id if not _active_copy_id.is_empty() else _primed_copy_id
	var regions: Array[Rect2] = [_ability_panel.ability_focus_rect(copy_id), _ability_panel.discard_focus_rect()]
	match int(ability.get("timing", -1)):
		AbilityDefinition.Timing.HAND_MANIPULATION:
			regions.append(_phase_controls.hand_focus_rect())
		AbilityDefinition.Timing.FIELD:
			var clock_effect := (
				str(ability.get("effect_id", "")) in ["context_jump", "reverse_direction"]
				or str(ability.get("field_rule", "")) == "additional_context"
			)
			var scenery: TableScenery = $TableScenery
			var view_scale := scenery.size / TableScenery.BASE
			var board := TableScenery.TABLE_RECT
			var bounds: Rect2 = scenery.clock_rect() if clock_effect else Rect2(
				board.position * view_scale, board.size * view_scale
			)
			regions.append(scenery.get_global_transform() * bounds)
		AbilityDefinition.Timing.HAND_SHAPE:
			regions.append_array(_table_targets.target_rects())
		AbilityDefinition.Timing.SABOTAGE:
			for seat in [_top_seat, _left_seat, _right_seat]:
				if seat.is_ability_target():
					regions.append(seat.ability_target_rect())
	var to_local := _ability_focus.get_global_transform().affine_inverse()
	var rects := PackedVector4Array()
	for region in regions:
		if not region.has_area() or rects.size() >= MAX_FOCUS_REGIONS:
			continue
		var local := to_local * region
		var start := local.position / _ability_focus.size
		var end := local.end / _ability_focus.size
		rects.append(Vector4(start.x, start.y, end.x, end.y))
	var region_count := rects.size()
	rects.resize(MAX_FOCUS_REGIONS)
	if rects != _focus_regions:
		_focus_regions = rects
		_focus_material.set_shader_parameter("focus_regions", rects)
		_focus_material.set_shader_parameter("region_count", region_count)


func _on_phase_intent_requested(kind: StringName, payload: Dictionary) -> void:
	intent_requested.emit(kind, payload.duplicate(true))


func _request_for(requests: Dictionary, player: Dictionary) -> Dictionary:
	if player.is_empty():
		return {}
	var request: Variant = requests.get(str(player.get("player_id", "")), {})
	return request if request is Dictionary else {}


func _progress_player() -> Dictionary:
	var private_id := str(_model.get("private_player_id", ""))
	var first_active: Dictionary = {}
	for player in _model.get("players", []):
		if not player is Dictionary or bool(player.get("spectator", false)):
			continue
		if first_active.is_empty():
			first_active = player
		if str(player.get("player_id", "")) == private_id:
			return player
	return first_active


func _lobby_setting(key: String, fallback: Variant) -> Variant:
	var settings: Dictionary = _model.get("lobby_settings", {})
	return settings.get(key, fallback)


func _context_name(index: int) -> String:
	return GameTypes.context_name(index)
