class_name ScoringCategories
extends RefCounted

const CARD_HAND := &"card_hand"
const CONTEXT_HAND := &"context_hand"
const FIELD := &"field"

const HIGH_CARD := &"high_card"
const STRAIGHT := &"straight"
const FAMILY := &"family"
const GROUP := &"group"
const FLUSH := &"flush"
const SINGLE_CONTEXT := &"single_context"
const TWO_CONTEXT := &"two_context"
const THREE_CONTEXT := &"three_context"

const RANK_GROUP := &"rank"
const SUIT_GROUP := &"suit"

const _CATEGORIES := {
	CARD_HAND: [HIGH_CARD, STRAIGHT, FAMILY, GROUP, FLUSH],
	CONTEXT_HAND: [SINGLE_CONTEXT, TWO_CONTEXT, THREE_CONTEXT],
	FIELD: [FIELD],
}


static func category_allowed(factor_id: StringName, category_id: StringName) -> bool:
	return _CATEGORIES.has(factor_id) and category_id in _CATEGORIES[factor_id]


static func component_group_allowed(group_id: StringName) -> bool:
	return group_id == RANK_GROUP or group_id == SUIT_GROUP
