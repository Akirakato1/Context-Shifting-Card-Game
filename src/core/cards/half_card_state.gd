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
				and suit >= GameTypes.Suit.ONE and suit <= GameTypes.Suit.THREE
			)
		GameTypes.HalfKind.JOKER:
			return rank == 0 and suit == NO_SUIT
	return false


func is_joker() -> bool:
	return kind == GameTypes.HalfKind.JOKER


func apply_overrides(context: int, rank: int, suit: int) -> void:
	assert(not is_joker(), "joker choices are submission-local")
	assert(is_valid_base(context, rank, suit), "invalid half-card effective values")
	_context_override = context
	_rank_override = rank
	_suit_override = suit


func reset_effective() -> void:
	_context_override = NO_OVERRIDE
	_rank_override = NO_OVERRIDE
	_suit_override = NO_OVERRIDE


func effective_context() -> int:
	return base_context if _context_override == NO_OVERRIDE else _context_override


func effective_rank() -> int:
	return base_rank if _rank_override == NO_OVERRIDE else _rank_override


func effective_suit() -> int:
	return base_suit if _suit_override == NO_OVERRIDE else _suit_override
