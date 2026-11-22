class_name MatchScreen
extends Control

signal intent_requested(kind: StringName, payload: Dictionary)
signal connection_action_requested(action: StringName)
signal settings_requested
signal leave_requested

const GameTypes = preload("res://src/core/common/game_types.gd")
const Rules := preload("res://src/view/help/rules_and_cards_modal.tscn")
const PHASE_NAMES := ["SETUP", "START", "MAIN 1", "HAND PLAY", "MAIN 2", "END", "COMPLETE"]

var _model: Dictionary = {}
var _active_ability: Dictionary = {}
var _active_copy_id: StringName = &""
var _connection_action: StringName = &""
var _timer_local_deadline_msec := -1
var _rules: Control
var _field_details: AcceptDialog
var _selected_sort := -1

@export_group("Artwork")
@export var show_placeholder_guides := true
@export var phase_badge_art: StyleBoxTexture
@export var match_score_art: StyleBoxTexture
@export var opponent_seat_art: StyleBoxTexture
@export var reveal_panel_art: StyleBoxTexture
@export var context_sort_art: Array[Texture2D]

@onready var _phase: Label = $PhaseBadge/Phase
@onready var _round: Label = $Header/Round
@onready var _timer: Label = $Header/Timer
@onready var _progress: Label = $MatchScore/Progress
@onready var _spectators: Label = $Header/Spectators
@onready var _top_seat = $TableLayer/TopSeat
@onready var _left_seat = $TableLayer/LeftSeat
@onready var _right_seat = $TableLayer/RightSeat
@onready var _bottom_seat = $TableLayer/BottomSeat
@onready var _clock_direction: Label = $Center/ContextClock/Direction
@onready var _clock_active: Label = $Center/ContextClock/Active
@onready var _field_rows: VBoxContainer = $Center/Fields/FieldScroll/FieldRows
@onready var _round_result: Label = $Center/RoundResult
@onready var _phase_controls = $PhaseControls
@onready var _ability_panel: AbilityPanel = $AbilityPanel
@onready var _targeting_overlay = $TargetingOverlay
@onready var _ability_history: VBoxContainer = $AbilityHistory/Rows
@onready var _connection_overlay: Control = $ConnectionOverlay
@onready var _connection_message: Label = $ConnectionOverlay/Panel/Layout/Message
@onready var _connection_action_button: Button = $ConnectionOverlay/Panel/Layout/ActionButton


func _ready() -> void:
	_configure_artwork()
	_rules = Rules.instantiate()
	add_child(_rules)
	_field_details = AcceptDialog.new()
	_field_details.dialog_autowrap = true
	add_child(_field_details)
	$MenuButton.pressed.connect(func(): $MatchMenu.visible = not $MatchMenu.visible)
	$HelpButton.pressed.connect(func():
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
	$SortControls/Rank.pressed.connect(_on_rank_sort_pressed)
	for i in 3:
		var button: Button = $SortControls.get_child(i)
		button.pressed.connect(_on_sort_pressed.bind(i))
		if i < 3 and (show_placeholder_guides or (i < context_sort_art.size() and context_sort_art[i] != null)):
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
	resized.connect(_position_cockpit)
	var toggle: Button = $AbilityPanel/ToggleButton
	toggle.offset_top = -88
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
	_ability_panel.ability_activated.connect(_on_ability_activated)
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
	}
	for panel: PanelContainer in art_by_panel:
		var artwork: StyleBoxTexture = art_by_panel[panel]
		if artwork != null:
			panel.add_theme_stylebox_override("panel", artwork)
		elif not show_placeholder_guides:
			panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


func render(model: Dictionary) -> void:
	_model = model.duplicate(true)
	_rules.render(_model)
	_render_header()
	_render_context_and_piles()
	_render_fields()
	_render_seats()
	_render_phase_controls()
	_render_abilities()
	_render_connection_state()
	$RoundReveal.render(_model)


