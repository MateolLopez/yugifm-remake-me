extends Node
class_name DuelGraveyardService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null
var graveyard_service: DuelGraveyardService = null
var card_db_service: DuelCardDbService = null
var reveal_service: DuelRevealService = null
var animation_service: DuelAnimationService = null
var atk_state_service: DuelAttackStateService = null
var ui_service: DuelUiService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service
	graveyard_service = bm.graveyard_service
	card_db_service = bm.card_db_service
	reveal_service = bm.reveal_service
	animation_service = bm.animation_service
	atk_state_service = bm.atk_state_service
	ui_service = bm.ui_service

func send_monster_to_graveyard_as_cost(card: Node, owner: String, ctx: Dictionary = {}) -> bool:
	if bm == null:
		push_warning("DuelGraveyardService: BattleManager no asignado.")
		return false

	if not is_instance_valid(card):
		return false

	owner = card_runtime_service._norm_owner(owner)

	if owner == "":
		return false

	if card_runtime_service._card_kind(card) != "MONSTER":
		return false

	var slot = zone_service._card_slot(card)

	var grave_entry = _grave_entry_from_card(card)
	grave_entry["grave_owner"] = owner
	grave_entry["sent_order"] = _next_graveyard_order()
	grave_entry["cause"] = "SEND_TO_GRAVE_AS_COST"
	grave_entry["was_destroyed"] = false

	var effect_source = ctx.get("cost_source", ctx.get("effect_source", ctx.get("source", null)))

	var send_ctx := {
		"battle_manager": bm,
		"source": card,
		"sent_card": card,
		"cost_source": effect_source,
		"effect_source": effect_source,
		"controller": owner,
		"cause": "SEND_TO_GRAVE_AS_COST",
		"was_destroyed": false,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
		"turn_index": bm.turn_index
	}

	for k in ctx.keys():
		if not send_ctx.has(k):
			send_ctx[k] = ctx[k]

	if event_service.has_method("_unregister_card_with_effect_engine"):
		event_service._unregister_card_with_effect_engine(card)

	if owner == "Player":
		if card in bm.player_cards_on_battlefield:
			bm.player_cards_on_battlefield.erase(card)

		bm.player_graveyard.append(grave_entry)
	else:
		if card in bm.opponent_cards_on_battlefield:
			bm.opponent_cards_on_battlefield.erase(card)

		bm.opponent_graveyard.append(grave_entry)

	if is_instance_valid(slot):
		slot.set("card_in_slot", false)

		if "card_ref" in slot:
			slot.set("card_ref", null)

		if slot.has_meta("card_ref"):
			slot.remove_meta("card_ref")

		var slot_shape = slot.get_node_or_null("Area2D/CollisionShape2D")
		if slot_shape:
			slot_shape.disabled = false

		var rival_slots_root := bm.get_node_or_null("../../CardSlotsRival")

		if rival_slots_root != null and slot.get_parent() == rival_slots_root:
			if "empty_monster_card_slots" in bm:
				if not bm.empty_monster_card_slots.has(slot):
					bm.empty_monster_card_slots.append(slot)

	var cshape = card.get_node_or_null("Area2D/CollisionShape2D")
	if cshape:
		cshape.disabled = true

	if atk_state_service.has_method("_clear_multi_for"):
		atk_state_service._clear_multi_for(card)

	if zone_service.has_method("_clear_card_slot"):
		zone_service._clear_card_slot(card)

	if zone_service.has_method("_clean_battlefield_lists"):
		zone_service._clean_battlefield_lists()

	if event_service.has_method("_emit_duel_event"):
		event_service._emit_duel_event("ON_LEAVE_FIELD", send_ctx)
		event_service._emit_duel_event("ON_SEND_TO_GRAVE", send_ctx)
		event_service._emit_duel_event("ON_SEND_TO_GRAVE_AS_COST", send_ctx)

	if event_service.has_method("_refresh_effect_engine_continuous_buffs"):
		event_service._refresh_effect_engine_continuous_buffs()

	if ui_service.has_method("_refresh_card_usage_overlays"):
		ui_service._refresh_card_usage_overlays()

	card.queue_free()

	return true

func _grave_entry_from_card(card: Node) -> Dictionary:
	if not is_instance_valid(card):
		return {}

	var entry := {
		"id": str(card.id) if ("id" in card) else "",
		"cardname": str(card.cardname) if ("cardname" in card) else "",
		"kind": str(card.kind).to_upper() if ("kind" in card) else "",
		"attribute": str(card.attribute).to_upper() if ("attribute" in card) else "",
		"race": str(card.race).to_upper() if ("race" in card) else "",
		"tags": [],
		"keywords": []
	}

	if "tags" in card and typeof(card.tags) == TYPE_ARRAY:
		entry["tags"] = card.tags.duplicate()

	if "keywords" in card and typeof(card.keywords) == TYPE_ARRAY:
		entry["keywords"] = card.keywords.duplicate()

	return entry

