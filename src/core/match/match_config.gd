class_name MatchConfig
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const Rational = preload("res://src/core/common/rational.gd")
const NormalHandDefinition = preload("res://src/core/scoring/normal_hand_definition.gd")
const ContextHandDefinition = preload("res://src/core/scoring/context_hand_definition.gd")

var match_started := false

var _active_player_ids: Array[StringName] = []
var _spectator_ids: Array[StringName] = []
var _victory_mode: int
var _victory_target: int
var _information_visibility: int
var _phase_timers: Dictionary
var _reaction_window_msec: int
var _public_hard_limit_msec: int
var _reconnect_grace_msec: int
var _ability_definitions: Array[AbilityDefinition] = []
var _normal_definitions: Array[NormalHandDefinition] = []
var _context_definitions: Array[ContextHandDefinition] = []

var active_player_ids: Array[StringName]:
	get: return _active_player_ids.duplicate()
var spectator_ids: Array[StringName]:
	get: return _spectator_ids.duplicate()
var victory_mode: int:
	get: return _victory_mode
var victory_target: int:
	get: return _victory_target
var information_visibility: int:
	get: return _information_visibility
var phase_timers: Dictionary:
	get: return _phase_timers.duplicate()
var reaction_window_msec: int:
	get: return _reaction_window_msec
var public_hard_limit_msec: int:
	get: return _public_hard_limit_msec
var reconnect_grace_msec: int:
	get: return _reconnect_grace_msec
var ability_definitions: Array[AbilityDefinition]:
	get: return _ability_definitions.duplicate()
var normal_definitions: Array[NormalHandDefinition]:
	get: return _normal_definitions.duplicate()
var context_definitions: Array[ContextHandDefinition]:
	get: return _context_definitions.duplicate()


func _init(
	initial_active_ids: Array,
	initial_spectator_ids: Array,
	initial_victory_mode: int,
	initial_victory_target: int,
	initial_visibility: int,
	initial_phase_timers: Dictionary,
	initial_reaction_window_msec: int,
	initial_public_hard_limit_msec: int,
	initial_reconnect_grace_msec: int,
	initial_ability_definitions: Array,
	initial_normal_definitions: Array = [],
	initial_context_definitions: Array = []
) -> void:
	_active_player_ids.assign(initial_active_ids)
	_spectator_ids.assign(initial_spectator_ids)
	_victory_mode = initial_victory_mode
	_victory_target = initial_victory_target
	_information_visibility = initial_visibility
	_phase_timers = initial_phase_timers.duplicate()
	_reaction_window_msec = initial_reaction_window_msec
	_public_hard_limit_msec = initial_public_hard_limit_msec
	_reconnect_grace_msec = initial_reconnect_grace_msec
	_ability_definitions.assign(initial_ability_definitions)
	_normal_definitions.assign(initial_normal_definitions)
	_context_definitions.assign(initial_context_definitions)


func validate() -> StringName:
	if _active_player_ids.size() < 2 or _active_player_ids.size() > 4:
		return &"active_player_count_out_of_range"
	if _spectator_ids.size() > 4:
		return &"spectator_count_out_of_range"
	var participant_ids := {}
	for player_id in _active_player_ids + _spectator_ids:
		if participant_ids.has(player_id):
			return &"duplicate_participant_id"
		participant_ids[player_id] = true
	if _victory_target <= 0:
		return &"invalid_victory_target"
	if _victory_mode < GameTypes.VictoryMode.SCORE_RACE or _victory_mode > GameTypes.VictoryMode.ROUND_WIN_RACE:
		return &"invalid_victory_mode"
	if _information_visibility < GameTypes.InformationVisibility.PUBLIC or _information_visibility > GameTypes.InformationVisibility.PRIVATE:
		return &"invalid_information_visibility"
	var required_phases := [
		GameTypes.Phase.START, GameTypes.Phase.MAIN_1, GameTypes.Phase.HAND_PLAY,
		GameTypes.Phase.MAIN_2, GameTypes.Phase.END,
	]
	for phase in _phase_timers:
		if not phase is int or phase not in required_phases:
			return &"unknown_phase_timer"
	for phase in required_phases:
		if not _phase_timers.has(phase):
			return &"missing_phase_timer"
	for duration in _phase_timers.values():
		if not duration is int or duration <= 0:
			return &"invalid_phase_timer"
	if _reaction_window_msec <= 0:
		return &"invalid_reaction_window"
	if _public_hard_limit_msec <= 0:
		return &"invalid_public_hard_limit"
	if _reconnect_grace_msec <= 0:
		return &"invalid_reconnect_grace"
	if _ability_definitions.size() < _active_player_ids.size() * 3:
		return &"insufficient_ability_cards"
	return &""


func lock_for_match() -> void:
	match_started = true


func register_active_participant(player_id: StringName) -> void:
	if player_id not in _active_player_ids:
		_active_player_ids.append(player_id)


func unregister_active_participant(player_id: StringName) -> void:
	_active_player_ids.erase(player_id)


func register_spectator(player_id: StringName) -> void:
	if player_id not in _spectator_ids:
		_spectator_ids.append(player_id)


