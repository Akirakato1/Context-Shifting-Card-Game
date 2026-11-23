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

enum VictoryMode {
	SCORE_RACE,
	ROUND_WIN_RACE,
}

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
