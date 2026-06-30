extends Node
class_name DuelCardPlayService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null
var animation_service: DuelAnimationService = null
var graveyard_service: DuelGraveyardService = null


func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service
	animation_service = bm.animation_service
	graveyard_service = bm.graveyard_service

func try_play_monster_from_hand(card, facedown: bool, preferred_slot: Node2D = null) -> bool:
	if bm.duel_finished:
		return false

	if bm.is_opponent_turn:
		return false

	if animation_service.is_duel_animating():
		return false

	if not is_instance_valid(card):
		return false

	if not ("current_zone" in card) or str(card.current_zone).to_upper() != "HAND":
		return false

	if str(card_runtime_service._card_kind(card)).to_upper() != "MONSTER":
		return false

	var cm := get_node_or_null("../../CardManager")
	if cm != null and ("played_monster_card_this_turn" in cm) and bool(cm.played_monster_card_this_turn):
		return false

	var free_slot: Node2D = preferred_slot

	if not is_instance_valid(free_slot):
		var slots_root := get_node_or_null("../../CardSlots")
		if not is_instance_valid(slots_root):
			return false

		for s in slots_root.get_children():
			if not is_instance_valid(s):
				continue
			if str(s.get("card_slot_type")) != "Monster":
				continue
			if bool(s.get("card_in_slot")):
				continue

			free_slot = s
			break

	if not is_instance_valid(free_slot):
		return false

	if bool(free_slot.get("card_in_slot")):
		return false

	animation_service._begin_duel_animation_lock()

	var current_global_position = card.global_position
	var current_rotation = card.rotation
	var current_scale = card.scale

	var ph := get_node_or_null("../../PlayerHand")
	if ph and ph.has_method("remove_card_from_hand"):
		ph.remove_card_from_hand(card, false)

	card.global_position = current_global_position
	card.rotation = current_rotation
	card.scale = current_scale

	card_runtime_service._set_card_owner_side(card, "Player")

	if card.has_method("apply_owner_collision_layers"):
		card.apply_owner_collision_layers()

	if facedown:
		animation_service._play_duel_sfx("summon_set")
		card_runtime_service._set_card_face_down(card, true)
	else:
		animation_service._play_duel_sfx("summon_faceup")
		card_runtime_service._set_card_face_down(card, false)

	card.set_meta("played_from_hand", true)

	await animation_service._animate_card_to_slot_visual(card, free_slot, 0.28)

	zone_service._place_card_in_slot(card, free_slot, "PLAY", true)

	if cm != null and ("played_monster_card_this_turn" in cm):
		cm.played_monster_card_this_turn = true

	if ph and ph.has_method("update_hand_positions"):
		ph.update_hand_positions()

	animation_service._end_duel_animation_lock()

	return true

func try_set_from_hand(card, preferred_slot: Node2D = null) -> bool:
	if bm.duel_finished:
		return false

	if bm.is_opponent_turn:
		return false

	if animation_service.is_duel_animating():
		return false

	if not is_instance_valid(card):
		return false

	if not ("current_zone" in card) or str(card.current_zone).to_upper() != "HAND":
		return false

	var kind := str(card_runtime_service._card_kind(card)).to_upper()
	if kind != "SPELL" and kind != "TRAP":
		return false

	var cm := get_node_or_null("../../CardManager")
	if cm != null and ("played_spellortrap_card_this_turn" in cm) and bool(cm.played_spellortrap_card_this_turn):
		return false

	var free_slot: Node2D = preferred_slot

	if not is_instance_valid(free_slot):
		var slots_root := get_node_or_null("../../CardSlots")
		if not is_instance_valid(slots_root):
			return false

		for s in slots_root.get_children():
			if not is_instance_valid(s):
				continue

			var slot_type := str(s.get("card_slot_type"))
			if slot_type != "SpellTrap" and slot_type != "Spell" and slot_type != "Trap":
				continue

			if bool(s.get("card_in_slot")):
				continue

			free_slot = s
			break

	if not is_instance_valid(free_slot):
		return false

	if bool(free_slot.get("card_in_slot")):
		return false

	animation_service._begin_duel_animation_lock()

	var current_global_position = card.global_position
	var current_rotation = card.rotation
	var current_scale = card.scale

	var ph := get_node_or_null("../../PlayerHand")
	if ph and ph.has_method("remove_card_from_hand"):
		ph.remove_card_from_hand(card, false)

	card.global_position = current_global_position
	card.rotation = current_rotation
	card.scale = current_scale

	card_runtime_service._set_card_owner_side(card, "Player")

	if card.has_method("apply_owner_collision_layers"):
		card.apply_owner_collision_layers()

	animation_service._play_duel_sfx("set_spelltrap")

	card_runtime_service._set_card_face_down(card, true)
	card.set_meta("played_from_hand", true)

	await animation_service._animate_card_to_slot_visual(card, free_slot, 0.24)

	zone_service._place_card_in_slot(card, free_slot, "SET", true)

	if cm != null and ("played_spellortrap_card_this_turn" in cm):
		cm.played_spellortrap_card_this_turn = true

	if ph and ph.has_method("update_hand_positions"):
		ph.update_hand_positions()

	animation_service._end_duel_animation_lock()

	return true

