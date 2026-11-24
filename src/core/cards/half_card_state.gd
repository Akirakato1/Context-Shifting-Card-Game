class_name HalfCardState
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")

const NO_OVERRIDE := -1
const NO_SUIT := -1

var copy_id: StringName
var base_context: int
var base_rank: int
var base_suit: int
var kind: int
var joker_context := NO_OVERRIDE
var joker_suit := NO_SUIT
var joker_rank := 0
var joker_override := false

var _context_override := NO_OVERRIDE
var _rank_override := NO_OVERRIDE
var _suit_override := NO_OVERRIDE


func _init(
	id: StringName,
	origin_context: int,
	rank: int,
	suit: int,
	half_kind: int = GameTypes.HalfKind.NORMAL
) -> void:
	assert(is_valid_base(origin_context, rank, suit, half_kind), "invalid half-card base values")
	copy_id = id
	base_context = origin_context
	base_rank = rank
	base_suit = suit
	kind = half_kind


static func is_valid_base(
	context: int,
	rank: int,
	suit: int,
	half_kind: int = GameTypes.HalfKind.NORMAL
) -> bool:
	if context < GameTypes.Context.RISE or context > GameTypes.Context.FALL:
		return false
	match half_kind:
		GameTypes.HalfKind.NORMAL:
			return (
				rank >= 1 and rank <= 10
				and suit >= GameTypes.Suit.MOUNTAIN and suit <= GameTypes.Suit.SEA
			)
		GameTypes.HalfKind.JOKER:
			return rank == 0 and suit == NO_SUIT
	return false


func is_joker() -> bool:
	return kind == GameTypes.HalfKind.JOKER or joker_override


func effective_kind() -> int:
	return GameTypes.HalfKind.JOKER if is_joker() else kind


func make_joker() -> void:
	if not is_joker():
		reset_effective()
		joker_override = true


static func joker_choice_error(context: Variant, suit: Variant, rank: Variant = 0) -> StringName:
	if not context is int or context < GameTypes.Context.RISE or context > GameTypes.Context.FALL:
		return &"invalid_joker_context"
	if not suit is int or suit < GameTypes.Suit.MOUNTAIN or suit > GameTypes.Suit.SEA:
		return &"invalid_joker_suit"
	if not rank is int or rank < 0 or rank > 10:
		return &"invalid_joker_rank"
	return &""


func set_joker_choice(context: int, suit: int, rank: int = 0) -> void:
	assert(is_joker() and joker_choice_error(context, suit, rank).is_empty(), "invalid Joker choice")
	joker_context = context
	joker_suit = suit
	joker_rank = rank


func apply_overrides(context: int, rank: int, suit: int) -> void:
	assert(not is_joker(), "Jokers use their own face choices")
	assert(is_valid_base(context, rank, suit), "invalid half-card effective values")
	_context_override = context
	_rank_override = rank
	_suit_override = suit


func reset_effective() -> void:
	_context_override = NO_OVERRIDE
	_rank_override = NO_OVERRIDE
	_suit_override = NO_OVERRIDE
	joker_override = false
	joker_context = NO_OVERRIDE
	joker_suit = NO_SUIT
	joker_rank = 0


func effective_context() -> int:
	return base_context if _context_override == NO_OVERRIDE else _context_override


func effective_rank() -> int:
	if joker_override:
		return 0
	return base_rank if _rank_override == NO_OVERRIDE else _rank_override


func effective_suit() -> int:
	if joker_override:
		return NO_SUIT
	return base_suit if _suit_override == NO_OVERRIDE else _suit_override
