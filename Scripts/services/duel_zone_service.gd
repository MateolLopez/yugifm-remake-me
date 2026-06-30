extends Node
class_name DuelZoneService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var card_activation_service: DuelCardActivationService = null
var event_service: DuelEventService = null
var ui_service: DuelUiService = null
var reveal_service: DuelRevealService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	card_activation_service = bm.card_activation_service
	event_service = bm.event_service
	ui_service = bm.ui_service
	reveal_service = bm.reveal_service

func _card_slot(card):
	if not is_instance_valid(card):
		return null
	if "current_slot" in card:
		return card.current_slot
	if "card_slot_card_is_in" in card:
		return card.card_slot_card_is_in
	return null

func _set_card_slot(card, slot) -> void:
	if not is_instance_valid(card):
		return
	if card.has_method("set_field_slot"):
		card.set_field_slot(slot)
	else:
		if "current_slot" in card:
			card.current_slot = slot
		if "card_slot_card_is_in" in card:
			card.card_slot_card_is_in = slot

func _clear_card_slot(card) -> void:
	if not is_instance_valid(card):
		return
	if card.has_method("clear_field_slot"):
		card.clear_field_slot()
	else:
		if "current_slot" in card:
			card.current_slot = null
		if "card_slot_card_is_in" in card:
			card.card_slot_card_is_in = null

func _get_free_monster_slot_for(controller: String) -> Node2D:
	var norm = card_runtime_service._norm_owner(controller)
	var slots_root := get_node_or_null("../../CardSlots") if norm == "Player" else get_node_or_null("../../CardSlotsRival")
	if not is_instance_valid(slots_root):
		return null

	for s in slots_root.get_children():
		if not is_instance_valid(s):
			continue
		if str(s.get("card_slot_type")) != "Monster":
			continue
		if bool(s.get("card_in_slot")):
			continue
		return s

	return null

func _get_free_spelltrap_slot_for(controller: String) -> Node2D:
	var norm = card_runtime_service._norm_owner(controller)
	var slots_root := get_node_or_null("../../CardSlots") if norm == "Player" else get_node_or_null("../../CardSlotsRival")
	if not is_instance_valid(slots_root):
		return null

	for s in slots_root.get_children():
		if not is_instance_valid(s):
			continue

		var t := str(s.get("card_slot_type"))
		if t != "SpellTrap" and t != "Spell" and t != "Trap":
			continue

		if bool(s.get("card_in_slot")):
			continue

		return s

	return null

func _place_card_in_slot(card: Node2D, slot: Node2D, placement_origin: String = "PLAY", snap_visual: bool = true) -> void:
	if not is_instance_valid(card) or not is_instance_valid(slot):
		return
	var cardowner = card_runtime_service._card_owner_side(card)
	var kind = card_runtime_service._card_kind(card)

	_set_card_slot(card, slot)
	slot.set("card_in_slot", true)
	slot.set_meta("card_ref", card)

	var should_reveal := false
	if kind == "TRAP":
		card_runtime_service._set_card_face_down(card, true)
		should_reveal = false
		bm.reaction_set_order_counter += 1
		card.set_meta("set_order", bm.reaction_set_order_counter)
	elif kind == "SPELL":
		if placement_origin == "SET":
			card_runtime_service._set_card_face_down(card, true)
			should_reveal = false
		elif card_activation_service._has_immediate_effect(card):
			card_runtime_service._set_card_face_down(card, false)
			should_reveal = true
		else:
			card_runtime_service._set_card_face_down(card, true)

	if card.has_method("set_show_back_only"):
		card.set_show_back_only(false)
	if card.has_method("move_to_zone"):
		card.move_to_zone("FIELD")
	var cm = get_node_or_null("../../CardManager")
	if cm:
		if snap_visual:
			card.scale = Vector2(cm.FIELD_SCALE, cm.FIELD_SCALE)
			cm._snap_card_to_slot_center(card, slot)

	card.z_index = -4

	if kind == "MONSTER":
		var arr = (bm.player_cards_on_battlefield if cardowner == "Player" else bm.opponent_cards_on_battlefield)
		if not arr.has(card):
			arr.append(card)

	event_service._register_card_with_effect_engine(card, cardowner)

	match kind:
		"MONSTER":
			bm.emit_signal("monster_played", card, cardowner)
		"SPELL":
			bm.emit_signal("spell_activated", card, cardowner)
		"TRAP":
			bm.emit_signal("trap_activated", card, cardowner)

	if (kind == "SPELL" or kind == "TRAP") and placement_origin == "PLAY":
		var cm_track := get_node_or_null("../../CardManager")
		if cm_track:
			if "played_spellortrap_card_this_turn" in cm_track:
				cm_track.played_spellortrap_card_this_turn = true

	if kind == "TRAP":
		event_service._emit_duel_event("ON_PLAY", {
			"battle_manager": bm,
			"source": card,
			"controller": cardowner,
			"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player")
		})
	elif kind == "SPELL" and should_reveal:
		card_activation_service.start_spell_activation(card, cardowner)
		return

	if should_reveal:
		reveal_service.reveal_card(card)
		if kind == "MONSTER" and placement_origin == "PLAY":
			event_service._trigger_on_play_effects(card, cardowner)
	
	ui_service._refresh_card_usage_overlays()

func register_card_played(card, cardowner: String) -> void:
	if not is_instance_valid(card):
		return
	cardowner = card_runtime_service._norm_owner(cardowner)
	card_runtime_service._set_card_owner_side(card, cardowner)
	if card.has_method("apply_owner_collision_layers"):
		card.apply_owner_collision_layers()
	var slot = _card_slot(card)
	if slot == null:
		return
	_place_card_in_slot(card, slot)

func _owner_of(card) -> String:
	if card in bm.player_cards_on_battlefield:
		return "Player"
	if card in bm.opponent_cards_on_battlefield:
		return "Opponent"
	return ""

func _clean_battlefield_lists():
	bm.player_cards_on_battlefield = bm.player_cards_on_battlefield.filter(is_instance_valid)
	bm.opponent_cards_on_battlefield = bm.opponent_cards_on_battlefield.filter(is_instance_valid)

func _controlled_monsters(owner: String) -> Array:
	owner = card_runtime_service._norm_owner(owner)

	if owner == "Player":
		return bm.player_cards_on_battlefield.duplicate()

	if owner == "Opponent":
		return bm.opponent_cards_on_battlefield.duplicate()

	return []

func _get_card_current_slot(card: Node) -> Node:
	if not is_instance_valid(card):
		return null

	if "current_slot" in card and card.current_slot != null:
		return card.current_slot

	if "card_slot_card_is_in" in card and card.card_slot_card_is_in != null:
		return card.card_slot_card_is_in

	return null

func _reserve_slot_for_card(card: Node2D, slot: Node2D) -> void:
	if not is_instance_valid(card) or not is_instance_valid(slot):
		return

	_set_card_slot(card, slot)
	slot.set("card_in_slot", true)
	slot.set_meta("card_ref", card)
