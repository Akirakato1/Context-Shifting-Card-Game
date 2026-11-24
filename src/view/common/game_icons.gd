extends RefCounted

const CONTEXT_ART := [
	preload("res://assets/artwork/context_emblems/context_emblem_rish.png"),
	preload("res://assets/artwork/context_emblems/context_emblem_flourish.png"),
	preload("res://assets/artwork/context_emblems/context_emblem_fall.png"),
]
const SUIT_ART := [
	preload("res://assets/artwork/card_suit_mountain.png"),
	preload("res://assets/artwork/card_suit_cloud.png"),
	preload("res://assets/artwork/card_suit_sea.png"),
]
const SUIT_CROPS := [
	Rect2i(132, 219, 1737, 1365),
	Rect2i(106, 262, 1885, 1141),
	Rect2i(241, 295, 1707, 1429),
]
const CONTEXT_NAMES := ["Rise", "Flourish", "Fall"]
const SUIT_NAMES := ["Mountain", "Cloud", "Sea"]
static var _mentions := RegEx.create_from_string("\\b(Rise|Flourish|Fall|Mountain|Cloud|Sea)\\b")
static var _suit_icons: Dictionary[int, Texture2D] = {}
static var _context_icons: Dictionary[int, Texture2D] = {}


static func context(index: int) -> Texture2D:
	if index < 0 or index >= CONTEXT_ART.size():
		return null
	if not _context_icons.has(index):
		var icon := AtlasTexture.new()
		icon.atlas = CONTEXT_ART[index]
		icon.region = Rect2(75, 68, 853, 852)
		icon.filter_clip = true
		_context_icons[index] = icon
	return _context_icons[index]


static func suit(index: int) -> Texture2D:
	if index < 0 or index >= SUIT_ART.size():
		return null
	if not _suit_icons.has(index):
		var ink: Image = SUIT_ART[index].get_image().get_region(SUIT_CROPS[index])
		var height := roundi(96.0 * ink.get_height() / ink.get_width())
		ink.resize(96, height, Image.INTERPOLATE_LANCZOS)
		ink.convert(Image.FORMAT_RGBA8)
		for y in height:
			for x in 96:
				ink.set_pixel(x, y, Color(0.95, 0.97, 1.0, ink.get_pixel(x, y).a))
		_suit_icons[index] = ImageTexture.create_from_image(ink)
	return _suit_icons[index]


static func has_mentions(words: String) -> bool:
	return _mentions.search(words) != null


static func label(font: Font, font_size: int, ink: Color, wrap := true) -> RichTextLabel:
	var message := RichTextLabel.new()
	message.add_theme_font_override("normal_font", font)
	message.add_theme_font_size_override("normal_font_size", font_size)
	message.add_theme_color_override("default_color", ink)
	message.fit_content = true
	message.scroll_active = false
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	message.mouse_filter = Control.MOUSE_FILTER_PASS
	return message


static func write(label: RichTextLabel, words: String, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	label.clear()
	label.push_paragraph(alignment)
	var height := label.get_theme_font_size("normal_font_size")
	var offset := 0
	for mention in _mentions.search_all(words):
		var name := mention.get_string()
		var icon := context(CONTEXT_NAMES.find(name)) if name in CONTEXT_NAMES else suit(SUIT_NAMES.find(name))
		label.add_text(words.substr(offset, mention.get_start() - offset))
		var width := roundi(height * icon.get_width() / icon.get_height())
		label.add_image(icon, width, height)
		offset = mention.get_end()
	label.add_text(words.substr(offset))
	label.pop()
	label.tooltip_text = words if offset > 0 else ""
