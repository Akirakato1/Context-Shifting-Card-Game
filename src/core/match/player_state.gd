class_name PlayerState
extends RefCounted

const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const AbilityState = preload("res://src/core/abilities/ability_state.gd")

var player_id: StringName
var seat_index: int
var spectator: bool
var active: bool
var pending := false
var connected := true
var ready := false
var hand: Array[FullCardState] = []
var ability_hand: Array[AbilityState] = []
var match_score := 0
var round_wins := 0
var replenishment_needed := 0


func _init(id: StringName, seat: int, is_spectator: bool = false) -> void:
	player_id = id
	seat_index = seat
	spectator = is_spectator
	active = not is_spectator