func _process(_delta: float) -> void:
	if _timer_local_deadline_msec >= 0:
		_update_timer(maxi(0, _timer_local_deadline_msec - Time.get_ticks_msec()))


func handle_command_result(
	kind: StringName,
	accepted: bool,
	error_code: StringName,
	authoritative_phase: int
) -> void:
	_phase_controls.handle_command_result(kind, accepted, error_code, authoritative_phase)
	if kind == &"stage_manipulation" and not accepted:
		if _targeting_overlay.visible:
			_targeting_overlay.cancel(&"rejected")
		else:
			_phase_controls.clear_targeting()
			_clear_active_ability()
	elif kind == &"commit_manipulation":
		if accepted:
			_phase_controls.clear_targeting()
			_clear_active_ability()
		elif (
			authoritative_phase == int(_model.get("phase", -1))
			and _active_ability_still_legal()
		):
			_targeting_overlay.reopen()
		else:
			_phase_controls.clear_targeting()
			_clear_active_ability()


func _render_header() -> void:
	var phase_index := int(_model.get("phase", 0))
	_phase.text = PHASE_NAMES[phase_index] if phase_index >= 0 and phase_index < PHASE_NAMES.size() else "UNKNOWN"
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
	_clock_direction.text = (
		"Rise  →  Flourish  →  Fall"
		if direction >= 0
		else "Fall  ←  Flourish  ←  Rise"
	)
	var active_names: Array[String] = []
	for context in active_contexts:
		active_names.append(_context_name(int(context)))
	_clock_active.text = "ACTIVE  %s" % " + ".join(active_names)
	var counts: Dictionary = _model.get("pile_counts", {})
	for context in 3:
		var pile = get_node("Center/Piles/Pile%s" % _context_name(context))
		var count_label: Label = pile.get_node("Count")
		var data: Dictionary = counts.get(str(context), counts.get(context, {}))
		count_label.text = "%d left" % int(data.get("draw_count", 0)) if not data.is_empty() else "Hidden"
	_round_result.visible = bool(_model.get("last_round_nil", false))
	_round_result.text = "NIL ROUND  ·  no progress awarded" if _round_result.visible else ""


func _render_fields() -> void:
	for child in _field_rows.get_children():
		_field_rows.remove_child(child)
		child.queue_free()
	var catalog: Dictionary = _model.get("ability_catalog", {})
	var player_names := {}
	for player: Dictionary in _model.get("players", []):
		var player_id := str(player.get("player_id", ""))
		player_names[player_id] = str(player.get("name", player_id))
	for field in _model.get("active_fields", []):
		if not field is Dictionary:
			continue
		var ability_id := str(field.get("ability_id", "field"))
		var definition: Dictionary = catalog.get(ability_id, {})
		var field_name := str(definition.get("display_name", ability_id.replace("_", " ").capitalize()))
		var rules := str(definition.get("rules_text", ""))
		var source_id := str(field.get("source_player_id", "?"))
		var source_name := str(player_names.get(source_id, source_id))
		var duration_text := "Persistent" if bool(field.get("persistent", false)) else "%d round%s" % [
			int(field.get("remaining_rounds", 0)),
			"" if int(field.get("remaining_rounds", 0)) == 1 else "s",
		]
		var row := Button.new()
		row.flat = true
		row.clip_text = true
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.text = "%s  ·  %s  ·  by %s" % [field_name, duration_text, source_name]
		row.tooltip_text = rules
		if not rules.is_empty():
			row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			row.pressed.connect(_show_field_details.bind(field_name, rules))
		_field_rows.add_child(row)
	$Center/Fields/FieldScroll.visible = _field_rows.get_child_count() > 0
	$Center/Fields/Heading.text = "ACTIVE FIELDS  ·  SELECT FOR DETAILS" if _field_rows.get_child_count() > 0 else "ACTIVE FIELDS"


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
	var requests: Dictionary = _model.get("replacement_requests", {})
	_bottom_seat.render(
		local_player, [], int(_model.get("active_context", 0)),
		not private_id.is_empty() and str(local_player.get("player_id", "")) == private_id,
		_request_for(requests, local_player), false, _active_contexts()
	)
	var opponent_seats := [_top_seat, _left_seat, _right_seat]
	for index in opponent_seats.size():
		var player: Dictionary = opponents[index] if index < opponents.size() else {}
		opponent_seats[index].render(
			player, [], int(_model.get("active_context", 0)), false,
			_request_for(requests, player), true, _active_contexts()
		)
		opponent_seats[index].render_table_seat(player, int(_model.get("victory_mode", 0)))


