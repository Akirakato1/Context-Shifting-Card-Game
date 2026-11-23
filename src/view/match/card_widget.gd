class_name CardWidget
extends PanelContainer

signal primary_clicked(card_id: StringName)
signal orientation_requested(card_id: StringName)
signal half_choice_requested(card_id: StringName, half_index: int)
signal half_target_requested(card_id: StringName, half_index: int)
signal joker_choice_changed(card_id: StringName, half_index: int, context: int, suit: int)
signal reorder_requested(card_id: StringName, delta: int)
signal card_hovered
signal interaction_rejected

const GameTypes = preload("res://src/core/common/game_types.gd")
const RANK_INK := preload("res://src/view/match/rank_ink.tres")
const HOVER_AURA := preload("res://src/view/match/hover_card_aura.tres")
const PRIMED_AURA := preload("res://src/view/match/primed_card_aura.tres")
const CARD_ART_REGION := Rect2(130, 130, 1740, 2610)
const DIVIDER_ART := preload("res://assets/artwork/card/card_divider.png")
const BACK_ART := preload("res://assets/artwork/card/card_back.png")
const CONTEXT_ART := {
	GameTypes.Context.RISE: preload("res://assets/artwork/card/card_half_context_rise.png"),
	GameTypes.Context.FLOURISH: preload("res://assets/artwork/card/card_half_context_flourish.png"),
	GameTypes.Context.FALL: preload("res://assets/artwork/card/card_half_context_fall.png"),
}

## Optional transparent 2:3 frame over the front of the card.
@export var frame_art: Texture2D
## Optional replacement frame while the card is staged for submission.
@export var selected_frame_art: Texture2D
## Suit artwork in Mountain, Cloud, and Sea order.
@export var suit_icons: Array[Texture2D]

var card_id := ""
var active_half_index := -1
var face_down := false
var interaction_disabled := false
var orientation_flipped := false
var targeting_eligible := false
var targeting_selected := false
var targeting_kind: StringName = &""
var targeting_half_eligible: Array[bool] = [false, false]
var targeting_half_selected: Array[bool] = [false, false]
var _card: Dictionary = {}
var _staged := false
var _select_in_place := false
var _first_debug_text := ""
var _second_debug_text := ""
var _drag_hand: Control
var _left_click_pending := false
var _hover_enabled := false
var _hovered := false

@onready var _artwork: Control = $Artwork
@onready var _top_art: TextureRect = $Artwork/TopHalf
@onready var _bottom_art: TextureRect = $Artwork/BottomHalf
@onready var _art_divider: TextureRect = $Artwork/Divider
@onready var _back: TextureRect = $Back
@onready var _frame: TextureRect = $Frame
@onready var _face: Control = $Face
@onready var _first: TextureRect = $Face/First
@onready var _first_rank_art: HBoxContainer = $Face/FirstRankArt
@onready var _second: TextureRect = $Face/Second
@onready var _second_rank_art: HBoxContainer = $Face/SecondRankArt
@onready var _first_choices: HBoxContainer = $Face/FirstChoices
@onready var _first_context: OptionButton = $Face/FirstChoices/Context
@onready var _first_suit: OptionButton = $Face/FirstChoices/Suit
@onready var _second_choices: HBoxContainer = $Face/SecondChoices
@onready var _second_context: OptionButton = $Face/SecondChoices/Context
@onready var _second_suit: OptionButton = $Face/SecondChoices/Suit
@onready var _order_controls: HBoxContainer = $Face/OrderControls
@onready var _move_left: Button = $Face/OrderControls/MoveLeft
@onready var _move_right: Button = $Face/OrderControls/MoveRight
@onready var _aura: Node2D = $Aura


func _ready() -> void:
	var context_names := [
		GameTypes.context_name(GameTypes.Context.RISE),
		GameTypes.context_name(GameTypes.Context.FLOURISH),
		GameTypes.context_name(GameTypes.Context.FALL),
	]
	_populate_choices(_first_context, context_names)
	_populate_choices(_second_context, context_names)
	var suit_names := _suit_names()
	_populate_choices(_first_suit, suit_names)
	_populate_choices(_second_suit, suit_names)
	_art_divider.texture = _artwork_region(DIVIDER_ART)
	_back.texture = _artwork_region(BACK_ART)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_aura.draw.connect(_draw_aura)
	resized.connect(_aura.queue_redraw)


