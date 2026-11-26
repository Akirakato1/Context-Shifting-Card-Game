extends RefCounted

const Types := preload("res://src/core/common/game_types.gd")
const FRONT := {
	"avatar_1": preload("res://assets/artwork/avatar/avatar_1_front.png"),
	"avatar_2": preload("res://assets/artwork/avatar/avatar_2_front.png"),
	"avatar_3": preload("res://assets/artwork/avatar/avatar_front_3.png"),
	"avatar_4": preload("res://assets/artwork/avatar/avatar_4_front.png"),
	"avatar_5": preload("res://assets/artwork/avatar/avatar_5_front.png"),
	"avatar_6": preload("res://assets/artwork/avatar/avatar_6_front.png"),
	"avatar_8": preload("res://assets/artwork/avatar/mascot.tres"),
	"avatar_9": preload("res://assets/artwork/avatar/avatar_9_front.png"),
	"avatar_10": preload("res://assets/artwork/avatar/avatar_10_front.png"),
	"avatar_11": preload("res://assets/artwork/avatar/avatar_11_front.png"),
}
const SIDE := {
	"avatar_1": preload("res://assets/artwork/avatar/avatar_1_side.png"),
	"avatar_2": preload("res://assets/artwork/avatar/avatar_2_side.png"),
}
const NAMES := {
	"avatar_1": "Max Stirner",
	"avatar_2": "Bernhard Riemann",
	"avatar_3": "John Smith",
	"avatar_4": "Claude-Louis Navier",
	"avatar_5": "Traveler",
	"avatar_6": "Dog",
	"avatar_8": "Aldoro Einstein",
	"avatar_9": "Max Planck",
	"avatar_10": "Chocolate Fish",
	"avatar_11": "Taiyaki",
}


static func display_name(id: String) -> String:
	return NAMES.get(Types.canonical_avatar_id(id), "Avatar")


static func front_texture(id: String) -> Texture2D:
	return FRONT.get(Types.canonical_avatar_id(id), FRONT[default_avatar_id(0)])


static func seat_texture(id: String, seat_position: StringName) -> Texture2D:
	if seat_position in [&"left", &"right"] and has_side(id):
		return SIDE[id]
	return front_texture(id)


static func has_side(id: String) -> bool:
	return SIDE.has(id)


static func default_avatar_id(seat_index: int) -> String:
	return Types.default_avatar_id(seat_index)