func _active_contexts() -> Array:
	var result: Array = _model.get("active_contexts", [])
	if result.is_empty():
		result = [int(_model.get("active_context", 0))]
	return result


func _render_phase_controls() -> void:
	var has_private_player := not str(_model.get("private_player_id", "")).is_empty()
	_phase_controls.visible = has_private_player
	_bottom_seat.visible = not has_private_player
	$MatchScore.visible = has_private_player
	$SortControls.visible = has_private_player
	_position_cockpit()
	if not has_private_player:
		return
	_phase_controls.render(_model)
	_phase_controls.set_inputs_locked(bool(_model.get("frozen", false)))


func _position_cockpit() -> void:
	var ui_scale := maxf(0.25, minf(size.x / 1920.0, size.y / 1080.0))
	_phase_controls.position = Vector2(size.x * 0.188, size.y * 0.613)
	_phase_controls.scale = Vector2.ONE * ui_scale
	_phase_controls.size = Vector2(size.x * 0.649 / ui_scale, 410)
	_ability_panel.scale = Vector2.ONE * ui_scale
	_ability_panel.position = Vector2(size.x * 0.852, size.y * 0.765 - _ability_panel.size.y * ui_scale)
	var toggle: Button = $AbilityPanel/ToggleButton
	var drawer_top := -get_global_transform().origin.y
	var drawer_bottom := _ability_panel.position.y + (toggle.position.y - 8.0) * ui_scale
	var drawer_left := size.x * 0.844
	var drawer_right := size.x * 0.987
	var drawer_position := (Vector2(drawer_left, drawer_top) - _ability_panel.position) / ui_scale
	var drawer_size := Vector2(drawer_right - drawer_left, drawer_bottom - drawer_top) / ui_scale
	_ability_panel.set_drawer_bounds(Rect2(drawer_position, drawer_size))


func _on_sort_pressed(index: int) -> void:
	if _phase_controls.sort_hand(index):
		_selected_sort = index
	for i in 3:
		$SortControls.get_child(i).set_pressed_no_signal(i == _selected_sort)


func _clear_context_sort() -> void:
	_selected_sort = -1
	for i in 3:
		$SortControls.get_child(i).button_pressed = false


func _on_rank_sort_pressed() -> void:
	if not _phase_controls.toggle_rank_sort():
		return
	var ascending: bool = _phase_controls.rank_sort_ascending()
	$SortControls/Rank.text = "RANK ↑" if ascending else "RANK ↓"
	$SortControls/Rank.tooltip_text = "Top-half rank: low to high" if ascending else "Top-half rank: high to low"


func _render_abilities() -> void:
	var has_private_player := not str(_model.get("private_player_id", "")).is_empty()
	_ability_panel.visible = has_private_player
	if has_private_player:
		_ability_panel.render(
			_model.get("private_abilities", []), int(_model.get("phase", 0)),
			_model.get("ability_catalog", {}), bool(_model.get("frozen", false))
		)
	_render_ability_history()
	if not _active_ability.is_empty() and not _active_ability_still_legal():
		if _targeting_overlay.visible:
			_targeting_overlay.cancel(&"interrupted")
		else:
			_phase_controls.clear_targeting()
			_clear_active_ability()