func render(
	card: Dictionary,
	active_context: int = -1,
	hidden: bool = false,
	view_state: Dictionary = {}
) -> void:
	_card = card.duplicate(true)
	card_id = str(card.get("card_id", ""))
	face_down = hidden
	_hover_enabled = not hidden and bool(view_state.get("hover_enabled", false))
	if not _hover_enabled:
		_hovered = false
	_aura.queue_redraw()
	interaction_disabled = bool(view_state.get("interaction_disabled", hidden))
	orientation_flipped = bool(view_state.get("orientation_flipped", false))
	_staged = bool(view_state.get("staged", false))
	_select_in_place = bool(view_state.get("select_in_place", false))
	_drag_hand = view_state.get("drag_hand") as Control
	_left_click_pending = false
	for label in [_first, _second]:
		if _select_in_place:
			label.add_theme_font_size_override("font_size", 23)
		else:
			label.remove_theme_font_size_override("font_size")
	targeting_eligible = bool(view_state.get("targeting_eligible", false))
	targeting_selected = bool(view_state.get("targeting_selected", false))
	targeting_kind = StringName(view_state.get("targeting_kind", ""))
	targeting_half_eligible.assign(view_state.get(
		"targeting_half_eligible", [false, false]
	))
	targeting_half_selected.assign(view_state.get(
		"targeting_half_selected", [false, false]
	))
	_update_cursor(bool(view_state.get("display_only", false)))
	_order_controls.visible = bool(view_state.get("reorder_enabled", false)) and not hidden
	_move_left.disabled = interaction_disabled
	_move_right.disabled = interaction_disabled
	_back.visible = hidden
	_face.visible = not hidden
	_artwork.visible = not hidden
	var staged_in_place := _select_in_place and _staged
	_frame.texture = selected_frame_art if staged_in_place and selected_frame_art != null else frame_art
	_frame.visible = not hidden and _frame.texture != null
	_first_choices.visible = false
	_second_choices.visible = false
	active_half_index = -1
	if targeting_selected:
		modulate = Color.WHITE
	elif targeting_eligible:
		modulate = Color("77e8ff")
	elif interaction_disabled and not hidden and not bool(view_state.get("display_only", false)):
		modulate = Color("8290a0")
	else:
		modulate = Color.WHITE
	if hidden:
		return
	var first: Dictionary = card.get("first", {})
	var second: Dictionary = card.get("second", {})
	var active_contexts: Array = view_state.get("active_contexts", [])
	if active_contexts.is_empty() and active_context >= 0:
		active_contexts = [active_context]
	var resolved_halves: Array = card.get("halves", [])
	if resolved_halves.size() >= 2:
		first = _resolved_half(resolved_halves[0])
		second = _resolved_half(resolved_halves[1])
		if not view_state.has("orientation_flipped"):
			orientation_flipped = int(card.get("selected_half_index", 0)) == 1
	_first_debug_text = _half_text(first)
	_second_debug_text = _half_text(second)
	_render_rank_art(_first_rank_art, _half_rank(first))
	_render_rank_art(_second_rank_art, _half_rank(second))
	if card.has("selected_half_index"):
		active_half_index = int(card["selected_half_index"])
	elif view_state.has("selected_half_index"):
		active_half_index = int(view_state["selected_half_index"])
	elif _half_matches_contexts(first, active_contexts):
		active_half_index = 0
	elif _half_matches_contexts(second, active_contexts):
		active_half_index = 1
	_apply_joker_choices(first, second, view_state)
	_render_suit(_first, first, _first_choices, _first_suit)
	_render_suit(_second, second, _second_choices, _second_suit)
	for selector in [_first_context, _first_suit, _second_context, _second_suit]:
		selector.disabled = interaction_disabled
	_apply_orientation()
	_apply_context_art(first, second)
	_apply_active_style()
	_apply_half_targeting_style()


