extends "res://tests/test_case.gd"


func test_runtime_error_is_not_reported_as_a_pass() -> void:
	assert(false, "intentional harness fixture")
