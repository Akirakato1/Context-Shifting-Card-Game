class_name Rational
extends RefCounted

var numerator: int
var denominator: int


func _init(value_numerator: int, value_denominator: int = 1) -> void:
	assert(value_denominator != 0, "rational denominator cannot be zero")
	var sign_value := -1 if value_denominator < 0 else 1
	var divisor := _greatest_common_divisor(abs(value_numerator), abs(value_denominator))
	numerator = sign_value * value_numerator / divisor
	denominator = abs(value_denominator) / divisor


func equals(other: Rational) -> bool:
	return numerator == other.numerator and denominator == other.denominator


static func _greatest_common_divisor(left: int, right: int) -> int:
	while right != 0:
		var remainder := left % right
		left = right
		right = remainder
	return max(left, 1)