func _update_cursor(display_only: bool) -> void:
	var pointer := Control.CURSOR_ARROW
	if not face_down:
		if targeting_eligible or targeting_half_eligible.has(true):
			pointer = Control.CURSOR_CROSS
		elif _drag_hand != null or not interaction_disabled:
			pointer = Control.CURSOR_POINTING_HAND
		elif not targeting_kind.is_empty() or (_hover_enabled and not display_only):
			pointer = Control.CURSOR_FORBIDDEN
	mouse_default_cursor_shape = pointer
	for half_index in 2:
		var area: Control = get_node("Face/FirstHit" if half_index == 0 else "Face/SecondHit")
		area.mouse_default_cursor_shape = pointer
		if targeting_kind == &"half_card" and not targeting_half_eligible[half_index]:
			area.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN


func _gui_input(event: InputEvent) -> void:
	if _drag_hand != null and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var select_on_release := _left_click_pending and not event.is_pressed()
		_left_click_pending = event.is_pressed()
		accept_event()
		if select_on_release and Rect2(Vector2.ZERO, size).has_point(event.position):
			if interaction_disabled:
				_reject_pointer_action()
			else:
				primary_clicked.emit(StringName(card_id))
		return
	if face_down:
		return
	if event is InputEventMouseButton and event.pressed:
		if interaction_disabled and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_reject_pointer_action()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if targeting_kind == &"half_card":
				_reject_pointer_action()
				return
			primary_clicked.emit(StringName(card_id))
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			orientation_requested.emit(StringName(card_id))
			accept_event()


func _reject_pointer_action() -> void:
	if _hover_enabled:
		interaction_rejected.emit()
		accept_event()


func _on_mouse_entered() -> void:
	if not _hover_enabled or _hovered:
		return
	_hovered = true
	_aura.queue_redraw()
	card_hovered.emit()


func _on_mouse_exited() -> void:
	if _hovered:
		_hovered = false
		_aura.queue_redraw()


func _draw_aura() -> void:
	if _hovered:
		_aura.draw_style_box(HOVER_AURA, Rect2(Vector2.ZERO, size))
	if targeting_selected or (_select_in_place and _staged and not face_down and selected_frame_art == null):
		_aura.draw_style_box(PRIMED_AURA, Rect2(Vector2.ZERO, size))
	if targeting_kind == &"half_card":
		var half_height := size.y * 0.5
		for index in range(2):
			if targeting_half_selected[index]:
				var is_top := (index == 0) != orientation_flipped
				_aura.draw_style_box(PRIMED_AURA, Rect2(0, 0 if is_top else half_height, size.x, half_height))


func _get_drag_data(at_position: Vector2) -> Variant:
	if _drag_hand == null or not _left_click_pending:
		return null
	_left_click_pending = false
	var drag_preview := Control.new()
	var card_preview := duplicate(0) as Control
	drag_preview.add_child(card_preview)
	card_preview.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	card_preview.size = size
	card_preview.scale = get_global_transform().get_scale()
	card_preview.position = -at_position * card_preview.scale
	set_drag_preview(drag_preview)
	return {"hand": _drag_hand, "card_id": StringName(card_id)}


func first_face_text() -> String:
	return _first_debug_text


func second_face_text() -> String:
	return _second_debug_text


func joker_prompts_visible() -> bool:
	return _first_choices.visible or _second_choices.visible


func _half_text(half: Dictionary) -> String:
	if int(half.get("kind", 0)) == 1:
		return "JOKER  0  ANY"
	var context := int(half.get("effective_context", half.get("base_context", 0)))
	var rank := int(half.get("effective_rank", half.get("rank", half.get("base_rank", 0))))
	var suit := int(half.get("effective_suit", half.get("suit", half.get("base_suit", 0))))
	return "%s  %d  %s" % [GameTypes.context_name(context), rank, GameTypes.suit_name(suit)]


