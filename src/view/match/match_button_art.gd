extends RefCounted

const PILL := preload("res://assets/artwork/button/button_1.png")
const BAR := preload("res://assets/artwork/button/button_2.png")
const ROUND := preload("res://assets/artwork/button/button_3.png")
const ACTION := preload("res://assets/artwork/button/button_4.png")
const MENU := preload("res://assets/artwork/button/button_5.png")

const STATE_TINTS := {
	"normal": Color.WHITE,
	"hover": Color(1.20, 1.20, 1.20),
	"pressed": Color(1.36, 1.21, 0.94),
	"hover_pressed": Color(1.47, 1.34, 1.08),
	"disabled": Color(0.67, 0.67, 0.67, 0.76),
}


static func surface(texture: Texture2D, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.modulate_color = tint
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


static func skin(button: Button, texture: Texture2D) -> void:
	button.flat = false
	if button.mouse_default_cursor_shape == Control.CURSOR_ARROW:
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in STATE_TINTS:
		button.add_theme_stylebox_override(state, surface(texture, STATE_TINTS[state]))
