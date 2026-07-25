extends Node
class_name DuelBanishService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null
var atk_state_service: DuelAttackStateService = null
var ui_service: DuelUiService = null

var _banish_order_counter: int = 0


func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service
	atk_state_service = bm.atk_state_service
	ui_service = bm.ui_service


func banish_card_from_field_by_effect(
	card: Node,
	owner: String,
	ctx: Dictionary = {}
) -> bool:
	if bm == null:
		push_warning("DuelBanishService: BattleManager no asignado.")
		return false

	if not is_instance_valid(card):
		return false

	owner = card_runtime_service._norm_owner(owner)

	if owner == "":
		owner = card_runtime_service._norm_owner(
			zone_service._owner_of(card)
		)

	if owner == "":
		return false

	var slot = zone_service._card_slot(card)
	var effect_source = ctx.get(
		"effect_source",
		ctx.get("source", null)
	)

	var banish_entry := _banish_entry_from_card(card)
	banish_entry["banish_owner"] = owner
	banish_entry["banish_order"] = _next_banish_order()
	banish_entry["cause"] = str(
		ctx.get("cause", "BANISH_BY_EFFECT")
	)
	banish_entry["was_destroyed"] = false
	banish_entry["banished_face_down"] = false

	if event_service.has_method("_unregister_card_with_effect_engine"):
		event_service._unregister_card_with_effect_engine(card)

	if owner == "Player":
		if card in bm.player_cards_on_battlefield:
			bm.player_cards_on_battlefield.erase(card)

		bm.player_banished.append(banish_entry)
	else:
		if card in bm.opponent_cards_on_battlefield:
			bm.opponent_cards_on_battlefield.erase(card)

		bm.opponent_banished.append(banish_entry)

	_release_card_slot(card, slot)

	if atk_state_service.has_method("_clear_multi_for"):
		atk_state_service._clear_multi_for(card)

	if zone_service.has_method("_clear_card_slot"):
		zone_service._clear_card_slot(card)

	if card.has_method("move_to_zone"):
		card.move_to_zone("BANISHED")
	elif "current_zone" in card:
		card.current_zone = "BANISHED"

	if zone_service.has_method("_clean_battlefield_lists"):
		zone_service._clean_battlefield_lists()

	var banish_ctx := {
		"battle_manager": bm,
		"source": card,
		"banished_card": card,
		"effect_source": effect_source,
		"controller": owner,
		"cause": banish_entry["cause"],
		"was_destroyed": false,
		"turn_owner": (
			"Opponent" if bm.is_opponent_turn else "Player"
		),
		"turn_index": bm.turn_index
	}

	for key in ctx.keys():
		if not banish_ctx.has(key):
			banish_ctx[key] = ctx[key]

	if event_service.has_method("_emit_duel_event"):
		event_service._emit_duel_event(
			"ON_LEAVE_FIELD",
			banish_ctx
		)
		event_service._emit_duel_event(
			"ON_BANISH",
			banish_ctx
		)

	if event_service.has_method(
		"_refresh_effect_engine_continuous_buffs"
	):
		event_service._refresh_effect_engine_continuous_buffs()

	if ui_service.has_method("_refresh_card_usage_overlays"):
		ui_service._refresh_card_usage_overlays()

	card.queue_free()

	return true


func _release_card_slot(card: Node, slot: Node) -> void:
	if is_instance_valid(slot):
		slot.set("card_in_slot", false)
		slot.set_meta("card_ref", null)

		var slot_shape = slot.get_node_or_null(
			"Area2D/CollisionShape2D"
		)

		if slot_shape != null:
			slot_shape.disabled = false

		var rival_slots_root := bm.get_node_or_null(
			"../../CardSlotsRival"
		)

		if rival_slots_root != null \
		and slot.get_parent() == rival_slots_root:
			if not bm.empty_monster_card_slots.has(slot):
				bm.empty_monster_card_slots.append(slot)

	var card_shape = card.get_node_or_null(
		"Area2D/CollisionShape2D"
	)

	if card_shape != null:
		card_shape.disabled = true


func _next_banish_order() -> int:
	_banish_order_counter += 1
	return _banish_order_counter


func _banish_entry_from_card(card: Node) -> Dictionary:
	return {
		"id": str(card.id) if "id" in card else "",
		"art_id_override": (
			str(card.art_id_override)
			if "art_id_override" in card
			else ""
		),
		"kind": str(card.kind) if "kind" in card else "",
		"cardname": (
			str(card.cardname)
			if "cardname" in card
			else ""
		),
		"attribute": (
			str(card.attribute)
			if "attribute" in card
			else ""
		),
		"race": str(card.race) if "race" in card else "",
		"level": int(card.level) if "level" in card else 0,
		"atk": int(card.atk) if "atk" in card else 0,
		"def": int(card.def) if "def" in card else 0,
		"guardian_star": (
			card.guardian_star.duplicate(true)
			if "guardian_star" in card
			else []
		),
		"active_guardian_star_index": (
			int(card.active_guardian_star_index)
			if "active_guardian_star_index" in card
			else 0
		),
		"tags": (
			card.tags.duplicate(true)
			if "tags" in card
			else []
		),
		"keywords": (
			card.keywords.duplicate(true)
			if "keywords" in card
			else []
		),
		"description": (
			str(card.description)
			if "description" in card
			else ""
		),
		"effects": (
			card.effects.duplicate(true)
			if "effects" in card
			else []
		),
		"owner_side": (
			str(card.owner_side)
			if "owner_side" in card
			else ""
		)
	}