func _send_spell_to_graveyard(spell_card, who: String) -> void:
	if not is_instance_valid(spell_card):
		return

	var slot = zone_service._card_slot(spell_card)

	if not is_instance_valid(slot) and spell_card.has_meta("equip_origin_slot"):
		slot = spell_card.get_meta("equip_origin_slot")

	if is_instance_valid(slot):
		slot.set("card_in_slot", false)

		if "card_ref" in slot:
			slot.set("card_ref", null)

		if slot.has_meta("card_ref"):
			slot.remove_meta("card_ref")

		var slot_shape = slot.get_node_or_null("Area2D/CollisionShape2D")
		if slot_shape:
			slot_shape.disabled = false

		var slot_area := slot.get_node_or_null("Area2D") as Area2D
		if slot_area:
			slot_area.monitoring = true
			slot_area.input_pickable = true

	if spell_card.has_meta("equip_origin_slot"):
		spell_card.remove_meta("equip_origin_slot")

	var norm_who := card_runtime_service._norm_owner(who)
	var grave_entry := graveyard_service._grave_entry_from_card(spell_card)

	grave_entry["grave_owner"] = norm_who
	grave_entry["cause"] = "SEND_TO_GRAVE"
	grave_entry["was_destroyed"] = false

	if norm_who == "Player":
		bm.player_graveyard.append(grave_entry)
	else:
		bm.opponent_graveyard.append(grave_entry)

	event_service._unregister_card_with_effect_engine(spell_card)

	zone_service._clear_card_slot(spell_card)

	if spell_card.has_method("move_to_zone"):
		spell_card.move_to_zone("GRAVE")
	elif "current_zone" in spell_card:
		spell_card.current_zone = "GRAVE"

	zone_service._clean_battlefield_lists()

	if bm.ui_service != null and bm.ui_service.has_method("_refresh_card_usage_overlays"):
		bm.ui_service._refresh_card_usage_overlays()

	spell_card.queue_free()

#IA
func play_monster_from_hand_for_owner(
	card,
	owner: String,
	position: String = "FACEDOWN_ATK",
	preferred_slot: Node2D = null
) -> bool:
	if bm.duel_finished:
		return false

	if animation_service.is_duel_animating():
		return false

	if not is_instance_valid(card):
		return false

	owner = card_runtime_service._norm_owner(owner)

	if owner == "":
		return false

	if not ("current_zone" in card) or str(card.current_zone).to_upper() != "HAND":
		return false

	if str(card_runtime_service._card_kind(card)).to_upper() != "MONSTER":
		return false

	var free_slot: Node2D = preferred_slot

	if not is_instance_valid(free_slot):
		free_slot = zone_service._get_free_monster_slot_for(owner)

	if not is_instance_valid(free_slot):
		return false

	if bool(free_slot.get("card_in_slot")):
		return false

	animation_service._begin_duel_animation_lock()

	var hand_node: Node = null

	if owner == "Player":
		hand_node = get_node_or_null("../../PlayerHand")
	else:
		hand_node = get_node_or_null("../../OpponentHand")

	var current_global_position = card.global_position
	var current_rotation = card.rotation
	var current_scale = card.scale

	if hand_node and hand_node.has_method("remove_card_from_hand"):
		hand_node.remove_card_from_hand(card, false)

	card.global_position = current_global_position
	card.rotation = current_rotation
	card.scale = current_scale

	card_runtime_service._set_card_owner_side(card, owner)

	if card.has_method("apply_owner_collision_layers"):
		card.apply_owner_collision_layers()

	_apply_monster_play_position(card, position)

	card.set_meta("played_from_hand", true)

	animation_service._play_duel_sfx("summon_set" if bool(card.get("face_down")) else "summon_faceup")

	await animation_service._animate_card_to_slot_visual(card, free_slot, 0.28)

	zone_service._place_card_in_slot(card, free_slot, "PLAY", true)

	if hand_node and hand_node.has_method("update_hand_positions"):
		hand_node.update_hand_positions()

	animation_service._end_duel_animation_lock()

	return true

func _apply_monster_play_position(card, position: String) -> void:
	position = str(position).to_upper()

	match position:
		"FACEDOWN_ATK":
			card_runtime_service._set_card_face_down(card, true)

			if card.has_method("set_defense_position"):
				card.set_defense_position(false)
			elif "in_defense" in card:
				card.in_defense = false

		"FACEDOWN_DEF":
			card_runtime_service._set_card_face_down(card, true)

			if card.has_method("set_defense_position"):
				card.set_defense_position(true)
			elif "in_defense" in card:
				card.in_defense = true

		"FACEUP_DEF":
			card_runtime_service._set_card_face_down(card, false)

			if card.has_method("set_defense_position"):
				card.set_defense_position(true)
			elif "in_defense" in card:
				card.in_defense = true

		_:
			card_runtime_service._set_card_face_down(card, false)

			if card.has_method("set_defense_position"):
				card.set_defense_position(false)
			elif "in_defense" in card:
				card.in_defense = false