func _remove_grave_entry_at(grave_owner: String, index: int) -> void:
	var owner := card_runtime_service._norm_owner(grave_owner)

	if index < 0:
		return

	if owner == "Player":
		if index < bm.player_graveyard.size():
			bm.player_graveyard.remove_at(index)
	elif owner == "Opponent":
		if index < bm.opponent_graveyard.size():
			bm.opponent_graveyard.remove_at(index)

func _next_graveyard_order() -> int:
	bm.graveyard_order_counter += 1
	return bm.graveyard_order_counter


func revive_last_destroyed_monster_from_graveyard(source: Node, ctx: Dictionary, params: Dictionary) -> bool:
	var controller_param := str(params.get("controller", "SELF")).to_upper()
	var source_grave := str(params.get("source_grave", "BOTH")).to_upper()
	var position := str(params.get("position", "FACEUP_ATK")).to_upper()
	var require_destroyed := bool(params.get("require_destroyed", true))

	var source_controller := card_runtime_service._norm_owner(ctx.get("controller", ""))
	if source_controller == "" and is_instance_valid(source) and ("owner_side" in source):
		source_controller = ("Player" if str(source.owner_side).to_upper() == "PLAYER" else "Opponent")
	source_controller = card_runtime_service._norm_owner(source_controller)

	if source_controller == "":
		return false

	var summon_controller := source_controller
	if controller_param == "OPPONENT":
		summon_controller = ("Opponent" if source_controller == "Player" else "Player")
	elif controller_param == "SELF":
		summon_controller = source_controller

	summon_controller = card_runtime_service._norm_owner(summon_controller)

	var free_slot := zone_service._get_free_monster_slot_for(summon_controller)
	if free_slot == null:
		return false

	var found := _find_last_destroyed_monster_grave_entry(source_controller, source_grave, require_destroyed)
	if found.is_empty():
		return false

	var entry: Dictionary = found.get("entry", {})
	var grave_owner := card_runtime_service._norm_owner(found.get("grave_owner", ""))
	var grave_index := int(found.get("index", -1))

	if entry.is_empty():
		return false

	var revive_id := str(entry.get("id", ""))
	if revive_id == "":
		return false

	var card_def := card_db_service._get_db_card_by_id(revive_id)
	if card_def.is_empty():
		return false

	var card := card_db_service._spawn_card_from_db_entry(card_def, summon_controller)
	if not is_instance_valid(card):
		return false

	card.set_meta("played_from_hand", false)
	card.set_meta("revived_from_graveyard", true)
	card.set_meta("revived_by", source.cardname if is_instance_valid(source) and ("cardname" in source) else "UNKNOWN")

	_remove_grave_entry_at(grave_owner, grave_index)

	if position == "FACEUP_ATK":
		card_runtime_service._set_card_face_down(card, false)
		if card.has_method("set_defense_position"):
			card.set_defense_position(false)
		else:
			card.in_defense = false

	elif position == "FACEUP_DEF":
		card_runtime_service._set_card_face_down(card, false)
		if card.has_method("set_defense_position"):
			card.set_defense_position(true)
		else:
			card.in_defense = true

	elif position == "FACEDOWN_DEF":
		card_runtime_service._set_card_face_down(card, true)
		if card.has_method("set_defense_position"):
			card.set_defense_position(true)
		else:
			card.in_defense = true

	else:
		card_runtime_service._set_card_face_down(card, false)
		if card.has_method("set_defense_position"):
			card.set_defense_position(false)
		else:
			card.in_defense = false

	zone_service._set_card_slot(card, free_slot)
	zone_service._place_card_in_slot(card, free_slot, "EFFECT")

	if position == "FACEUP_ATK":
		card_runtime_service._set_card_face_down(card, false)
		reveal_service.reveal_card(card)

	elif position == "FACEUP_DEF":
		card_runtime_service._set_card_face_down(card, false)
		reveal_service.reveal_card(card)

	elif position == "FACEDOWN_DEF":
		card_runtime_service._set_card_face_down(card, true)

	if card is Node2D:
		animation_service._play_monster_reborn_fx_on_card(card)

	event_service._emit_duel_event("ON_SUMMON_BY_EFFECT", {
		"battle_manager": bm,
		"source": card,
		"controller": summon_controller,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
		"created_from": source,
		"revived_from_graveyard": true,
		"original_grave_owner": grave_owner
	})

	return true

