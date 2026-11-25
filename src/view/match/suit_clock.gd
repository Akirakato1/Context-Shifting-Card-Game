extends Control

const GameIcons := preload("res://src/view/common/game_icons.gd")
const GameTypes := preload("res://src/core/common/game_types.gd")


func _ready() -> void:
	$Mountain.texture = GameIcons.suit(GameTypes.Suit.MOUNTAIN)
	$Cloud.texture = GameIcons.suit(GameTypes.Suit.CLOUD)
	$Sea.texture = GameIcons.suit(GameTypes.Suit.SEA)
