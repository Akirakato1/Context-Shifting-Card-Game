class_name PlayerState
extends RefCounted

const FullCardState = preload("res://src/core/cards/full_card_state.gd")
const AbilityState = preload("res://src/core/abilities/ability_state.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")

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
var score_modifiers: Array[ScoringTypes.ScoreModifier] = []
var pending_manipulation: Dictionary = {}
var staged_submission: Array[Dictionary] = []
var has_staged_submission := false
var hand_locked := false
var submitted_cards: Array[FullCardState] = []
var submitted_faces: Array[ScoringTypes.SelectedCardFace] = []
var locked_normal: Variant = null
var locked_context: Variant = null
var provisional_score: Variant = null
var completed_manipulation_ids: Array[StringName] = []


func _init(id: StringName, seat: int, is_spectator: bool = false) -> void:
	player_id = id
	seat_index = seat
	spectator = is_spectator
	active = not is_spectator
