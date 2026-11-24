extends RefCounted

const MatchConfig = preload("res://src/core/match/match_config.gd")
const FullCard = preload("res://src/core/cards/full_card_state.gd")
const HalfCard = preload("res://src/core/cards/half_card_state.gd")
const Field = preload("res://src/core/abilities/field_state.gd")
const Ability = preload("res://src/core/abilities/ability_state.gd")
const AbilityDefinition = preload("res://src/core/abilities/ability_definition.gd")
const ScoringTypes = preload("res://src/core/scoring/scoring_types.gd")
const Rational = preload("res://src/core/common/rational.gd")
const Evaluator = preload("res://src/core/scoring/submission_evaluator.gd")
const Projector = preload("res://src/core/match/snapshot_projector.gd")

var _settings: Dictionary
var _config: MatchConfig
var _definitions_by_id := {}


func evaluate(model: Dictionary, selections: Array) -> Dictionary:
	var staging: Dictionary = model.get("private_staging", {})
	if bool(staging.get("hand_locked", false)) and staging.has("submitted_score"):
		return {"score_breakdown": staging.submitted_score}
	var settings: Dictionary = model.get("lobby_settings", {}).duplicate()
	if not settings.has("active_player_ids"):
		return {}
	if not settings.has("ability_definitions"):
		settings["ability_definitions"] = []
	if _config == null or settings != _settings:
		_settings = settings
		_config = MatchConfig.from_dict(settings)
		_definitions_by_id.clear()
		for definition in _config.ability_definitions:
			_definitions_by_id[str(definition.id)] = definition
	var hand: Array[FullCard] = []
	var locked_cards := {}
	for card: Dictionary in model.get("private_hand", []):
		var id := StringName(card.get("card_id", ""))
		hand.append(FullCard.new(id, _half(card.first, str(id) + ":0"), _half(card.second, str(id) + ":1")))
		if bool(card.get("submission_locked", false)):
			locked_cards[id] = true
	for selection in selections:
		if selection is Dictionary and locked_cards.has(StringName(str(selection.get("card_id", "")))):
			return {"invalid_reason": "card_submission_locked"}
	var fields: Array = []
	for data: Dictionary in model.get("active_fields", []):
		var ability_id := StringName(data.get("ability_id", ""))
		var definition: AbilityDefinition = _definitions_by_id.get(str(ability_id))
		if data.has("effect_parameters"):
			definition = AbilityDefinition.new(
				ability_id, AbilityDefinition.Timing.FIELD, [], &"field_rule",
				int(data.get("remaining_rounds", 1)), &"", data.effect_parameters
			)
		if definition != null:
			fields.append(Field.new(Ability.new(ability_id, definition), StringName(data.get("source_player_id", ""))))
	var modifiers: Array[ScoringTypes.FactorModifier] = []
	for data: Dictionary in model.get("private_score_modifiers", []):
		modifiers.append(ScoringTypes.FactorModifier.new(StringName(data.factor_id), StringName(data.category_id),
			Rational.new(int(data.delta.numerator), int(data.delta.denominator)), &"", StringName(data.source_definition_id)))
	var result := Evaluator.evaluate(hand, selections, int(model.get("active_context", 0)),
		_config.normal_definitions, _config.context_definitions, modifiers, fields)
	if not result.is_valid:
		return {"invalid_reason": str(result.error_code)}
	return {"score_breakdown": Projector.score_breakdown(result.score_breakdown, result.selected_faces)}


func _half(data: Dictionary, fallback: String) -> HalfCard:
	var context := int(data.get("effective_context", data.get("base_context", 0)))
	var rank := int(data.get("effective_rank", data.get("base_rank", 1)))
	var suit := int(data.get("effective_suit", data.get("base_suit", 0)))
	var kind := int(data.get("kind", 0))
	if kind == 1:
		rank = 0
		suit = HalfCard.NO_SUIT
	var half := HalfCard.new(StringName(data.get("copy_id", fallback)), context, rank, suit, kind)
	if half.is_joker() and data.has("joker_suit"):
		half.set_joker_choice(data.joker_context, data.joker_suit, data.get("joker_rank", 0))
	return half
