class_name TargetingOverlay
extends Control

signal commit_requested(choices: Dictionary)
signal closed(reason: StringName)
signal selection_changed(kind: StringName, eligible: Array, selected: Array)

var _steps: Array = []
var _choices: Dictionary = {}
var _current_step := 0

@onready var _prompt: Label = $Panel/Layout/Prompt
@onready var _remaining: Label = $Panel/Layout/Remaining
@onready var _options: HBoxContainer = $Panel/Layout/Options
@onready var _commit: Button = $Panel/Layout/CommitButton


func begin(workflow: Dictionary) -> void:
	_steps = workflow.get("steps", []).duplicate(true)
	_choices.clear()
	_current_step = 0
	visible = not _steps.is_empty()
	if visible:
		_render_step()


func select_value(value: Variant) -> void:
	if not visible or _current_step < 0 or _current_step >= _steps.size():
		return
	var step: Dictionary = _steps[_current_step]
	var eligible: Array = step.get("eligible", [])
	if value not in eligible:
		return
	var key := str(step.get("key", "step_%d" % _current_step))
	var selected: Array = _choices.get(key, [])
	var required := maxi(int(step.get("count", 1)), 1)
	if required == 1:
		selected = [value]
	elif value not in selected:
		selected.append(value)
	_choices[key] = selected
	selection_changed.emit(StringName(step.get("kind", "value")), eligible.duplicate(), selected.duplicate())
	if selected.size() >= required and _current_step < _steps.size() - 1:
		_current_step += 1
		_render_step()
	else:
		_update_completion()


func selected_values() -> Array:
	if _steps.is_empty() or _current_step >= _steps.size():
		return []
	var step: Dictionary = _steps[_current_step]
	return _choices.get(str(step.get("key", "step_%d" % _current_step)), []).duplicate()


func current_step_index() -> int:
	return _current_step


func cancel(reason: StringName = &"cancelled") -> void:
	if not visible:
		return
	visible = false
	closed.emit(reason)


func _render_step() -> void:
	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()
	var step: Dictionary = _steps[_current_step]
	_prompt.text = str(step.get("prompt", "Choose a target"))
	var key := str(step.get("key", "step_%d" % _current_step))
	var selected: Array = _choices.get(key, [])
	var required := maxi(int(step.get("count", 1)), 1)
	_remaining.text = "%d remaining" % maxi(required - selected.size(), 0)
	var kind := str(step.get("kind", "value"))
	var eligible: Array = step.get("eligible", [])
	if kind != "card":
		for value in eligible:
			var button := Button.new()
			button.text = str(value).replace("_", " ").capitalize()
			button.pressed.connect(func(): select_value(value))
			_options.add_child(button)
	selection_changed.emit(StringName(kind), eligible.duplicate(), selected.duplicate())
	_update_completion()


func _update_completion() -> void:
	var complete := not _steps.is_empty()
	for index in _steps.size():
		var step: Dictionary = _steps[index]
		var key := str(step.get("key", "step_%d" % index))
		if _choices.get(key, []).size() < maxi(int(step.get("count", 1)), 1):
			complete = false
			break
	_commit.disabled = not complete


func _on_commit_pressed() -> void:
	if _commit.disabled:
		return
	var result := _choices.duplicate(true)
	visible = false
	commit_requested.emit(result)
	closed.emit(&"committed")


func _on_cancel_pressed() -> void:
	cancel()
