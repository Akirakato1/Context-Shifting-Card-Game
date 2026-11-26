class_name GameTypes
extends RefCounted

enum Context {
	RISE = 0,
	FLOURISH = 1,
	FALL = 2,
}


static func context_name(context: int) -> String:
	match context:
		Context.RISE:
			return "Rise"
		Context.FLOURISH:
			return "Flourish"
		Context.FALL:
			return "Fall"
		_:
			return "Unknown"

enum Suit {
	MOUNTAIN = 0,
	CLOUD = 1,
	SEA = 2,
}


static func suit_name(suit: int) -> String:
	match suit:
		Suit.MOUNTAIN:
			return "Mountain"
		Suit.CLOUD:
			return "Cloud"
		Suit.SEA:
			return "Sea"
		_:
			return "Unknown"

enum HalfKind {
	NORMAL,
	JOKER,
}

enum Phase {
	SETUP,
	START,
	MAIN_1,
	HAND_PLAY,
	MAIN_2,
	END,
	COMPLETE,
}

const MAIN_2_REVIEW_MSEC_PER_PLAYER := 3000
const AVATAR_IDS := [
	"avatar_1", "avatar_2", "avatar_3", "avatar_4", "avatar_5", "avatar_6",
	"avatar_8", "avatar_9", "avatar_10", "avatar_11",
]


static func canonical_avatar_id(avatar_id: String) -> String:
	match avatar_id:
		"avatar_7":
			return default_avatar_id(0)
		"avatar_8_2":
			return "avatar_8"
		_:
			return avatar_id


static func default_avatar_id(seat_index: int) -> String:
	return AVATAR_IDS[maxi(seat_index, 0) % AVATAR_IDS.size()]

enum VictoryMode {
	SCORE_RACE,
	ROUND_WIN_RACE,
}

static func default_victory_target(mode: int) -> int:
	return 10 if mode == VictoryMode.ROUND_WIN_RACE else 1_000


enum InformationVisibility {
	PUBLIC,
	PRIVATE,
}

enum ContextDirection {
	FORWARD = 1,
	REVERSE = -1,
}

enum RecipientRole {
	HOST,
	ACTIVE_PLAYER,
	PENDING_PLAYER,
	SPECTATOR,
}
