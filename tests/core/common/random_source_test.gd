extends "res://tests/test_case.gd"

const RandomSource = preload("res://src/core/common/random_source.gd")


func test_shuffle_is_deterministic_for_equal_seeds() -> void:
	var fixture := [1, 2, 3, 4, 5, 6, 7, 8]
	var original := fixture.duplicate()
	var first := RandomSource.new(8675309)
	var second := RandomSource.new(8675309)
	var different := RandomSource.new(42)

	var first_result: Array = first.shuffle(fixture)
	var second_result: Array = second.shuffle(fixture)
	var different_result: Array = different.shuffle(fixture)

	assert_eq(first_result, second_result, "equal seeds should produce equal shuffles")
	assert_ne(first_result, different_result, "different seeds should produce a different shuffle")
	assert_eq(fixture, original, "shuffle should not mutate the caller's array")
