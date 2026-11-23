extends Control

const Card := preload("res://src/view/match/card_widget.tscn")
const Events := preload("res://src/core/events/event_kinds.gd")
const Types := preload("res://src/core/common/game_types.gd")
const ContextArt := [
	preload("res://assets/artwork/context_emblems/context_emblem_rish.png"),
	preload("res://assets/artwork/context_emblems/context_emblem_flourish.png"),
	preload("res://assets/artwork/context_emblems/context_emblem_fall.png"),
]
const SuitArt := [
	preload("res://assets/artwork/card_suit_mountain.png"),
	preload("res://assets/artwork/card_suit_cloud.png"),
	preload("res://assets/artwork/card_suit_sea.png"),
]
const CONTEXT_COLORS := [Color("9edaff"), Color("bcf39c"), Color("ffb29a")]
const SABOTAGE_COLOR := Color("ff9a87")
const CARD_SIZE := Vector2(128, 136)

var _board := Rect2()
var _clock := Rect2()
var _seats: Dictionary = {}
var _pending: Array[Dictionary] = []
var _cue: Dictionary = {}
var _timeline: Tween
var _progress := 0.0
var _showing_after := false
var _cards: Array[CardWidget] = []
var _title := Label.new()
var _subtitle := Label.new()
var _glow: GradientTexture2D


func _ready() -> void:
	z_index = 24
	mouse_filter = MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
	_glow = GradientTexture2D.new()
	_glow.gradient = gradient
	_glow.width = 128
	_glow.height = 128
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial", "Liberation Sans", "DejaVu Sans"])
	for label in [_title, _subtitle]:
		label.mouse_filter = MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", font)
		label.add_theme_color_override("font_outline_color", Color("101724"))
		label.add_theme_constant_override("outline_size", 9)
		label.hide()
		add_child(label)
	_title.name = "EffectTitle"
	_subtitle.name = "EffectDetail"
	_title.add_theme_font_size_override("font_size", 31)
	_subtitle.add_theme_font_size_override("font_size", 21)


func set_regions(board: Rect2, clock: Rect2, seats: Dictionary) -> void:
	_board = board
	_clock = clock
	_seats = seats


func present(events: Array, model: Dictionary) -> void:
	var local_id := str(model.get("private_player_id", ""))
	var catalog: Dictionary = model.get("ability_catalog", {})
	var names := {}
	for player: Dictionary in model.get("players", []):
		names[str(player.get("player_id", ""))] = str(player.get("name", "Player"))
	var direction := int(model.get("context_direction", 1))
	for event in events:
		if event is Dictionary and StringName(event.get("kind", "")) == Events.CONTEXT_DIRECTION_CHANGED:
			var payload: Variant = event.get("payload")
			if payload is Dictionary:
				direction = int(payload.get("direction", direction))
	for event in events:
		if not event is Dictionary or not event.get("payload", {}) is Dictionary:
			continue
		var payload: Dictionary = event.get("payload", {})
		var ability_id := str(payload.get("ability_id", payload.get("source_definition_id", "")))
		var definition: Dictionary = catalog.get(ability_id, {})
		var name := str(definition.get("display_name", ability_id.capitalize()))
		var source := str(payload.get("source_player_id", ""))
		var target := str(payload.get("target_player_id", ""))
		var source_name := str(names.get(source, "Player"))
		var target_name := str(names.get(target, "Player"))
		var cue: Dictionary
		match StringName(event.get("kind", "")):
			Events.FIELD_PLAYED:
				cue = _field_cue(definition, name, source_name, direction)
			Events.FACTOR_MODIFIER_APPLIED:
				var delta := float(payload.get("numerator", 0)) / maxf(1.0, float(payload.get("denominator", 1)))
				var kind := "buff" if delta > 0.0 else "nerf"
				var detail := ""
				if local_id in [source, target] and not local_id.is_empty():
					detail = "%s  ·  %s %s" % [name, str(payload.get("category_id", "")).capitalize(),
						"%+.3f" % delta]
					detail = detail.rstrip("0").rstrip(".")
				cue = {"kind": kind, "title": "Buff applied" if delta > 0.0 else "Nerf applied",
					"detail": detail, "target": target,
					"color": Color("adf3bb") if delta > 0.0 else Color("ffb1a8")}
			Events.SABOTAGE_RESOLVED:
				cue = _sabotage_cue(payload, definition, name, source_name, target_name, local_id)
			Events.MANIPULATION_RESOLVED:
				if not local_id.is_empty() and source == local_id:
					var changes: Array = payload.get("card_changes", [])
					cue = {"kind": "manipulation", "title": name,
						"detail": "Your cards changed" if not changes.is_empty() else "Your cards stayed the same",
						"target": source, "color": Color("d4bbff"), "changes": changes}
		if not cue.is_empty():
			_pending.append(cue)
	if _cue.is_empty() and not _pending.is_empty():
		_start_next()


