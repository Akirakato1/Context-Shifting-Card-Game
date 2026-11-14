class_name TestCase
extends RefCounted

var _failures: Array[String] = []


func reset_failures() -> void:
	_failures.clear()


func failures() -> Array[String]:
	return _failures.duplicate()


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		_record_failure(message, "expected %s, got %s" % [str(expected), str(actual)])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	if actual == unexpected:
		_record_failure(message, "did not expect %s" % str(unexpected))


func assert_true(value: bool, message: String = "") -> void:
	if not value:
		_record_failure(message, "expected true")


func assert_false(value: bool, message: String = "") -> void:
	if value:
		_record_failure(message, "expected false")


func _record_failure(message: String, fallback: String) -> void:
	_failures.append(message if not message.is_empty() else fallback)
