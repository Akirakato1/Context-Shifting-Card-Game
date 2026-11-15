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


func added(other: Rational) -> Rational:
	return _new_value(
		numerator * other.denominator + other.numerator * denominator,
		denominator * other.denominator
	)


func multiplied(other: Rational) -> Rational:
	return _new_value(numerator * other.numerator, denominator * other.denominator)


func compare_to(other: Rational) -> int:
	var left := numerator * other.denominator
	var right := other.numerator * denominator
	if left == right:
		return 0
	return 1 if left > right else -1


func clamped_to_zero() -> Rational:
	return _new_value(max(numerator, 0), denominator)


func ceiling() -> int:
	var quotient: int = numerator / denominator
	if numerator > 0 and numerator % denominator != 0:
		quotient += 1
	return quotient


func _new_value(value_numerator: int, value_denominator: int) -> Rational:
	var value: Rational = get_script().new(value_numerator, value_denominator)
	return value


static func _greatest_common_divisor(left: int, right: int) -> int:
	while right != 0:
		var remainder := left % right
		left = right
		right = remainder
	return max(left, 1)
