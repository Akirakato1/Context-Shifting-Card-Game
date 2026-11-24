class_name NormalHandEvaluator
extends RefCounted

const Rational = preload("res://src/core/common/rational.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")

const SUPPORTED_RULES := {
	&"high_card": true,
	&"straight": true,
	&"grouped_ranks": true,
	&"flush": true,
}


static func supports_rule(rule_id: StringName) -> bool:
	return SUPPORTED_RULES.has(rule_id)


static func evaluate(
	faces: Array[ScoringTypes.SelectedCardFace],
	definitions: Array[NormalHandDefinition]
) -> ScoringTypes.NormalHandResult:
	var best_definition: NormalHandDefinition = null
	var best_faces: Array[ScoringTypes.SelectedCardFace] = []
	var best_tie_break := PackedInt32Array()
	var best_flush_definition: NormalHandDefinition = null
	var best_flush_tie_break := PackedInt32Array()

	for definition in definitions:
		if not supports_rule(definition.rule_id) or definition.subset_size > faces.size():
			continue
		if definition.component_group == &"suit":
			if definition.subset_size != faces.size() or not _matches(definition, faces):
				continue
			var flush_tie_break := _tie_break(definition, faces)
			if _candidate_precedes(definition, flush_tie_break, best_flush_definition, best_flush_tie_break):
				best_flush_definition = definition
				best_flush_tie_break = flush_tie_break
			continue
		var subsets := _combinations(faces, definition.subset_size)
		for untyped_subset in subsets:
			var subset: Array[ScoringTypes.SelectedCardFace] = []
			subset.assign(untyped_subset)
			if not _matches(definition, subset):
				continue
			var candidate_tie_break := _tie_break(definition, subset)
			if _candidate_precedes(
				definition, candidate_tie_break, best_definition, best_tie_break
			):
				best_definition = definition
				best_faces = _ordered_faces(subset)
				best_tie_break = candidate_tie_break

	if best_definition == null:
		return ScoringTypes.NormalHandResult.new(
			false, &"", -1, Rational.new(0, 1), [], faces, PackedInt32Array()
		)
	var components: Array[ScoringTypes.MultiplierComponent] = [
		ScoringTypes.MultiplierComponent.new(
			&"card_hand", best_definition.broad_category_id,
			best_definition.id, best_definition.multiplier
		),
	]
	if best_flush_definition != null:
		components.append(ScoringTypes.MultiplierComponent.new(
			&"card_hand", best_flush_definition.broad_category_id,
			best_flush_definition.id, best_flush_definition.multiplier
		))
	return ScoringTypes.NormalHandResult.new(
		true,
		best_definition.id,
		best_definition.priority,
		best_definition.multiplier,
		best_faces,
		faces,
		best_tie_break,
		components
	)


static func _candidate_precedes(
	definition: NormalHandDefinition,
	tie_break: PackedInt32Array,
	best_definition: NormalHandDefinition,
	best_tie_break: PackedInt32Array
) -> bool:
	if best_definition == null:
		return true
	if definition.priority != best_definition.priority:
		return definition.priority > best_definition.priority
	var tie_comparison := _compare_tie_break(tie_break, best_tie_break)
	if tie_comparison != 0:
		return tie_comparison > 0
	return str(definition.id) < str(best_definition.id)


static func _compare_tie_break(left: PackedInt32Array, right: PackedInt32Array) -> int:
	var shared_size: int = min(left.size(), right.size())
	for index in range(shared_size):
		if left[index] != right[index]:
			return 1 if left[index] > right[index] else -1
	if left.size() == right.size():
		return 0
	return 1 if left.size() > right.size() else -1


static func _matches(definition: NormalHandDefinition, faces: Array[ScoringTypes.SelectedCardFace]) -> bool:
	match definition.rule_id:
		&"high_card":
			return faces.size() == 1
		&"straight":
			return _is_straight(faces)
		&"grouped_ranks":
			var counts: Array = _rank_counts(faces, true).values()
			counts.sort_custom(func(left, right): return left > right)
			var required: Array = definition.rule_parameters.get("group_sizes", []).duplicate()
			required.sort_custom(func(left, right): return left > right)
			return counts == required
		&"flush":
			if faces.is_empty(): return false
			for face in faces:
				if face.suit != faces[0].suit: return false
			return true
	return false


static func _tie_break(
	definition: NormalHandDefinition,
	faces: Array[ScoringTypes.SelectedCardFace]
) -> PackedInt32Array:
	var ranks: Array[int] = []
	for face in faces:
		ranks.append(face.rank)
	ranks.sort()
	match definition.rule_id:
		&"grouped_ranks":
			var counts := _rank_counts(faces)
			var ordered_groups: Array = []
			for rank in counts:
				ordered_groups.append([counts[rank], rank])
			ordered_groups.sort_custom(func(left, right):
				return left[0] > right[0] or (left[0] == right[0] and left[1] > right[1])
			)
			var result := PackedInt32Array()
			for group in ordered_groups: result.append(group[1])
			return result
		&"flush":
			ranks.reverse()
			return PackedInt32Array(ranks)
		&"high_card", &"straight":
			return PackedInt32Array([ranks[-1]])
	return PackedInt32Array()


static func _rank_counts(
	faces: Array[ScoringTypes.SelectedCardFace], exclude_unranked: bool = false
) -> Dictionary:
	var counts := {}
	for face in faces:
		if exclude_unranked and face.rank == 0:
			continue
		counts[face.rank] = counts.get(face.rank, 0) + 1
	return counts


static func _is_straight(faces: Array[ScoringTypes.SelectedCardFace]) -> bool:
	var ranks: Array[int] = []
	for face in faces:
		if face.rank == 0:
			return false
		if face.rank in ranks:
			return false
		ranks.append(face.rank)
	ranks.sort()
	for index in range(1, ranks.size()):
		if ranks[index] != ranks[index - 1] + 1:
			return false
	return true


static func _ordered_faces(
	faces: Array[ScoringTypes.SelectedCardFace]
) -> Array[ScoringTypes.SelectedCardFace]:
	var ordered := faces.duplicate()
	ordered.sort_custom(_face_precedes)
	return ordered


static func _face_precedes(
	left: ScoringTypes.SelectedCardFace,
	right: ScoringTypes.SelectedCardFace
) -> bool:
	if left.rank != right.rank:
		return left.rank > right.rank
	if left.suit != right.suit:
		return left.suit > right.suit
	if left.card_id != right.card_id:
		return str(left.card_id) < str(right.card_id)
	return left.half_index < right.half_index


static func _combinations(values: Array, subset_size: int) -> Array:
	var result: Array = []
	_append_combinations(values, subset_size, 0, [], result)
	return result


static func _append_combinations(
	values: Array,
	subset_size: int,
	start_index: int,
	current: Array,
	result: Array
) -> void:
	if current.size() == subset_size:
		result.append(current.duplicate())
		return
	var remaining_needed := subset_size - current.size()
	var final_start := values.size() - remaining_needed
	for index in range(start_index, final_start + 1):
		current.append(values[index])
		_append_combinations(values, subset_size, index + 1, current, result)
		current.pop_back()