func _render_ability_history() -> void:
	for child in _ability_history.get_children():
		_ability_history.remove_child(child)
		child.queue_free()
	for event in _model.get("recent_public_abilities", []):
		if not event is Dictionary:
			continue
		var row := Label.new()
		var source := str(event.get("source_player_id", "?"))
		var target := str(event.get("target_player_id", ""))
		row.text = "%s  ·  %s%s" % [
			str(event.get("ability_id", "ability")).replace("_", " ").capitalize(),
			source,
			(" → " + target) if not target.is_empty() else "",
		]
		_ability_history.add_child(row)
	$AbilityHistory.visible = _ability_history.get_child_count() > 0


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
	_phase_controls.set_inputs_locked(true)


func _on_ability_activated(copy_id: StringName, ability: Dictionary) -> void:
	_active_copy_id = copy_id
	_active_ability = ability.duplicate(true)
	var timing := int(ability.get("timing", -1))
	var workflow: Dictionary = ability.get("choice_schema", {})
	if timing == 0:
		intent_requested.emit(&"stage_manipulation", {"copy_id": str(copy_id)})
		_targeting_overlay.begin(workflow, _model.get("private_hand", []), _active_player_targets())
	elif workflow.get("steps", []).is_empty():
		intent_requested.emit(&"play_public_ability", {"copy_id": str(copy_id), "target_player_id": ""})
		_clear_active_ability()
	else:
		_targeting_overlay.begin(workflow, _model.get("private_hand", []), _active_player_targets())


func _on_targeting_commit_requested(choices: Dictionary) -> void:
	var timing := int(_active_ability.get("timing", -1))
	if timing == 0:
		intent_requested.emit(&"commit_manipulation", {"choices": choices.duplicate(true)})
	else:
		intent_requested.emit(&"play_public_ability", {
			"copy_id": str(_active_copy_id),
			"target_player_id": str(_single_choice(choices, "target_player_id", "")),
			"choices": choices.duplicate(true),
		})


func _active_player_targets() -> Array:
	var result: Array = []
	for player in _model.get("players", []):
		if not player is Dictionary: continue
		if bool(player.get("spectator", false)) or not bool(player.get("active", false)) or bool(player.get("pending", false)):
			continue
		result.append({"player_id": str(player.get("player_id", "")),
			"display_name": str(player.get("display_name", player.get("name", player.get("player_id", ""))))})
	return result


func _on_targeting_selection_changed(kind: StringName, eligible: Array, selected: Array) -> void:
	if kind in [&"card", &"full_card", &"half_card"]:
		_phase_controls.set_targeting(kind, eligible, selected)
	else:
		_phase_controls.clear_targeting()


func _on_targeting_closed(reason: StringName) -> void:
	_phase_controls.clear_targeting()
	if reason == &"cancelled" and int(_active_ability.get("timing", -1)) == 0:
		intent_requested.emit(&"cancel_manipulation", {})
	if reason != &"committed":
		_clear_active_ability()


func _on_half_target_requested(card_id: StringName, half_index: int) -> void:
	_targeting_overlay.select_value({"card_id": str(card_id), "half_index": half_index})


func _on_connection_action_pressed() -> void:
	connection_action_requested.emit(_connection_action)


func _active_ability_still_legal() -> bool:
	var timing := int(_active_ability.get("timing", -1))
	var phase := int(_model.get("phase", 0))
	var timing_allowed := (
		(timing == 0 and phase == 3) or (timing in [1, 3] and phase == 2)
		or (timing == 2 and phase in [2, 4])
	)
	if not timing_allowed:
		return false
	for ability in _model.get("private_abilities", []):
		if ability is Dictionary and StringName(ability.get("copy_id", "")) == _active_copy_id:
			return true
	return false


func _single_choice(choices: Dictionary, key: String, fallback: Variant) -> Variant:
	var values: Array = choices.get(key, [])
	return values[0] if not values.is_empty() else fallback


func _clear_active_ability() -> void:
	_active_copy_id = &""
	_active_ability.clear()


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
