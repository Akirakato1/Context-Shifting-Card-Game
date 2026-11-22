extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const MatchConfig = preload("res://src/core/match/match_config.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")
const ContextHandDefinition = preload("res://src/core/scoring/context_hand_definition.gd")
const ContextHandCatalog = preload("res://src/core/scoring/context_hand_catalog.gd")


static func normal_definitions() -> Array[NormalHandDefinition]:
	return [
		NormalHandDefinition.new(&"high_card", 10, 1, &"high_card", Rational.new(1, 1)),
		NormalHandDefinition.new(&"pair", 20, 2, &"pair", Rational.new(1, 1)),
		NormalHandDefinition.new(&"three_kind", 30, 3, &"three_kind", Rational.new(1, 1)),
		NormalHandDefinition.new(&"straight_three", 40, 3, &"straight", Rational.new(1, 1)),
		NormalHandDefinition.new(&"straight_four", 41, 4, &"straight", Rational.new(1, 1)),
		NormalHandDefinition.new(&"straight_five", 42, 5, &"straight", Rational.new(1, 1)),
		NormalHandDefinition.new(&"straight_six", 43, 6, &"straight", Rational.new(1, 1)),
		NormalHandDefinition.new(&"full_house", 50, 5, &"full_house", Rational.new(1, 1)),
	]


static func context_definitions() -> Array[ContextHandDefinition]:
	return ContextHandCatalog.definitions()


static func default_catalog() -> Dictionary:
	var config := MatchConfig.new([], [], 0, 1, 0, {}, 1, 1, 1, [], normal_definitions(), context_definitions())
	return catalog_from_config(config.to_dict())


static func catalog_from_config(config: Dictionary) -> Dictionary:
	var normal: Array = []
	for definition: Dictionary in config.get("normal_definitions", []):
		var id := str(definition.id)
		var length := int(definition.subset_size)
		var label := id.capitalize()
		var description := ""
		match str(definition.rule_id):
			"high_card":
				description = "Use the highest-ranked selected face."
			"straight":
				label = "%d-card Straight" % length
				description = "Use %d faces with consecutive ranks." % length
			"grouped_ranks":
				if id == "three_kind":
					label = "Three of a Kind"
				var group_sizes: Array = definition.get("rule_parameters", {}).get("group_sizes", [])
				var groups := PackedStringArray()
				for size in group_sizes:
					groups.append("%d of a kind" % int(size))
				description = "Use %s." % " and ".join(groups)
			"flush":
				description = "All selected faces share a suit."
		normal.append(_entry(definition, label, description))
	var context: Array = []
	for definition: Dictionary in config.get("context_definitions", []):
		var minimums: Dictionary = definition.get("minimums", {})
		var names := PackedStringArray()
		var requirements := PackedStringArray()
		for key in minimums:
			var name := GameTypes.context_name(int(key))
			names.append(name)
			requirements.append("%d %s" % [int(minimums[key]), name])
		context.append(_entry(
			definition, "%s (%s)" % [" / ".join(names), " + ".join(requirements)],
			"Submit at least %s halves." % " and ".join(requirements)
		))
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
