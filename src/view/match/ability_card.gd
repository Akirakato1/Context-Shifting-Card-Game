extends PanelContainer

const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const GameTypes = preload("res://src/core/common/game_types.gd")
const CATEGORY_NAMES := ["Manipulation", "Field", "Buff / Nerf", "Sabotage"]
const CATEGORY_COLORS := [
	Color("78cfe1"), Color("9ed7a3"), Color("c7abf2"), Color("f29a91"),
]
const PHASE_NAMES := ["Hand Play", "Main 1", "Main 1 / Main 2", "Main 1"]
const DEFAULT_ACCENT := Color("adbdcf")
const CONTEXT_EMBLEMS := {
	GameTypes.Context.RISE: preload("res://assets/artwork/context_emblems/context_emblem_rish.png"),
	GameTypes.Context.FLOURISH: preload("res://assets/artwork/context_emblems/context_emblem_flourish.png"),
	GameTypes.Context.FALL: preload("res://assets/artwork/context_emblems/context_emblem_fall.png"),
}

@export var inventory_layout := false
@export_group("Background Artwork")
@export var manipulation_background: Texture2D
@export var field_background: Texture2D
@export var buff_nerf_background: Texture2D
@export var sabotage_background: Texture2D
@export_group("Category Frames")
@export var manipulation_frame: StyleBox
@export var field_frame: StyleBox
@export var buff_nerf_frame: StyleBox
@export var sabotage_frame: StyleBox

var _accent := DEFAULT_ACCENT
var _fallback_frame: StyleBoxFlat
var _custom_frame: StyleBox
var _border := DEFAULT_ACCENT
var _playable := false

@onready var _artwork: TextureRect = $Artwork
@onready var _art_space: Control = $Face/ArtSpace
@onready var _context_emblem: TextureRect = $Face/ArtSpace/ContextEmblem
@onready var _title: Label = $Face/Copy/Layout/Heading/Title
@onready var _count: Label = $Face/Copy/Layout/Heading/Count
@onready var _timing: Label = $Face/Copy/Layout/Timing
@onready var _rules: Label = $Face/Copy/Layout/Rules


func _ready() -> void:
	_artwork.draw.connect(_draw_placeholder)
	_artwork.resized.connect(_artwork.queue_redraw)
	_fallback_frame = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	add_theme_stylebox_override("panel", _fallback_frame)
	mouse_entered.connect(_update_border.bind(true))
	mouse_exited.connect(_update_border.bind(false))


func render(entry: Dictionary, ability_id: String, show_copies: bool, playable := false) -> void:
	var timing := int(entry.get("timing", -1))
	var valid_timing := timing >= 0 and timing < CATEGORY_NAMES.size()
	_playable = playable
	mouse_filter = Control.MOUSE_FILTER_PASS if playable else Control.MOUSE_FILTER_IGNORE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if playable else Control.CURSOR_ARROW
	_title.text = str(entry.get("display_name", entry.get("label", ability_id.capitalize())))
	_rules.text = str(entry.get("rules_text", ""))
	_timing.text = _timing_text(timing, entry) if valid_timing else "Unconfigured"
	_count.visible = show_copies
	var copies := int(entry.get("copies", 0))
	_count.text = "%d %s" % [copies, "copy" if copies == 1 else "copies"]
	_accent = DEFAULT_ACCENT
	_artwork.texture = null
	_custom_frame = null
	if valid_timing:
		_accent = CATEGORY_COLORS[timing]
		var backgrounds := [
			manipulation_background, field_background, buff_nerf_background, sabotage_background,
		]
		_artwork.texture = backgrounds[timing]
		var frames := [manipulation_frame, field_frame, buff_nerf_frame, sabotage_frame]
		_custom_frame = frames[timing]
	_border = _accent.darkened(0.15 if playable or show_copies else 0.44)
	add_theme_stylebox_override("panel", _custom_frame if _custom_frame != null else _fallback_frame)
	_timing.add_theme_color_override("font_color", _accent)
	_count.add_theme_color_override("font_color", _accent)
	if inventory_layout:
		_context_emblem.texture = CONTEXT_EMBLEMS.get(int(entry.get("context_emblem", -1)))
		_context_emblem.visible = _context_emblem.texture != null
		modulate = Color.WHITE if playable else Color("b7bdc8")
	_artwork.queue_redraw()
	_update_border(false)


func _timing_text(timing: int, entry: Dictionary) -> String:
	var timing_text := "%s · %s" % [CATEGORY_NAMES[timing], PHASE_NAMES[timing]]
	if timing == AbilityDefinition.Timing.FIELD and entry.has("field_duration"):
		var duration := int(entry["field_duration"])
		if duration == AbilityDefinition.FIELD_DURATION_PERSISTENT:
			timing_text += " · Persistent"
		elif duration == AbilityDefinition.FIELD_DURATION_INSTANT:
			timing_text += " · Instant"
		else:
			timing_text += " · %d %s" % [duration, "round" if duration == 1 else "rounds"]
	return timing_text


func _update_border(hovered: bool) -> void:
	if _custom_frame == null:
		_fallback_frame.border_color = _accent.lightened(0.28) if hovered and _playable else _border


func _draw_placeholder() -> void:
	if _artwork.texture != null:
		return
	var art_width := _art_space.custom_minimum_size.x
	var center := Vector2(art_width * 0.5, _artwork.size.y * 0.5)
	var ink := _accent.darkened(0.23)
	_artwork.draw_rect(Rect2(Vector2.ZERO, Vector2(art_width, _artwork.size.y)), _accent.darkened(0.84))
	if _context_emblem.visible:
		return
	var symbol_scale := minf(1.0, art_width / 60.0)
	_artwork.draw_arc(center, 27.0 * symbol_scale, 0.0, TAU, 40, Color(ink, 0.35), 1.0, true)
	_artwork.draw_polyline(PackedVector2Array([
		center + Vector2(0, -21) * symbol_scale, center + Vector2(17, 0) * symbol_scale,
		center + Vector2(0, 21) * symbol_scale, center + Vector2(-17, 0) * symbol_scale,
		center + Vector2(0, -21) * symbol_scale,
	]), ink, 1.5, true)
	_artwork.draw_circle(center, 3.0, _accent, true, -1.0, true)
