extends SceneTree

const TEST_SUFFIX := "_test.gd"

var _failed_tests := 0
var _passed_tests := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var filters := OS.get_cmdline_user_args()
	var test_paths: Array[String] = []
	if filters.is_empty():
		test_paths = _discover_tests("res://tests")
	else:
		for filter_path in filters:
			var normalized := String(filter_path).replace("\\", "/").trim_prefix("./")
			test_paths.append(normalized if normalized.begins_with("res://") else "res://" + normalized)

	if test_paths.is_empty():
		print("FAIL: no tests matched")
		quit(1)
		return

	for test_path in test_paths:
		_run_test_script(test_path)

	print("RESULT: %d passed, %d failed" % [_passed_tests, _failed_tests])
	quit(0 if _failed_tests == 0 else 1)


func _discover_tests(directory_path: String) -> Array[String]:
	var discovered: Array[String] = []
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return discovered

	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path := directory_path.path_join(entry)
			if directory.current_is_dir():
				discovered.append_array(_discover_tests(child_path))
			elif entry.ends_with(TEST_SUFFIX):
				discovered.append(child_path)
		entry = directory.get_next()
	directory.list_dir_end()
	discovered.sort()
	return discovered


func _run_test_script(test_path: String) -> void:
	var test_script := load(test_path)
	if test_script == null or not test_script.can_instantiate():
		_failed_tests += 1
		print("FAIL %s: script could not be loaded" % test_path)
		return

	var suite: RefCounted = test_script.new()
	var methods := suite.get_method_list()
	for method_info in methods:
		var method_name := String(method_info["name"])
		if method_name.begins_with("test_"):
			_run_test_method(test_path, suite, method_name)


func _run_test_method(test_path: String, suite: RefCounted, method_name: String) -> void:
	if suite.has_method("reset_failures"):
		suite.call("reset_failures")
	if suite.has_method("before_each"):
		suite.call("before_each")

	suite.call(method_name)

	if suite.has_method("after_each"):
		suite.call("after_each")
	var failures: Array = suite.call("failures") if suite.has_method("failures") else []
	if failures.is_empty():
		_passed_tests += 1
		print("PASS %s::%s" % [test_path, method_name])
	else:
		_failed_tests += 1
		print("FAIL %s::%s" % [test_path, method_name])
		for failure in failures:
			print("  %s" % String(failure))
