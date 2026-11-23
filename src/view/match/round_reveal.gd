extends PanelContainer

signal sound_requested(cue: StringName)

const Card := preload("res://src/view/match/card_widget.tscn")
const Types := preload("res://src/core/common/game_types.gd")
const ScoringReference := preload("res://src/view/app/scoring_reference.gd")
const REVEAL_SECONDS := 0.60
const COUNT_SECONDS := 1.25
const HOLD_SECONDS := Types.MAIN_2_REVIEW_MSEC_PER_PLAYER / 1000.0 - REVEAL_SECONDS - COUNT_SECONDS
const SCORE_TICKS := 4
const SCORE_MILESTONE := 100.0
const MAX_SCORE_GROWTH := 0.25
const SCORE_PULSE_GROWTH := 0.19
const SCORE_SHAKE_DISTANCE := 7.0
const SCORE_POWER_COLORS := [
	Color("ffd166"), Color("ffad5a"), Color("ff8780"),
	Color("e4a1ff"), Color("8fcfff"), Color("8cebd1"),
]

var _sequence: Tween
var _reveal_round := -1
var _award_round := -1
var _players := {}
var _player_labels := {}
var _private_player_id := ""
var _selected_player_id := ""
var _context := 0
var _score_progress := 1.0
var _last_score_tick := -1
var _last_milestone := 0
var _score_tier := 0
var _score_energy := 0.0
var _score_pulse: Tween
var _selected_tab_style: StyleBoxFlat
var _scoring_catalog: Dictionary = {}

@onready var _headline: Label = $Content/Headline
@onready var _navigation: HBoxContainer = $Content/Navigation
@onready var _player_buttons: HBoxContainer = $Content/Navigation/Players
@onready var _cards: HBoxContainer = $Content/Cards
@onready var _hand_name: Label = $Content/HandName
@onready var _score_prefix: Label = $Content/ScoreLine/Prefix
@onready var _score_slot: Control = $Content/ScoreLine/ValueSlot
@onready var _score_value: Label = $Content/ScoreLine/ValueSlot/Value
@onready var _score_unit: Label = $Content/ScoreLine/Unit


func _ready() -> void:
	_score_value.resized.connect(_center_score_pivot)
	_center_score_pivot()
	_selected_tab_style = StyleBoxFlat.new()
	_selected_tab_style.bg_color = Color("324656")
	_selected_tab_style.border_color = Color("ffd166")
	_selected_tab_style.border_width_bottom = 2
	_selected_tab_style.set_corner_radius_all(4)


func render(model: Dictionary) -> void:
	var phase := int(model.get("phase", -1))
	var round_id := int(model.get("round_number", 0))
	if phase == Types.Phase.MAIN_2:
		_render_submissions(model, round_id)
		return
	_hand_name.hide()
	if _navigation.visible:
		_stop()
		_navigation.hide()
	# The local discard controls use the review area during End.
	if phase == Types.Phase.END and not str(model.get("private_player_id", "")).is_empty():
		_stop()
		return
	if phase in [Types.Phase.END, Types.Phase.START]:
		var history: Array = model.get("public_history", [])
		for idx in range(history.size() - 1, -1, -1):
			var event: Dictionary = history[idx]
			if event.get("kind") != "round_finalized":
				continue
			var scored_round := int(event.payload.get("round_number", event.get("round_number", 0)))
			if scored_round <= _award_round or scored_round < round_id - 1:
				break
			if phase == Types.Phase.START and _award_round < 0 and _reveal_round != scored_round:
				break
			_award_round = scored_round
			_show_award(event.payload, model)
			break
	else:
		_stop()


func _render_submissions(model: Dictionary, round_id: int) -> void:
	var players: Array = model.get("players", []).filter(func(player: Dictionary):
		return player.has("revealed_submission"))
	if players.is_empty():
		_stop()
		_navigation.hide()
		return
	players.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.seat_index) < int(b.seat_index))
	var previous_submission := _selected_submission()
	var previous_context := _context
	var catalog: Dictionary = model.get("scoring_catalog", {})
	if not catalog.is_empty():
		_scoring_catalog = catalog
	elif _scoring_catalog.is_empty():
		_scoring_catalog = ScoringReference.default_catalog()
	_context = int(model.get("active_context", 0))
	_private_player_id = str(model.get("private_player_id", ""))
	_players.clear()
	var labels := {}
	for player: Dictionary in players:
		var id := str(player.get("player_id", ""))
		var display_name := str(player.get("name", id))
		_players[id] = player.revealed_submission
		labels[id] = "%s (You)" % display_name if id == _private_player_id else display_name
	if labels != _player_labels or labels.keys() != _player_labels.keys():
		_player_labels = labels
		_render_player_buttons()

	_headline.hide()
	_navigation.show()
	_hand_name.show()
	_cards.show()
	show()
	if round_id != _reveal_round:
		_reveal_round = round_id
		_start_reveal()
	elif not _players.has(_selected_player_id):
		_select_player(_preferred_player())
	else:
		if previous_submission.get("cards") != _selected_submission().get("cards") or previous_context != _context:
			_render_cards()
		_update_selection()
		_update_hand_name()
		_render_score()


