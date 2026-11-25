class_name TargetingOverlay
extends Control

signal commit_requested(choices: Dictionary)
signal closed(reason: StringName)
signal selection_changed(kind: StringName, eligible: Array, selected: Array)

const GameTypes := preload("res://src/core/common/game_types.gd")
const GameIcons := preload("res://src/view/common/game_icons.gd")

var _steps: Array = []
var _choices: Dictionary = {}
var _current_step := 0
var _player_labels: Dictionary = {}
var _on_table := false

@onready var _panel: PanelContainer = $Panel
@onready var _dimmer: ColorRect = $Dimmer
@onready var _prompt: Label = $Panel/Layout/Prompt
@onready var _remaining: Label = $Panel/Layout/Remaining
@onready var _options: HBoxContainer = $Panel/Layout/Options
@onready var _commit: Button = $Panel/Layout/CommitButton


func begin(workflow: Dictionary, private_hand: Array = [], player_targets: Array = [], on_table := false) -> void:
	_on_table = on_table
	_dimmer.visible = not _on_table
	_player_labels.clear()
	_steps = _resolved_steps(workflow.get("steps", []), private_hand, player_targets)
	_choices.clear()
	_current_step = 0
	visible = not _steps.is_empty()
	if visible:
		_render_step()


func reopen() -> void:
	if _steps.is_empty():
		return
	_current_step = 0
	visible = true
	_render_step()


func select_value(value: Variant) -> void:
	if not visible or _current_step < 0 or _current_step >= _steps.size():
		return
	var step: Dictionary = _steps[_current_step]
	var eligible: Array = step.get("eligible", [])
	if value not in eligible:
		return
	var key := str(step.get("key", "step_%d" % _current_step))
	var selected: Array = _choices.get(key, []).duplicate(true)
	if _is_variable(step):
		if value in selected:
			selected.erase(value)
		elif selected.size() < int(step.get("max_count", 0)):
			selected.append(value)
	else:
		var required := int(step.get("count", 1))
		if required == 1:
			selected = [value]
		elif value not in selected and selected.size() < required:
			selected.append(value)
	_choices[key] = selected
	selection_changed.emit(
		StringName(step.get("kind", "value")), eligible.duplicate(true),
		selected.duplicate(true)
	)
	if not _is_variable(step) and selected.size() == int(step.get("count", 1)):
		if _current_step < _steps.size() - 1:
			_current_step += 1
			_render_step()
		else:
			_commit_choices()
	else:
		_update_completion()
		_update_remaining(step, selected.size())


func selected_values() -> Array:
	if _steps.is_empty() or _current_step >= _steps.size():
		return []
	var step: Dictionary = _steps[_current_step]
	return _choices.get(
		str(step.get("key", "step_%d" % _current_step)), []
	).duplicate(true)


func hand_choice_values() -> Array:
	var values: Array = []
	for index in _steps.size():
		var step: Dictionary = _steps[index]
		if str(step.get("kind", "")) in ["card", "full_card", "half_card"]:
			values.append_array(_choices.get(str(step.get("key", "step_%d" % index)), []))
	return values.duplicate(true)


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
	_update_remaining(step, selected.size())
	var kind := str(step.get("kind", "value"))
	var eligible: Array = step.get("eligible", [])
	var selects_on_table := _on_table and kind in ["player", "half_index"]
	# Leave the top portrait clear when the target is a player.
	_panel.anchor_top = 0.5
	if _on_table:
		_panel.anchor_top = 0.42 if kind == "player" else 0.14
	_panel.anchor_bottom = _panel.anchor_top
	_panel.offset_top = 5.0 if _on_table else -105.0
	_panel.offset_bottom = 113.0 if _on_table else 105.0
	if kind not in ["card", "full_card", "half_card"] and not selects_on_table:
		for value in eligible:
			var button := Button.new()
			if kind == "suit":
				button.icon = GameIcons.suit(int(value))
				button.tooltip_text = GameTypes.suit_name(int(value))
				button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				button.custom_minimum_size = Vector2(56, 44)
				button.add_theme_constant_override("icon_max_width", 30)
			else:
				button.text = str(_player_labels.get(str(value), str(value))).replace("_", " ").capitalize()
			button.pressed.connect(func(): select_value(value))
			_options.add_child(button)
	_options.visible = not _on_table or _options.get_child_count() > 0
	selection_changed.emit(
		StringName(kind), eligible.duplicate(true), selected.duplicate(true)
	)
	_update_completion()


func _update_remaining(step: Dictionary, selected_count: int) -> void:
	if _is_variable(step):
		_remaining.text = "%d selected  ·  choose %d–%d" % [
			selected_count, int(step.min_count), int(step.max_count),
		]
	else:
		_remaining.text = "%d remaining" % maxi(
			int(step.get("count", 1)) - selected_count, 0
		)


func _update_completion() -> void:
	var complete := not _steps.is_empty()
	var has_variable := false
	for index in _steps.size():
		var step: Dictionary = _steps[index]
		var key := str(step.get("key", "step_%d" % index))
		var selected_count: int = _choices.get(key, []).size()
		if _is_variable(step):
			has_variable = true
			if (
				selected_count < int(step.get("min_count", 0))
				or selected_count > int(step.get("max_count", 0))
			):
				complete = false
		elif selected_count != int(step.get("count", 1)):
			complete = false
	_commit.text = "ACTIVATE" if has_variable else "COMMIT"
	_commit.visible = not _on_table or has_variable
	_commit.disabled = not complete


func _on_commit_pressed() -> void:
	if not _commit.disabled:
		_commit_choices()


func _commit_choices() -> void:
	var result := _choices.duplicate(true)
	visible = false
	commit_requested.emit(result)
	closed.emit(&"committed")


func _on_cancel_pressed() -> void:
	cancel()


func _resolved_steps(raw_steps: Variant, private_hand: Array, player_targets: Array) -> Array:
	if not raw_steps is Array:
		return []
	var card_ids: Array = []
	var half_targets: Array = []
	var ordinary_half_targets: Array = []
	for card in private_hand:
		if not card is Dictionary:
			continue
		var card_id := str(card.get("card_id", ""))
		if card_id.is_empty():
			continue
		card_ids.append(card_id)
		for half_index in range(2):
			var half_target := {"card_id": card_id, "half_index": half_index}
			half_targets.append(half_target)
			var half: Dictionary = card.get("first" if half_index == 0 else "second", {})
			if int(half.get("kind", GameTypes.HalfKind.NORMAL)) != GameTypes.HalfKind.JOKER:
				ordinary_half_targets.append(half_target)
	var result: Array = []
	var player_ids: Array = []
	for target in player_targets:
		if not target is Dictionary: continue
		var player_id := str(target.get("player_id", ""))
		if player_id.is_empty(): continue
		player_ids.append(player_id)
		_player_labels[player_id] = str(target.get("display_name", player_id))
	for raw_step in raw_steps:
		if not raw_step is Dictionary:
			continue
		var step: Dictionary = raw_step.duplicate(true)
		var kind := str(step.get("kind", "value"))
		if kind == "full_card" or (kind == "card" and not step.has("eligible")):
			step["eligible"] = card_ids.duplicate()
		elif kind == "half_card":
			var candidates := ordinary_half_targets if bool(step.get("ordinary_only", false)) else half_targets
			step["eligible"] = candidates.duplicate(true)
		elif kind == "player":
			step["eligible"] = player_ids.duplicate()
		result.append(step)
	return result


func _is_variable(step: Dictionary) -> bool:
	return not step.has("count") and step.has("min_count") and step.has("max_count")
