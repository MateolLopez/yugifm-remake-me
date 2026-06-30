extends Node
class_name DuelEquipService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null
var card_play_service: DuelCardPlayService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service
	card_play_service = bm.card_play_service

func start_equip_from_hand(spell_card: Node, controller: String) -> void:
	if not is_instance_valid(spell_card):
		return

	var origin_slot = zone_service._card_slot(spell_card)

	if is_instance_valid(origin_slot):
		spell_card.set_meta("equip_origin_slot", origin_slot)

	bm.pending_equip_card = spell_card
	bm.pending_equip_controller = card_runtime_service._norm_owner(controller)
	bm.equip_targeting = true

func resolve_equip_target(target_monster: Node) -> void:
	if not bm.equip_targeting:
		return
	if not is_instance_valid(bm.pending_equip_card):
		_cancel_equip_targeting()
		return
	if not is_instance_valid(target_monster):
		_cancel_equip_targeting()
		return

	if card_runtime_service._card_kind(target_monster) != "MONSTER" or not target_monster.is_on_field():
		_cancel_equip_targeting()
		return

	var res: Dictionary = _apply_equip_spell_to_target(bm.pending_equip_card, target_monster, bm.pending_equip_controller)
	if not bool(res.get("success", false)):
		print("Equip fallido: ", str(res.get("message", "sin mensaje")))
		return

	var ph := get_node_or_null("../../PlayerHand")
	if ph and ph.has_method("remove_card_from_hand"):
		ph.remove_card_from_hand(bm.pending_equip_card)

	card_play_service._send_spell_to_graveyard(bm.pending_equip_card, bm.pending_equip_controller)
	_cancel_equip_targeting()


func _cancel_equip_targeting() -> void:
	bm.equip_targeting = false
	bm.pending_equip_card = null
	bm.pending_equip_controller = ""
	$"../../InputManager".inputs_disabled = false

func _apply_equip_spell_to_target(spell_card: Node, target: Node, controller: String) -> Dictionary:
	if target.has_method("has_keyword") and target.has_keyword("NO_EQUIP"):
		return {"success": false, "message": "El objetivo tiene NO_EQUIP."}

	if not spell_card.has_method("get_effects"):
		return {"success": false, "message": "El spell no tiene get_effects()."}

	var effs: Array = spell_card.get_effects()
	var equip_def: Dictionary = {}
	for e in effs:
		if e is Dictionary and str(e.get("trigger","")).to_upper() == "ON_ACTIVATE":
			equip_def = e
			break
	if equip_def.is_empty():
		return {"success": false, "message": "El spell no tiene ON_ACTIVATE."}

	var params: Dictionary = equip_def.get("params", {})
	if not _equip_requirements_ok(target, params):
		return {"success": false, "message": "El objetivo no cumple requisitos de equip (race/tag)."}

	var inst_id := str(Time.get_ticks_usec())
	var equip_instance := {
		"instance_id": inst_id,
		"spell_id": str(spell_card.id),
		"spell_name": str(spell_card.cardname),
		"mod": params.get("mod", {}),
		"set": params.get("set", {}),
		"grant_keywords": params.get("grant_keywords", []),
		"meta": {}
	}

	if target.has_method("add_equip_instance"):
		target.add_equip_instance(equip_instance)
		return {"success": true, "message": "Equip aplicado."}

	return {"success": false, "message": "El objetivo no soporta add_equip_instance()."}

func _equip_requirements_ok(target: Node, params: Dictionary) -> bool:
	var req: Dictionary = params.get("requirements", {})
	if req.is_empty():
		return true

	var require_race := str(req.get("race", ""))
	if require_race != "":
		if str(target.race).to_upper() != require_race.to_upper():
			return false

	var require_tag := str(req.get("tag", ""))
	if require_tag != "":
		var tags: Array = target.tags if ("tags" in target) else []
		var ok := false
		for t in tags:
			if str(t) == require_tag: 
				ok = true
				break
		if not ok:
			return false

	return true