func set_victory_target(value: int) -> StringName:
	if match_started: return &"config_locked"
	_victory_target = value
	return &""


func set_victory_mode(value: int) -> StringName:
	if match_started: return &"config_locked"
	_victory_mode = value
	return &""


func set_information_visibility(value: int) -> StringName:
	if match_started: return &"config_locked"
	_information_visibility = value
	return &""


func set_phase_timer(phase: int, value: int) -> StringName:
	if match_started: return &"config_locked"
	_phase_timers[phase] = value
	return &""


func set_reaction_window_msec(value: int) -> StringName:
	if match_started: return &"config_locked"
	_reaction_window_msec = value
	return &""


func set_public_hard_limit_msec(value: int) -> StringName:
	if match_started: return &"config_locked"
	_public_hard_limit_msec = value
	return &""


func set_reconnect_grace_msec(value: int) -> StringName:
	if match_started: return &"config_locked"
	_reconnect_grace_msec = value
	return &""


func to_dict() -> Dictionary:
	var active: Array = []
	for id in _active_player_ids: active.append(str(id))
	var spectators: Array = []
	for id in _spectator_ids: spectators.append(str(id))
	var timers := {}
	for phase in _phase_timers: timers[str(phase)] = _phase_timers[phase]
	var definitions: Array = []
	for definition in _ability_definitions:
		var tags: Array = []
		for tag in definition.tags: tags.append(str(tag))
		definitions.append({
			"id": str(definition.id), "timing": definition.timing, "tags": tags,
			"effect_id": str(definition.effect_id), "field_duration": definition.field_duration,
			"conflict_group": str(definition.conflict_group),
			"effect_parameters": definition.effect_parameters,
			"choice_schema": definition.choice_schema,
		})
	var normal_definitions: Array = []
	for definition in _normal_definitions:
		normal_definitions.append({
			"id": str(definition.id), "priority": definition.priority,
			"subset_size": definition.subset_size, "rule_id": str(definition.rule_id),
			"multiplier_numerator": definition.multiplier.numerator,
			"multiplier_denominator": definition.multiplier.denominator,
		})
	var context_definitions: Array = []
	for definition in _context_definitions:
		var minimums := {}
		for context in definition.minimums:
			minimums[str(context)] = definition.minimums[context]
		context_definitions.append({
			"id": str(definition.id), "priority": definition.priority, "minimums": minimums,
			"multiplier_numerator": definition.multiplier.numerator,
			"multiplier_denominator": definition.multiplier.denominator,
		})
	return {
		"active_player_ids": active, "spectator_ids": spectators,
		"victory_mode": _victory_mode, "victory_target": _victory_target,
		"information_visibility": _information_visibility, "phase_timers": timers,
		"reaction_window_msec": _reaction_window_msec,
		"public_hard_limit_msec": _public_hard_limit_msec,
		"reconnect_grace_msec": _reconnect_grace_msec,
		"ability_definitions": definitions, "normal_definitions": normal_definitions,
		"context_definitions": context_definitions, "match_started": match_started,
	}


static func from_dict(data: Dictionary) -> MatchConfig:
	var active: Array[StringName] = []
	for id: String in data.active_player_ids: active.append(StringName(id))
	var spectators: Array[StringName] = []
	for id: String in data.spectator_ids: spectators.append(StringName(id))
	var timers := {}
	for phase: String in data.phase_timers: timers[int(phase)] = data.phase_timers[phase]
	var definitions: Array[AbilityDefinition] = []
	for item: Dictionary in data.ability_definitions:
		var tags: Array[StringName] = []
		for tag: String in item.tags: tags.append(StringName(tag))
		definitions.append(AbilityDefinition.new(
			StringName(item.id), item.timing, tags, StringName(item.effect_id),
			item.field_duration, StringName(item.conflict_group),
			item.get("effect_parameters", {}), item.get("choice_schema", {})
		))
	var normal_definitions: Array[NormalHandDefinition] = []
	for item: Dictionary in data.get("normal_definitions", []):
		normal_definitions.append(NormalHandDefinition.new(
			StringName(item.id), item.priority, item.subset_size, StringName(item.rule_id),
			Rational.new(item.multiplier_numerator, item.multiplier_denominator)
		))
	var context_definitions: Array[ContextHandDefinition] = []
	for item: Dictionary in data.get("context_definitions", []):
		var minimums := {}
		for context: String in item.minimums:
			minimums[int(context)] = item.minimums[context]
		context_definitions.append(ContextHandDefinition.new(
			StringName(item.id), item.priority, minimums,
			Rational.new(item.multiplier_numerator, item.multiplier_denominator)
		))
	var script: Script = load("res://src/core/match/match_config.gd")
	var config: MatchConfig = script.new(
		active, spectators, data.victory_mode, data.victory_target,
		data.information_visibility, timers, data.reaction_window_msec,
		data.public_hard_limit_msec, data.reconnect_grace_msec, definitions,
		normal_definitions, context_definitions
	)
	config.match_started = data.match_started
	return config
