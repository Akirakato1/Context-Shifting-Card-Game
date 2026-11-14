class_name GameTypes
extends RefCounted

enum Context {
	A,
	B,
	C,
}

enum Suit {
	ONE,
	TWO,
	THREE,
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