func _render_suit(icon: TextureRect, half: Dictionary, choices: Control, selector: OptionButton) -> void:
	var suit := selector.selected if choices.visible else int(half.get("effective_suit", half.get("suit", half.get("base_suit", -1))))
	icon.texture = suit_icons[suit] if suit >= 0 and suit < suit_icons.size() else null
	icon.tooltip_text = GameTypes.suit_name(suit) if icon.texture != null else ""
	var icon_width := 29.0 if _select_in_place else 18.0
	icon.custom_minimum_size = Vector2.ONE * icon_width if icon.texture != null else Vector2.ZERO


func _suit_names() -> Array[String]:
	return [
		GameTypes.suit_name(GameTypes.Suit.MOUNTAIN),
		GameTypes.suit_name(GameTypes.Suit.CLOUD),
		GameTypes.suit_name(GameTypes.Suit.SEA),
	]


func _half_rank(half: Dictionary) -> int:
	return 0 if int(half.get("kind", 0)) == 1 else int(half.get("effective_rank", half.get("rank", half.get("base_rank", 0))))


func _render_rank_art(container: HBoxContainer, rank: int) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	var digits := str(clampi(rank, 0, 10))
	container.tooltip_text = "Rank %d" % rank
	for digit in digits:
		var texture_rect := TextureRect.new()
		texture_rect.name = "Digit%s" % digit
		texture_rect.custom_minimum_size = Vector2(30, 42) if _select_in_place else Vector2(18, 24)
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_rect.material = RANK_INK
		texture_rect.texture = load("res://assets/artwork/card_number/png/card_number_%s.png" % digit)
		container.add_child(texture_rect)


func _half_matches_contexts(half: Dictionary, active_contexts: Array) -> bool:
	return (
		int(half.get("kind", 0)) == 1
		or int(half.get("effective_context", half.get("base_context", -1))) in active_contexts
	)


func _resolved_half(half: Dictionary) -> Dictionary:
	return {
		"effective_context": half.get("context", -1),
		"effective_rank": half.get("rank", 0),
		"effective_suit": half.get("suit", -1),
		"kind": 1 if bool(half.get("joker", false)) else 0,
	}


func _apply_context_art(first: Dictionary, second: Dictionary) -> void:
	var first_art := _half_context_art(first, _first_choices, _first_context)
	var second_art := _half_context_art(second, _second_choices, _second_context)
	_top_art.texture = second_art if orientation_flipped else first_art
	_bottom_art.texture = first_art if orientation_flipped else second_art


func _half_context_art(half: Dictionary, choices: Control, selector: OptionButton) -> Texture2D:
	var context := int(half.get("effective_context", half.get("base_context", -1)))
	if choices.visible:
		context = selector.selected
	var texture: Texture2D = CONTEXT_ART.get(context)
	return _artwork_region(texture) if texture != null else null


func _artwork_region(texture: Texture2D) -> AtlasTexture:
	# The layers share the same export canvas, with transparent padding around the card.
	var cropped := AtlasTexture.new()
	cropped.atlas = texture
	cropped.region = CARD_ART_REGION
	cropped.filter_clip = true
	return cropped


func _apply_active_style() -> void:
	var normal := Color("c4cfdb")
	var active := Color("ffd166")
	_first.modulate = active if active_half_index == 0 else normal
	_second.modulate = active if active_half_index == 1 else normal


func _apply_half_targeting_style() -> void:
	if targeting_kind != &"half_card":
		return
	for index in range(2):
		var icon := _first if index == 0 else _second
		if targeting_half_selected[index]:
			icon.modulate = Color("ffd45a")
		elif targeting_half_eligible[index]:
			icon.modulate = Color("77e8ff")
		else:
			icon.modulate = Color("46505d")


