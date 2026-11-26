extends RefCounted

const Types := preload("res://src/core/common/game_types.gd")
const Kinds := preload("res://src/core/commands/command_kinds.gd")

const STEPS := [
	{
		"round": 1, "phase": Types.Phase.MAIN_1, "title": "Welcome to Zeitklus",
		"body": "Win three rounds against Mika. Each round goes through Start, Main 1, Hand Play, Main 2, and End. This match is untimed and opens in Main 1 because your first hand is already dealt.",
	},
	{
		"round": 1, "phase": Types.Phase.MAIN_1, "title": "Find your controls",
		"body": "Use Menu for settings or to leave, and ? to open Rules & Cards. The scroll at the lower-right of the large context clock opens History. It groups public plays, hand reveals, and round scores. Space readies up, A toggles Abilities, and H toggles History by default.",
	},
	{
		"round": 1, "phase": Types.Phase.MAIN_1, "title": "Read your abilities",
		"body": "The Abilities tray opens in Main 1 and highlights playable cards. The eye icons show descriptions, and you can drag to reorder cards. Right-click a playable ability to begin. Choose its targets if prompted. For a card without targets, left-click the highlighted card to play it.",
	},
	{
		"round": 1, "phase": Types.Phase.MAIN_1, "title": "Play a field ability",
		"body": "Prime Rise Ascendancy with right-click, then left-click it. The field adds +0.25 to the Field multiplier when Rise has the most halves, including ties. Click its entry on the table for details.",
		"command": Kinds.PLAY_PUBLIC_ABILITY, "ability": &"rise_ascendancy",
	},
	{
		"round": 1, "phase": Types.Phase.MAIN_1, "title": "Finish Main Phase 1",
		"body": "The clock points to Rise. The other contexts follow in the direction of its arrows. Press Ready or your Ready hotkey. The seat indicators show who is ready.",
		"command": Kinds.SET_READY,
	},
	{
		"round": 1, "phase": Types.Phase.HAND_PLAY, "title": "Turn and sort cards",
		"body": "Right-click to flip to an eligible half. Use a context sort to turn matching halves up, or Rank to sort by rank. Click a sort again to reverse its order. Drag cards to arrange the hand yourself.",
	},
	{
		"round": 1, "phase": Types.Phase.HAND_PLAY, "title": "Flip a card",
		"body": "Find the card with Rise 8 Cloud on its bottom half. Right-click that card to bring the 8 to the top.",
		"flip_card": 1,
	},
	{
		"round": 1, "phase": Types.Phase.HAND_PLAY, "title": "Submit a pair",
		"body": "Left-click the two Rise 8s, Mountain and Cloud. Click again to deselect. Hover the score factors to see which ranks, hands and effects contribute, then choose Submit Hand.",
		"command": Kinds.LOCK_HAND, "hand_size": 2, "opening_cards": [0, 1], "rank": 8,
	},
	{
		"round": 1, "phase": Types.Phase.MAIN_2, "title": "Read the reveal",
		"body": "Base sums the top ranks. The card hand uses top ranks and suits. Both halves count toward One Full Cycle. Rise Ascendancy raises the Field factor. Multiply the four factors for your score. Use the player buttons to see either revealed hand.",
	},
	{
		"round": 1, "phase": Types.Phase.MAIN_2, "title": "Close the first round",
		"body": "Main 2 is the last chance to play eligible abilities before scoring becomes final. Press Ready. A solo high score earns one round win. A tie awards no win. Your two remaining abilities carry over.",
		"command": Kinds.SET_READY,
	},
	{
		"round": 2, "phase": Types.Phase.START, "title": "Replenish your hand",
		"body": "The clock advanced to Flourish. Each used full card needs two new halves. Choose 4 on the Flourish pile and click Ready. The halves pair up into two cards. You also draw three abilities on later turns.",
		"command": Kinds.SET_READY, "draw": {Types.Context.FLOURISH: 4},
	},
	{
		"round": 2, "phase": Types.Phase.MAIN_1, "title": "Sabotage an opponent",
		"body": "Prime and play Momentary Lock, then click Mika's seat. It locks a random card so Mika can't submit it this round. Opponents see public ability plays. Private hand details stay hidden until revealed.",
		"command": Kinds.PLAY_PUBLIC_ABILITY, "ability": &"momentary_lock", "target": &"mika",
	},
	{
		"round": 2, "phase": Types.Phase.MAIN_1, "title": "Move to Hand Play",
		"body": "Press Ready. Manipulation cards are played during Hand Play, so you will use Mirror Rank after Main 1 ends.",
		"command": Kinds.SET_READY,
	},
	{
		"round": 2, "phase": Types.Phase.HAND_PLAY, "title": "Change a rank",
		"body": "Right-click Mirror Rank, then click the card with Flourish 8 Sea. Both ranks mirror around 11, turning the 8 into a 3. Escape cancels an unfinished target selection.",
		"command": Kinds.COMMIT_MANIPULATION, "ability": &"mirror_rank", "card": 2,
	},
	{
		"round": 2, "phase": Types.Phase.HAND_PLAY, "title": "Submit three of a kind",
		"body": "Select the three cards with Flourish 3s on top and Submit Hand. Matching ranks make a group. All six halves are Flourish, giving you Six Golden Age.",
		"command": Kinds.LOCK_HAND, "hand_size": 3, "opening_cards": [2], "rank": 3,
	},
	{
		"round": 2, "phase": Types.Phase.MAIN_2, "title": "Compare the factors",
		"body": "This hand has a lower Base than your pair and earns a different card hand and context hand. Compare the named patterns. The help tabs show the available shapes, priorities, and multipliers.",
	},
	{
		"round": 2, "phase": Types.Phase.MAIN_2, "title": "Go to End",
		"body": "Press Ready to finalize the score. You have three abilities left. In End, you’ll select two to keep.",
		"command": Kinds.SET_READY,
	},
	{
		"round": 2, "phase": Types.Phase.END, "title": "Select 2 cards to keep",
		"body": "The tray opens automatically. Select the two abilities you want to keep, then press Confirm Keep 2 to discard the third. Mika handles the same step independently.",
		"command": Kinds.CHOOSE_ABILITY_DISCARDS,
	},
	{
		"round": 3, "phase": Types.Phase.START, "title": "Draw from two piles",
		"body": "Fall is active. Choose 5 from Fall and 1 from Rise, then Ready. You can draw up to five halves from a pile. The one Rise half will pair with a Fall half so you can build a two-context hand.",
		"command": Kinds.SET_READY, "draw": {Types.Context.FALL: 5, Types.Context.RISE: 1},
	},
	{
		"round": 3, "phase": Types.Phase.MAIN_1, "title": "Plan a flush",
		"body": "You will submit four Mountain tops. Your next two abilities change a suit and a context. Some field cards can also reverse the clock or activate extra contexts. Press Ready to start building the flush.",
		"command": Kinds.SET_READY,
	},
	{
		"round": 3, "phase": Types.Phase.HAND_PLAY, "title": "Change a suit",
		"body": "The small suit clock at the upper-left of the large context clock shows Mountain → Cloud → Sea → Mountain. Ride the Suit Cycle follows that order. Suit Imprint lets you choose a suit directly. Right-click Suit Imprint, pick Fall 7 Cloud, then choose Mountain to build the flush.",
		"command": Kinds.COMMIT_MANIPULATION, "ability": &"suit_imprint", "card": 4, "suit": Types.Suit.MOUNTAIN,
	},
	{
		"round": 3, "phase": Types.Phase.HAND_PLAY, "title": "Change a context",
		"body": "Right-click Ride the Cycle. Select only the Flourish 9 Mountain card, then click Activate. Flourish 9 becomes Fall 9, and the other half becomes Rise. Flip Fall 9 to the top if needed.",
		"command": Kinds.COMMIT_MANIPULATION, "ability": &"ride_the_cycle", "card": 5,
	},
	{
		"round": 3, "phase": Types.Phase.HAND_PLAY, "title": "Submit a flush",
		"body": "Set the Joker on Fall 4 Mountain to Fall and Mountain. Fall is the active context this round. Select Fall 4, 7, and 9, plus the fresh Fall Mountain card with a Rise bottom. Submit those four Mountain tops. Five Fall and three Rise halves make Three Upheaval.",
		"command": Kinds.LOCK_HAND, "hand_size": 4, "opening_cards": [3, 4, 5],
		"suit": Types.Suit.MOUNTAIN, "bottom_context": Types.Context.RISE, "joker_context": Types.Context.FALL,
	},
	{
		"round": 3, "phase": Types.Phase.MAIN_2, "title": "Buff a revealed hand",
		"body": "Prime and play Flush Buff, then select your own side of the table. This adds +0.5 to your card-hand multiplier because you submitted a flush. A nerf targets a category in the same way but lowers its factor.",
		"command": Kinds.PLAY_PUBLIC_ABILITY, "ability": &"flush_buff", "target": &"host",
	},
	{
		"round": 3, "phase": Types.Phase.MAIN_2, "title": "Finish the tutorial",
		"body": "Open the History scroll or press H to find your buff under Round 3. Compare your updated score, then press Ready to finalize the round. Replay the tutorial from Results or try an untimed Practice match from the menu.",
		"command": Kinds.SET_READY,
	},
]