func _find_last_destroyed_monster_grave_entry(source_controller: String, source_grave: String, require_destroyed: bool) -> Dictionary:
	var allowed_owners: Array[String] = []

	var src := card_runtime_service._norm_owner(source_controller)
	var opponent := ("Opponent" if src == "Player" else "Player")

	match source_grave:
		"SELF":
			allowed_owners.append(src)
		"OPPONENT":
			allowed_owners.append(opponent)
		_:
			allowed_owners.append("Player")
			allowed_owners.append("Opponent")

	var best: Dictionary = {}
	var best_order := -1

	for owner in allowed_owners:
		var grave: Array = bm.player_graveyard if owner == "Player" else bm.opponent_graveyard

		for i in range(grave.size()):
			var entry = grave[i]
			if typeof(entry) != TYPE_DICTIONARY:
				continue

			if str(entry.get("kind", "")).to_upper() != "MONSTER":
				continue

			if require_destroyed and not bool(entry.get("was_destroyed", false)):
				continue

			var entry_id := str(entry.get("id", ""))
			if entry_id == "":
				continue

			var order := int(entry.get("sent_order", -1))
			if order > best_order:
				best_order = order
				best = {
					"entry": entry,
					"grave_owner": owner,
					"index": i
				}

	return best

func _schedule_self_revival_at_turn_end(card: Node, card_owner: String, position: String, require_played_from_hand: bool, require_attack_position_on_destroy: bool) -> bool:
	if not is_instance_valid(card):
		return false

	if require_played_from_hand and not bool(card.get_meta("played_from_hand", false)):
		return false

	if require_attack_position_on_destroy and bool(card.in_defense):
		return false

	var entry := {
		"id": str(card.id) if ("id" in card) else "",
		"controller": card_runtime_service._norm_owner(card_owner),
		"position": str(position).to_upper(),
		"due_turn_end_owner": ("Opponent" if bm.is_opponent_turn else "Player")
	}

	if entry["id"] == "":
		return false

	bm.pending_end_turn_self_revives.append(entry)
	return true

func _revive_card_from_db_entry_at_turn_end(entry: Dictionary) -> bool:
	var controller := card_runtime_service._norm_owner(entry.get("controller", ""))
	var position := str(entry.get("position", "FACEUP_ATK")).to_upper()
	var revive_id := str(entry.get("id", ""))

	if revive_id == "":
		return false

	var free_slot := zone_service._get_free_monster_slot_for(controller)
	if free_slot == null:
		return false

	var db: Array = card_db_service._get_cards_db()
	if db.is_empty():
		return false

	var picked: Dictionary = {}
	for card_def in db:
		if typeof(card_def) != TYPE_DICTIONARY:
			continue
		if str(card_def.get("id", "")) == revive_id:
			picked = card_def
			break

	if picked.is_empty():
		return false

	var card := card_db_service._spawn_card_from_db_entry(picked, controller)
	if not is_instance_valid(card):
		return false

	card.set_meta("played_from_hand", false)

	if position == "FACEUP_ATK":
		card_runtime_service._set_card_face_down(card, false)
		if card.has_method("set_defense_position"):
			card.set_defense_position(false)
		else:
			card.in_defense = false
	elif position == "FACEUP_DEF":
		card_runtime_service._set_card_face_down(card, false)
		if card.has_method("set_defense_position"):
			card.set_defense_position(true)
		else:
			card.in_defense = true
	elif position == "FACEDOWN_DEF":
		card_runtime_service._set_card_face_down(card, true)
		if card.has_method("set_defense_position"):
			card.set_defense_position(true)
		else:
			card.in_defense = true
	else:
		card_runtime_service._set_card_face_down(card, false)
		if card.has_method("set_defense_position"):
			card.set_defense_position(false)
		else:
			card.in_defense = false

	zone_service._set_card_slot(card, free_slot)
	zone_service._place_card_in_slot(card, free_slot, "EFFECT")

	if position == "FACEUP_ATK":
		card_runtime_service._set_card_face_down(card, false)
		reveal_service.reveal_card(card)
	elif position == "FACEUP_DEF":
		card_runtime_service._set_card_face_down(card, false)
		reveal_service.reveal_card(card)
	elif position == "FACEDOWN_DEF":
		card_runtime_service._set_card_face_down(card, true)

	event_service._emit_duel_event("ON_SUMMON_BY_EFFECT", {
		"battle_manager": bm,
		"source": card,
		"controller": controller,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player")
	})

	return true

func _process_pending_end_turn_self_revives(turn_owner: String) -> void:
	var remaining: Array = []

	for entry in bm.pending_end_turn_self_revives:
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		var due_owner := card_runtime_service._norm_owner(entry.get("due_turn_end_owner", ""))
		if due_owner != card_runtime_service._norm_owner(turn_owner):
			remaining.append(entry)
			continue

		var ok := _revive_card_from_db_entry_at_turn_end(entry)
		if not ok:
			pass

	bm.pending_end_turn_self_revives = remaining