func _field_cue(definition: Dictionary, name: String, caster: String, direction: int) -> Dictionary:
	var style := str(definition.get("effect_id", ""))
	if style == "field_rule":
		style = str(definition.get("field_rule", ""))
	var context := int(definition.get("context_emblem", -1))
	var suit := int(definition.get("suit_emblem", -1))
	var accent: Color = CONTEXT_COLORS[context] if context in [0, 1, 2] else Color("ffe3a6")
	var detail := "Field effect applied"
	match style:
		"context_jump": detail = "Clock moves to %s" % Types.context_name(context)
		"reverse_direction": detail = "Clock direction reversed"
		"additional_context": detail = "%s also active this round" % Types.context_name(context)
		"per_selected_suit": detail = "%s halves boost the field multiplier" % Types.suit_name(suit)
		"per_selected_rank_set": detail = "Matching ranks boost the field multiplier"
		"leading_context": detail = "%s boosts the field multiplier when tied for most or leading" % Types.context_name(context)
	return {"kind": "field", "style": style, "title": name, "detail": "%s  ·  %s" % [caster, detail],
		"color": accent, "context": context, "suit": suit, "direction": direction}


func _sabotage_cue(
	payload: Dictionary, definition: Dictionary, name: String,
	source_name: String, target_name: String, local_id: String
) -> Dictionary:
	var source := str(payload.get("source_player_id", ""))
	var target := str(payload.get("target_player_id", ""))
	var participants := "%s → %s" % [source_name, target_name]
	var cue := {"kind": "sabotage", "source": source, "target": target,
		"title": "Sabotage", "detail": participants, "color": SABOTAGE_COLOR}
	var victim := not local_id.is_empty() and local_id == target and payload.has("card_changes")
	var attacker := not local_id.is_empty() and local_id == source and payload.has("success")
	if not victim and not attacker:
		return {} if payload.has("card_changes") or payload.has("success") or (
			not local_id.is_empty() and local_id in [source, target]
		) else cue

	var operation := str(definition.get("operation", ""))
	if str(definition.get("effect_id", "")) == "force_redraw":
		operation = "redraw"
	var description: String = {
		"redraw": "Replace a full card",
		"exchange_contexts": "Exchange two cards’ contexts",
		"randomize_suit": "Scramble a half’s suit",
		"randomize_rank": "Scramble a half’s rank",
		"randomize_context": "Scramble a half’s context",
		"nudge_rank": "Move a half’s rank one step",
		"nudge_context": "Move a half’s context one step",
		"swap_halves": "Swap halves between two cards",
		"lock_card": "Lock a card for this round",
	}.get(operation, "Card effect")
	if victim and bool(payload.get("no_eligible_half", false)):
		description = "No eligible half"
	elif victim and not bool(payload.get("changed", true)):
		description = "Your cards stayed the same"
	cue["title"] = name
	cue["detail"] = "%s  ·  %s" % [participants, description]
	cue["operation"] = operation
	if victim:
		cue["changes"] = payload.card_changes
	else:
		# An attacker's demonstration uses card backs and the ability's public rules.
		var count := 2 if operation in ["exchange_contexts", "swap_halves"] else 1
		var changes: Array = []
		changes.resize(count)
		changes.fill({})
		cue["changes"] = changes
		cue["masked"] = true
	return cue


func _start_next() -> void:
	_cue = _pending.pop_front()
	_showing_after = false
	_title.text = _cue.title
	_title.add_theme_color_override("font_color", _cue.color)
	_title.add_theme_font_size_override("font_size", 24 if _cue.kind in ["buff", "nerf"] else 31)
	_subtitle.text = _cue.detail
	_title.show()
	_subtitle.visible = not _subtitle.text.is_empty()
	var changes: Array = _cue.get("changes", [])
	for change: Dictionary in changes:
		var card := Card.instantiate() as CardWidget
		add_child(card)
		card.custom_minimum_size = CARD_SIZE
		card.size = CARD_SIZE
		card.pivot_offset = CARD_SIZE * 0.5
		_render_card(card, change, false)
		_cards.append(card)
	_animate(0.0)
	var duration := 2.4 if not changes.is_empty() else 1.65
	if _cue.kind in ["buff", "nerf"]:
		duration = 1.35
	_timeline = create_tween()
	_timeline.tween_method(_animate, 0.0, 1.0, duration)
	_timeline.tween_callback(_finish)


