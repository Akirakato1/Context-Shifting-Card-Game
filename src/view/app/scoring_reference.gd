extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")
const NormalHandCatalog = preload("res://src/core/scoring/normal_hand_catalog.gd")
const ContextHandDefinition = preload("res://src/core/scoring/context_hand_definition.gd")
const ContextHandCatalog = preload("res://src/core/scoring/context_hand_catalog.gd")
const NORMAL_HAND_NAMES := {
	"two_pair": "Two-Pair", "three_pair": "Three-Pair",
	"three_kind": "Three of a Kind", "four_kind": "Four of a Kind",
	"five_kind": "Five of a Kind", "six_kind": "Six of a Kind",
}
const RISE_BIT := 1 << GameTypes.Context.RISE
const FLOURISH_BIT := 1 << GameTypes.Context.FLOURISH
const FALL_BIT := 1 << GameTypes.Context.FALL
const CONTEXT_PATTERN_NAMES := {
	RISE_BIT: "Ascent",
	FLOURISH_BIT: "Golden Age",
	FALL_BIT: "Descent",
	RISE_BIT | FLOURISH_BIT: "Renaissance",
	RISE_BIT | FALL_BIT: "Upheaval",
	FLOURISH_BIT | FALL_BIT: "Afterglow",
	RISE_BIT | FLOURISH_BIT | FALL_BIT: "Full Cycle",
}
const TIER_NAMES := [
	"", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve",
]


static func normal_definitions() -> Array[NormalHandDefinition]:
	return NormalHandCatalog.definitions()


static func context_definitions() -> Array[ContextHandDefinition]:
	return ContextHandCatalog.definitions()


static func default_catalog() -> Dictionary:
	var config := MatchConfig.new([], [], 0, 1, 0, {}, 1, 1, 1, [], normal_definitions(), context_definitions())
	return catalog_from_config(config.to_dict())


static func normal_display_name(id: String, rule := "", length := 0) -> String:
	if rule.is_empty():
		var parts := id.split("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			rule = parts[0]
			length = int(parts[1])
	if rule in ["straight", "flush"]:
		return "%s-card %s" % [_number_word(length), rule.capitalize()]
	return NORMAL_HAND_NAMES.get(id, id.capitalize())


static func _number_word(value: int) -> String:
	return TIER_NAMES[value] if value > 0 and value < TIER_NAMES.size() else str(value)


static func catalog_from_config(config: Dictionary) -> Dictionary:
	var normal: Array = []
	for definition: Dictionary in config.get("normal_definitions", []):
		var id := str(definition.id)
		var length := int(definition.subset_size)
		var rule := str(definition.rule_id)
		var label := normal_display_name(id, rule, length)
		var description := ""
		match rule:
			"high_card":
				description = "Use the highest-ranked selected face."
			"straight":
				description = "Use %s faces with consecutive ranks." % _number_word(length).to_lower()
			"grouped_ranks":
				var group_sizes: Array = definition.get("rule_parameters", {}).get("group_sizes", [])
				var groups := PackedStringArray()
				for size in group_sizes:
					groups.append("%s of a kind" % _number_word(int(size)).to_lower())
				description = "Use %s." % " and ".join(groups)
			"flush":
				description = "All selected faces share a suit."
		normal.append(_entry(definition, label, description))
	var context: Array = []
	for definition: Dictionary in config.get("context_definitions", []):
		var minimums: Dictionary = definition.get("minimums", {})
		var requirements := PackedStringArray()
		var mask := 0
		var tier := 0
		var shared_tier := true
		for context_id in [GameTypes.Context.RISE, GameTypes.Context.FLOURISH, GameTypes.Context.FALL]:
			var count := int(minimums.get(str(context_id), minimums.get(context_id, 0)))
			if count <= 0:
				continue
			requirements.append("%d %s" % [count, GameTypes.context_name(context_id)])
			mask |= 1 << context_id
			if tier == 0:
				tier = count
			shared_tier = shared_tier and tier == count
		var requirements_text := " / ".join(requirements)
		var label := requirements_text if mask != 0 else str(definition.id).capitalize()
		if shared_tier and tier > 0 and tier < TIER_NAMES.size() and CONTEXT_PATTERN_NAMES.has(mask):
			label = "%s %s" % [TIER_NAMES[tier], CONTEXT_PATTERN_NAMES[mask]]
		var entry := _entry(
			definition, label,
			"Submit at least %s halves." % " and ".join(requirements)
		)
		if label != requirements_text:
			entry["requirements_text"] = requirements_text
		context.append(entry)
	for group in [normal, context]:
		group.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			if left.priority == right.priority:
				return left.id < right.id
			return left.priority > right.priority
		)
	return {"normal": normal, "context": context}


static func _entry(definition: Dictionary, label: String, description: String) -> Dictionary:
	var entry := definition.duplicate(true)
	entry["display_name"] = label
	entry["rules_text"] = description
	entry["multiplier"] = {
		"numerator": entry.get("multiplier_numerator", 1),
		"denominator": entry.get("multiplier_denominator", 1),
	}
	return entry