func _render_player_buttons() -> void:
	_clear_children(_player_buttons)
	for player_id: String in _player_labels:
		var button := Button.new()
		button.text = _player_labels[player_id]
		button.tooltip_text = button.text
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_stylebox_override("pressed", _selected_tab_style)
		button.add_theme_color_override("font_pressed_color", Color("ffd166"))
		button.pressed.connect(_inspect_player.bind(player_id))
		_player_buttons.add_child(button)


func _start_reveal() -> void:
	_stop_sequence()
	var player_ids := _players.keys()
	_select_player(player_ids[0], true)
	_sequence = create_tween()
	for index in player_ids.size():
		if index > 0:
			_sequence.tween_callback(_select_player.bind(player_ids[index], true))
		_sequence.tween_method(_fade_hand, 0.0, 1.0, REVEAL_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_sequence.tween_method(_count_score, 0.0, 1.0, COUNT_SECONDS)
		_sequence.tween_callback(_finish_score_count)
		_sequence.tween_interval(HOLD_SECONDS)
	_sequence.tween_callback(_finish_reveal)


func _count_score(progress: float) -> void:
	_score_progress = progress
	var submission := _selected_submission()
	_render_score()
	if int(submission.get("provisional_score", 0)) > 0 and not submission.get("cards", []).is_empty():
		var tick := mini(floori(progress * SCORE_TICKS), SCORE_TICKS - 1)
		if _score_tier > _last_milestone:
			for _milestone in range(_last_milestone, _score_tier):
				sound_requested.emit(&"score_milestone")
			_last_milestone = _score_tier
			_start_score_pulse()
		elif tick > _last_score_tick:
			sound_requested.emit(&"score")
		_last_score_tick = maxi(_last_score_tick, tick)


func _start_score_pulse() -> void:
	_stop_score_pulse()
	_apply_score_power(1.0)
	_score_pulse = create_tween()
	_score_pulse.tween_method(_apply_score_power, 1.0, 0.0, 0.30)


func _apply_score_power(energy: float) -> void:
	_score_energy = energy
	var growth := minf(float(_score_tier) * 0.065, MAX_SCORE_GROWTH)
	_score_value.scale = Vector2.ONE * (1.0 + growth + SCORE_PULSE_GROWTH * energy)
	_score_value.position.x = sin((1.0 - energy) * TAU * 3.0) * SCORE_SHAKE_DISTANCE * energy
	var tint: Color = SCORE_POWER_COLORS[_score_tier % SCORE_POWER_COLORS.size()]
	_score_value.self_modulate = tint.lerp(Color.WHITE, 0.20 * energy)


func _center_score_pivot() -> void:
	_score_value.pivot_offset = _score_value.size * 0.5


func _stop_score_pulse() -> void:
	if _score_pulse != null:
		_score_pulse.kill()
	_score_pulse = null
	_score_energy = 0.0


func _finish_score_count() -> void:
	var breakdown: Dictionary = _selected_submission().get("score_breakdown", {})
	for key in ["card_hand_factor", "context_hand_factor", "field_factor"]:
		var factor: Dictionary = breakdown.get(key, {})
		if int(factor.get("numerator", 1)) > int(factor.get("denominator", 1)):
			sound_requested.emit(&"score_multiplier")
			return


func _fade_hand(progress: float) -> void:
	_cards.modulate.a = progress
	_hand_name.modulate.a = progress


func _finish_reveal() -> void:
	_select_player(_preferred_player())


func _preferred_player() -> String:
	return _private_player_id if _players.has(_private_player_id) else str(_players.keys()[0])


func _inspect_player(player_id: String) -> void:
	_stop_sequence()
	_select_player(player_id)


func _select_player(player_id: String, animate_score: bool = false) -> void:
	if not _players.has(player_id):
		return
	_selected_player_id = player_id
	_score_progress = 0.0 if animate_score else 1.0
	_last_score_tick = -1
	_last_milestone = 0
	_stop_score_pulse()
	_render_cards()
	_update_selection()
	_update_hand_name()
	_fade_hand(0.0 if animate_score else 1.0)
	_render_score()
	if animate_score and not _selected_submission().get("cards", []).is_empty():
		sound_requested.emit(&"reveal")


func _selected_submission() -> Dictionary:
	return _players.get(_selected_player_id, {})


func _update_selection() -> void:
	var player_ids := _player_labels.keys()
	for index in player_ids.size():
		_player_buttons.get_child(index).set_pressed_no_signal(player_ids[index] == _selected_player_id)


func _render_cards() -> void:
	_clear_children(_cards)
	for data: Dictionary in _selected_submission().get("cards", []):
		var widget := Card.instantiate() as CardWidget
		_cards.add_child(widget)
		widget.custom_minimum_size = Vector2(112, 104)
		widget.render(data, _context, false, {"interaction_disabled": true, "display_only": true})
		var first_face := widget.first_face_text()
		var second_face := widget.second_face_text()
		widget.tooltip_text = "Scored: %s\nOther half: %s" % (
			[second_face, first_face] if widget.active_half_index == 1 else [first_face, second_face]
		)


func _update_hand_name() -> void:
	var submission := _selected_submission()
	if submission.get("cards", []).is_empty():
		_hand_name.text = ""
		return
	var breakdown: Dictionary = submission.get("score_breakdown", {})
	var shapes := PackedStringArray()
	for component: Dictionary in breakdown.get("card_hand_components", []):
		var id := str(component.get("source_definition_id", component.get("category_id", "")))
		if not id.is_empty():
			shapes.append(_pattern_name("normal", id))
	if shapes.is_empty():
		var normal_id := str(submission.get("normal_category", ""))
		shapes.append("Submitted Hand" if normal_id.is_empty() else _pattern_name("normal", normal_id))
	var contexts: Array = breakdown.get("context_hand_components", [])
	var context_id := str(submission.get("context_category", ""))
	if not contexts.is_empty():
		context_id = str(contexts[0].get("source_definition_id", context_id))
	_hand_name.text = " + ".join(shapes)
	if context_id not in ["", "no_context", "no_context_pattern"]:
		_hand_name.text += "  ×  %s" % _pattern_name("context", context_id)


func _pattern_name(group: String, id: String) -> String:
	for entry: Dictionary in _scoring_catalog.get(group, []):
		if str(entry.get("id", "")) == id:
			return str(entry.get("display_name", id.capitalize()))
	return id.capitalize()


func _render_score() -> void:
	var submission := _selected_submission()
	var cards: Array = submission.get("cards", [])
	if cards.is_empty():
		_show_score_message("Passed · 0 points")
		return
	var breakdown: Dictionary = submission.get("score_breakdown", {})
	var factors := ""
	if not breakdown.is_empty():
		factors = "%d × %s × %s × %s =" % [
			int(breakdown.get("base_value", 0)), _ratio(breakdown.get("card_hand_factor", {})),
			_ratio(breakdown.get("context_hand_factor", {})), _ratio(breakdown.get("field_factor", {})),
		]
	var total := int(submission.get("provisional_score", 0))
	var points := roundi(_score_progress * float(total))
	_score_prefix.text = factors
	_score_prefix.visible = not factors.is_empty()
	_score_slot.show()
	_score_unit.show()
	_score_value.text = str(points)
	var font := _score_value.get_theme_font("font")
	var font_size := _score_value.get_theme_font_size("font_size")
	var final_digits_width := font.get_string_size(str(total), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var max_scale := 1.0 + MAX_SCORE_GROWTH + SCORE_PULSE_GROWTH
	_score_slot.custom_minimum_size.x = ceilf(final_digits_width * max_scale) + SCORE_SHAKE_DISTANCE * 2.0
	_score_tier = maxi(0, floori(float(points) / SCORE_MILESTONE))
	_apply_score_power(_score_energy)


func _show_score_message(message: String) -> void:
	_score_prefix.text = message
	_score_prefix.show()
	_score_slot.hide()
	_score_unit.hide()


func _ratio(factor: Dictionary) -> String:
	var numerator := int(factor.get("numerator", 1))
	var denominator := int(factor.get("denominator", 1))
	return str(numerator) if denominator == 1 else "%d/%d" % [numerator, denominator]


func _show_award(result: Dictionary, model: Dictionary) -> void:
	_stop()
	_clear_children(_cards)
	_cards.hide()
	var winner := str(result.get("winner_id", ""))
	_headline.text = "Tied round" if winner.is_empty() else "Round winner"
	_headline.show()
	var message := "No match progress awarded"
	for player: Dictionary in model.get("players", []):
		if str(player.get("player_id", "")) == winner:
			var points := int(result.get("scores", {}).get(winner, 0))
			var award := "+1 win" if int(model.get("victory_mode", 0)) == 1 else "+%d points" % points
			message = "%s  %s" % [player.get("name", "Player"), award]
			break
	_show_score_message(message)
	show()
	_sequence = create_tween()
	_sequence.tween_interval(2.3)
	_sequence.tween_callback(hide)


func _clear_children(container: Control) -> void:
	for node in container.get_children():
		container.remove_child(node)
		node.queue_free()


func _stop() -> void:
	_stop_sequence()
	_stop_score_pulse()
	hide()


func _stop_sequence() -> void:
	if _sequence != null:
		_sequence.kill()
	_sequence = null