func _animate(progress: float) -> void:
	_progress = progress
	var opacity := _opacity()
	var kind: String = _cue.kind
	var board_center := _board.get_center()
	var caption_height := 0.27 if not _cards.is_empty() else 0.51
	var caption := Vector2(board_center.x, _board.position.y + _board.size.y * caption_height)
	if kind in ["buff", "nerf"]:
		var target := _seat(str(_cue.get("target", "")))
		var sign_y := -1 if kind == "buff" else 1
		caption = Vector2(target.get_center().x, target.position.y - 46.0 + sign_y * 20.0 * progress)
	_place_caption(_title, caption, opacity)
	_place_caption(_subtitle, caption + Vector2(0.0, 36.0), opacity)
	if not _cards.is_empty():
		_animate_cards(opacity)
	queue_redraw()


func _animate_cards(opacity: float) -> void:
	var operation := str(_cue.get("operation", ""))
	var changes: Array = _cue.changes
	if _progress >= 0.5 and not _showing_after:
		_showing_after = true
		for index in _cards.size():
			_render_card(_cards[index], changes[index], true)
	var spacing := CARD_SIZE.x + 12.0
	var anchor := Vector2(_board.get_center().x - CARD_SIZE.x / 2.0, _board.position.y + _board.size.y * 0.39)
	for index in _cards.size():
		var card := _cards[index]
		var order := index - (_cards.size() - 1) / 2.0
		var p := clampf((_progress - 0.29) / 0.42, 0.0, 1.0)
		var motion := sin(p * PI)
		var offset := Vector2(order * spacing, 18.0 * (1.0 - opacity))
		if operation in ["swap_halves", "exchange_contexts"]:
			offset += Vector2(-order * 104.0, 25.0 * order) * motion
		elif operation == "redraw":
			offset.x += -135.0 * p if p < 0.5 else 135.0 * (1.0 - p)
		elif operation in ["nudge_rank", "nudge_context"]:
			offset.y -= 23.0 * motion
		card.position = anchor + offset
		card.scale.x = 1.0 if operation == "lock_card" else maxf(0.08, absf(cos(p * PI)))
		card.rotation = (0.12 * sin(p * TAU) if operation == "redraw" else 0.0)
		card.modulate.a = opacity


func _render_card(card: CardWidget, change: Dictionary, resolved: bool) -> void:
	var masked := bool(_cue.get("masked", false))
	var faces: Dictionary = change.get("after" if resolved else "before", {})
	var settings := {"interaction_disabled": true, "display_only": true, "select_in_place": true}
	var half_index := int(change.get("half_index", -1))
	if _cue.get("operation") == "lock_card" and resolved:
		settings["targeting_selected"] = true
	elif not masked and half_index in [0, 1]:
		settings["targeting_kind"] = &"half_card"
		settings["targeting_half_eligible"] = [true, true]
		settings["targeting_half_selected"] = [half_index == 0, half_index == 1]
	card.visible = masked or not faces.is_empty()
	card.render(faces, -1, masked, settings)
	_ignore_input(card)


func _draw() -> void:
	if _cue.is_empty():
		return
	var tint: Color = _cue.color
	var opacity := _opacity()
	var energy := sin(_progress * PI) * opacity
	match str(_cue.kind):
		"field": _draw_field(tint, opacity, energy)
		"buff", "nerf":
			var bounds := _seat(str(_cue.target))
			var sign_y := -1 if _cue.kind == "buff" else 1
			var drift := Vector2(0.0, sign_y * 42.0 * _progress)
			_aura(bounds.grow(26.0), tint, energy * 0.5, drift)
		"sabotage":
			var start := _seat(str(_cue.source)).get_center()
			var target := _seat(str(_cue.target))
			var end := target.get_center()
			var travel := clampf(_progress / 0.52, 0.0, 1.0)
			var head := start.lerp(end, travel)
			var tail := start.lerp(end, maxf(0.0, travel - 0.22))
			draw_line(tail, head, Color(tint, opacity * (1.0 - smoothstep(0.46, 0.68, _progress))), 3.0, true)
			_aura(target.grow(24.0), tint, energy * 0.48 * smoothstep(0.2, 0.54, _progress))
		"manipulation":
			_aura(_seat(str(_cue.target)), tint, energy * 0.4)
	if not _cards.is_empty():
		var bounds := Rect2(_board.get_center().x - 500.0,
			_board.position.y + _board.size.y * 0.2, 1000.0, 235.0)
		_aura(bounds, tint, energy * 0.6)


