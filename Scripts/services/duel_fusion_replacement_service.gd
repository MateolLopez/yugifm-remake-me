extends Node
class_name DuelFusionReplacementService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null
var destruction_service: DuelDestructionService = null
var animation_service: DuelAnimationService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service
	destruction_service = bm.destruction_service
	animation_service = bm.animation_service

func is_waiting_for_fusion_replacement() -> bool:
	return bm.fusion_replacement_mode

func await_fusion_replacement_slot(owner: String, fusion_card: Node) -> Node:
	owner = card_runtime_service._norm_owner(owner)

	# La IA no elige manualmente. Reemplaza automáticamente el monstruo de menor ATK.
	if owner == "Opponent":
		return await _choose_opponent_fusion_replacement_slot()

	bm.fusion_replacement_mode = true
	bm.fusion_replacement_owner = owner
	bm.fusion_replacement_card = fusion_card
	bm.fusion_replacement_chosen_slot = null

	print("Descarta un monstruo de tu campo.")

	await bm.fusion_replacement_slot_ready

	var chosen = bm.fusion_replacement_chosen_slot

	bm.fusion_replacement_mode = false
	bm.fusion_replacement_owner = ""
	bm.fusion_replacement_card = null
	bm.fusion_replacement_chosen_slot = null

	return chosen

func receive_fusion_replacement_card(card: Node) -> void:
	if not bm.fusion_replacement_mode:
		return

	if not is_instance_valid(card):
		return

	var owner := card_runtime_service._norm_owner(zone_service._owner_of(card))
	if owner != bm.fusion_replacement_owner:
		return

	var slot := zone_service._get_card_current_slot(card)
	if slot == null:
		return

	bm.fusion_replacement_chosen_slot = slot

	destruction_service.destroy_card(card, owner, "SEND_TO_GRAVE_FUSION_REPLACE")

	if has_method("wait_until_duel_idle"):
		await animation_service.wait_until_duel_idle()

	bm.fusion_replacement_slot_ready.emit()

func _choose_opponent_fusion_replacement_slot() -> Node:
	var candidates := []

	for card in bm.opponent_cards_on_battlefield:
		if is_instance_valid(card):
			candidates.append(card)

	if candidates.is_empty():
		return null

	candidates.sort_custom(func(a, b):
		var a_atk := int(a.get("atk"))
		var b_atk := int(b.get("atk"))
		return a_atk < b_atk
	)

	var victim = candidates[0]
	var slot := zone_service._get_card_current_slot(victim)

	if slot == null:
		return null

	destruction_service.destroy_card(victim, "Opponent", "SEND_TO_GRAVE_FUSION_REPLACE")

	if has_method("wait_until_duel_idle"):
		await animation_service.wait_until_duel_idle()

	return slot
