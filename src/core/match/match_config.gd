class_name MatchConfig
extends RefCounted

const GameTypes = preload("res://src/core/common/game_types.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")

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
	initial_ability_definitions: Array
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


func set_victory_target(value: int) -> StringName:
	if match_started: return &"config_locked"
	_victory_target = value
	return &""


func set_victory_mode(value: int) -> StringName:
	if match_started: return &"config_locked"
	_victory_mode = value
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
		})
	return {
		"active_player_ids": active, "spectator_ids": spectators,
		"victory_mode": _victory_mode, "victory_target": _victory_target,
		"information_visibility": _information_visibility, "phase_timers": timers,
		"reaction_window_msec": _reaction_window_msec,
		"public_hard_limit_msec": _public_hard_limit_msec,
		"reconnect_grace_msec": _reconnect_grace_msec,
		"ability_definitions": definitions, "match_started": match_started,
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
			item.field_duration, StringName(item.conflict_group)
		))
	var script: Script = load("res://src/core/match/match_config.gd")
	var config: MatchConfig = script.new(
		active, spectators, data.victory_mode, data.victory_target,
		data.information_visibility, timers, data.reaction_window_msec,
		data.public_hard_limit_msec, data.reconnect_grace_msec, definitions
	)
	config.match_started = data.match_started
	return config
