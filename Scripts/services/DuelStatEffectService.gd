extends Node
class_name DuelStatService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service

func _clear_bonuses(cards: Array):
	for card in cards:
		if is_instance_valid(card) and card.has_method("clear_temporary_display_bonus"):
			card.clear_temporary_display_bonus()

func set_guardian_star_bonus_multiplier(source_card, multiplier: float, _ctx: Dictionary = {}) -> void:
	if not is_instance_valid(source_card):
		return
	source_card.set_meta("guardian_star_bonus_multiplier", float(multiplier))