func _apply_joker_choices(first: Dictionary, second: Dictionary, view_state: Dictionary) -> void:
	if not bool(view_state.get("staged", false)):
		return
	var choices: Array = view_state.get("joker_choices", [])
	for raw_choice in choices:
		if not raw_choice is Dictionary:
			continue
		var half_index := int(raw_choice.get("half_index", -1))
		if half_index == 0 and int(first.get("kind", 0)) == 1:
			_first_choices.visible = true
			_first_context.select(int(raw_choice.get("context", 0)))
			_first_suit.select(int(raw_choice.get("suit", 0)))
		elif half_index == 1 and int(second.get("kind", 0)) == 1:
			_second_choices.visible = true
			_second_context.select(int(raw_choice.get("context", 0)))
			_second_suit.select(int(raw_choice.get("suit", 0)))


func _apply_orientation() -> void:
	_place_half(_first_rank_art, _first, _first_choices, $Face/FirstHit, not orientation_flipped)
	_place_half(_second_rank_art, _second, _second_choices, $Face/SecondHit, orientation_flipped)


func _place_half(rank_art: Control, suit: TextureRect, choices: Control, hit_area: Control, is_top: bool) -> void:
	var rank_size := rank_art.get_combined_minimum_size()
	var suit_size := suit.get_combined_minimum_size()
	var row_height := maxf(rank_size.y, suit_size.y)
	var inset := 12.0 if _select_in_place else 9.0
	var gap := 5.0
	var preset := Control.PRESET_TOP_LEFT if is_top else Control.PRESET_BOTTOM_RIGHT
	var row_y := inset if is_top else -inset - row_height
	var rank_x := inset if is_top else -inset - rank_size.x
	var suit_x := rank_x + rank_size.x + gap if is_top else rank_x - gap - suit_size.x
	_place_corner_mark(rank_art, preset, Rect2(rank_x, row_y, rank_size.x, row_height))
	_place_corner_mark(suit, preset, Rect2(suit_x, row_y, suit_size.x, row_height))
	var choice_edge := 0.23 if is_top else 0.76
	choices.anchor_top = choice_edge
	choices.anchor_bottom = choice_edge
	hit_area.anchor_top = 0.0 if is_top else 0.5
	hit_area.anchor_bottom = 0.5 if is_top else 1.0


func _place_corner_mark(mark: Control, preset: int, rect: Rect2) -> void:
	# Anchor the two marks together without rotating their artwork.
	mark.set_anchors_preset(preset, true)
	mark.offset_left = rect.position.x
	mark.offset_top = rect.position.y
	mark.offset_right = rect.end.x
	mark.offset_bottom = rect.end.y


func _populate_choices(button: OptionButton, values: Array) -> void:
	if button.item_count > 0:
		return
	for value in values:
		button.add_item(str(value))


func _on_first_context_selected(index: int) -> void:
	joker_choice_changed.emit(StringName(card_id), 0, index, _first_suit.selected)


func _on_first_suit_selected(index: int) -> void:
	joker_choice_changed.emit(StringName(card_id), 0, _first_context.selected, index)


func _on_second_context_selected(index: int) -> void:
	joker_choice_changed.emit(StringName(card_id), 1, index, _second_suit.selected)


func _on_second_suit_selected(index: int) -> void:
	joker_choice_changed.emit(StringName(card_id), 1, _second_context.selected, index)


func _on_move_left_pressed() -> void:
	if not interaction_disabled:
		reorder_requested.emit(StringName(card_id), -1)


func _on_move_right_pressed() -> void:
	if not interaction_disabled:
		reorder_requested.emit(StringName(card_id), 1)


func _on_first_gui_input(event: InputEvent) -> void:
	_handle_half_gui_input(event, 0)


func _on_second_gui_input(event: InputEvent) -> void:
	_handle_half_gui_input(event, 1)


func _handle_half_gui_input(event: InputEvent, half_index: int) -> void:
	if interaction_disabled or face_down or _drag_hand != null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if targeting_kind == &"half_card":
			if targeting_half_eligible[half_index]:
				half_target_requested.emit(StringName(card_id), half_index)
			else:
				_reject_pointer_action()
		elif targeting_kind in [&"full_card", &"card"]:
			primary_clicked.emit(StringName(card_id))
		elif _staged and not _select_in_place:
			half_choice_requested.emit(StringName(card_id), half_index)
		else:
			primary_clicked.emit(StringName(card_id))
		accept_event()