func _draw_field(tint: Color, opacity: float, energy: float) -> void:
	var style := str(_cue.style)
	var context := int(_cue.context)
	var suit := int(_cue.suit)
	if style in ["context_jump", "reverse_direction", "additional_context"]:
		var center := _clock.get_center()
		if style == "reverse_direction":
			var angle := float(_cue.direction) * TAU * _progress - PI / 2.0
			draw_arc(center, _clock.size.x * 0.39, angle, angle + float(_cue.direction) * 1.45,
				30, Color(tint, energy), 6.0, true)
			_aura(_clock, tint, energy * 0.65)
		elif context in [0, 1, 2]:
			var points := [Vector2(0.494, 0.18), Vector2(0.762, 0.65), Vector2(0.225, 0.65)]
			var spot: Vector2 = _clock.position + _clock.size * points[context]
			if style == "context_jump":
				var head := center.lerp(spot, smoothstep(0.0, 0.4, _progress))
				draw_line(center, head, Color(tint, energy * 0.9), 5.0, true)
			var pulse := energy if style == "context_jump" else energy * (0.45 + 0.55 * absf(sin(_progress * TAU)))
			_aura(Rect2(spot - Vector2(78, 78), Vector2(156, 156)), tint, pulse)
		return
	var center := _board.get_center()
	if style == "per_selected_rank_set":
		for index in 3:
			var band := fposmod(_progress + index * 0.22, 1.0)
			_aura(Rect2(_board.position.x, center.y - 70.0 + band * 200.0, _board.size.x, 105.0),
				tint, energy * 0.64 * sin(PI * band))
	else:
		var spread := Vector2(_board.size.x * 0.82, _board.size.y * 0.9).lerp(_board.size, _progress)
		_aura(Rect2(center - spread * 0.5, spread), tint, energy * 0.86)
		var art: Texture2D = null
		if style == "per_selected_suit" and suit in [0, 1, 2]:
			art = SuitArt[suit]
		elif style == "leading_context" and context in [0, 1, 2]:
			art = ContextArt[context]
		if art != null:
			var icon_size := Vector2.ONE * lerpf(52.0, 82.0, _progress)
			var icon_position := center - Vector2(0.0, 45.0) - icon_size / 2.0
			draw_texture_rect(art, Rect2(icon_position, icon_size), false, Color(tint, opacity))


func _aura(bounds: Rect2, tint: Color, strength: float, offset := Vector2.ZERO) -> void:
	if bounds.has_area() and strength > 0.0:
		draw_texture_rect(_glow, Rect2(bounds.position + offset, bounds.size), false, Color(tint, strength))


func _seat(id: String) -> Rect2:
	return _seats.get(id, Rect2(_board.get_center() - Vector2(100, 46), Vector2(200, 92)))


func _place_caption(label: Label, center: Vector2, alpha: float) -> void:
	label.reset_size()
	var half_width := label.size.x * 0.5
	var safe_x := clampf(center.x, half_width + 12.0, maxf(half_width + 12.0, size.x - half_width - 12.0))
	label.position = Vector2(safe_x - half_width, maxf(4.0, center.y - label.size.y / 2.0))
	label.modulate.a = alpha


func _opacity() -> float:
	return smoothstep(0.0, 0.12, _progress) * (1.0 - smoothstep(0.77, 1.0, _progress))


func _ignore_input(node: Control) -> void:
	node.mouse_filter = MOUSE_FILTER_IGNORE
	node.focus_mode = FOCUS_NONE
	for child in node.get_children():
		if child is Control:
			_ignore_input(child)


func _finish() -> void:
	_title.hide()
	_subtitle.hide()
	for card in _cards:
		card.hide()
		card.queue_free()
	_cards.clear()
	_cue.clear()
	queue_redraw()
	if not _pending.is_empty():
		_start_next()
