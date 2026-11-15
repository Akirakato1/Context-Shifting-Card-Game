class_name RandomSource
extends RefCounted

var _rng: RandomNumberGenerator


func _init(seed_value: int) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value


func shuffle(values: Array) -> Array:
	var shuffled := values.duplicate()
	for index in range(shuffled.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temporary: Variant = shuffled[index]
		shuffled[index] = shuffled[swap_index]
		shuffled[swap_index] = temporary
	return shuffled


func pick_index(size: int) -> int:
	assert(size > 0, "cannot pick from an empty collection")
	return _rng.randi_range(0, size - 1)


func state_token() -> int:
	return _rng.state


func restore_state_token(token: int) -> void:
	_rng.state = token
