class_name NormalHandEvaluator
extends RefCounted

const Rational = preload("res://src/core/common/rational.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")

const SUPPORTED_RULES := {
	&"high_card": true,
	&"pair": true,
	&"three_kind": true,
	&"straight": true,
	&"full_house": true,
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

	for definition in definitions:
		if not supports_rule(definition.rule_id) or definition.subset_size > faces.size():
			continue
		var subsets := _combinations(faces, definition.subset_size)
		for untyped_subset in subsets:
			var subset: Array[ScoringTypes.SelectedCardFace] = []
			subset.assign(untyped_subset)
			if not _matches(definition.rule_id, subset):
				continue
			var candidate_tie_break := _tie_break(definition.rule_id, subset)
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
	return ScoringTypes.NormalHandResult.new(
		true,
		best_definition.id,
		best_definition.priority,
		best_definition.multiplier,
		best_faces,
		faces,
		best_tie_break
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
	return String(definition.id) < String(best_definition.id)


static func _compare_tie_break(left: PackedInt32Array, right: PackedInt32Array) -> int:
	var shared_size: int = min(left.size(), right.size())
	for index in range(shared_size):
		if left[index] != right[index]:
			return 1 if left[index] > right[index] else -1
	if left.size() == right.size():
		return 0
	return 1 if left.size() > right.size() else -1


static func _matches(rule_id: StringName, faces: Array[ScoringTypes.SelectedCardFace]) -> bool:
	match rule_id:
		&"high_card":
			return faces.size() == 1
		&"pair":
			return faces.size() == 2 and faces[0].rank == faces[1].rank
		&"three_kind":
			return faces.size() == 3 and _rank_counts(faces).size() == 1
		&"straight":
			return _is_straight(faces)
		&"full_house":
			var counts: Array = _rank_counts(faces).values()
			counts.sort()
			return counts == [2, 3]
	return false


static func _tie_break(
	rule_id: StringName,
	faces: Array[ScoringTypes.SelectedCardFace]
) -> PackedInt32Array:
	var ranks: Array[int] = []
	for face in faces:
		ranks.append(face.rank)
	ranks.sort()
	match rule_id:
		&"full_house":
			var counts := _rank_counts(faces)
			var triple_rank := 0
			var pair_rank := 0
			for rank in counts:
				if counts[rank] == 3:
					triple_rank = rank
				elif counts[rank] == 2:
					pair_rank = rank
			return PackedInt32Array([triple_rank, pair_rank])
		&"high_card", &"pair", &"three_kind", &"straight":
			return PackedInt32Array([ranks[-1]])
	return PackedInt32Array()


static func _rank_counts(faces: Array[ScoringTypes.SelectedCardFace]) -> Dictionary:
	var counts := {}
	for face in faces:
		counts[face.rank] = counts.get(face.rank, 0) + 1
	return counts


static func _is_straight(faces: Array[ScoringTypes.SelectedCardFace]) -> bool:
	var ranks: Array[int] = []
	for face in faces:
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
		return String(left.card_id) < String(right.card_id)
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
