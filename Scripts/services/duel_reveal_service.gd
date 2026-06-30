extends Node
class_name DuelRevealService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service

func reveal_card(card: Node):
	if not is_instance_valid(card):
		return
	if not card_runtime_service._is_card_face_down(card):
		return

	card_runtime_service._set_card_face_down(card, false)

	var controller := card_runtime_service._norm_owner(zone_service._owner_of(card))
	event_service._emit_duel_event("ON_FLIP", {
		"battle_manager": bm,
		"source": card,
		"controller": controller,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
		"turn_index": bm.turn_index
	})

	if card.has_method("ensure_guardian_initialized"):
		card.ensure_guardian_initialized()
	if card.has_method("_update_guardian_star_label"):
		card._update_guardian_star_label()

func reveal_all_set_monsters_for_side(side: String) -> void:
	var norm_side := card_runtime_service._norm_owner(side)
	var cards: Array = bm.player_cards_on_battlefield if norm_side == "Player" else bm.opponent_cards_on_battlefield
	for c in cards:
		if not is_instance_valid(c):
			continue
		if card_runtime_service._card_kind(c) != "MONSTER":
			continue
		if card_runtime_service._is_card_face_down(c):
			reveal_card(c)

func reveal_hidden_cards_by_effect(source: Node, ctx: Dictionary, params: Dictionary) -> void:
	print("ENTER reveal_hidden_cards_by_effect source=", source.cardname if is_instance_valid(source) and ("cardname" in source) else "<null>", " params=", params)

	var controller := card_runtime_service._norm_owner(ctx.get("controller", ""))
	var target_side := str(params.get("target_side", "OPPONENT")).to_upper()
	var source_zone := str(params.get("source_zone", "SET_SPELL_TRAP")).to_upper()
	var choose := str(params.get("choose", "ALL")).to_upper()
	var count := int(params.get("count", 0))
	var reveal_to := str(params.get("reveal_to", "PLAYER_ONLY")).to_upper()
	var require_ack := bool(params.get("require_ack", true))

	print("REVEAL controller=", controller, " target_side=", target_side, " source_zone=", source_zone, " choose=", choose, " count=", count, " reveal_to=", reveal_to, " require_ack=", require_ack)

	var target_sides: Array[String] = []

	if target_side == "SELF":
		target_sides = ["PLAYER" if controller == "Player" else "OPPONENT"]
	elif target_side == "OPPONENT":
		target_sides = ["OPPONENT" if controller == "Player" else "PLAYER"]
	elif target_side == "BOTH":
		target_sides = ["PLAYER", "OPPONENT"]
	else:
		target_sides = ["OPPONENT" if controller == "Player" else "PLAYER"]

	var candidates: Array = []

	for side in target_sides:
		if source_zone == "SET_SPELL_TRAP":
			var slots_root = $"../../CardSlots" if side == "PLAYER" else $"../../CardSlotsRival"
			print("REVEAL checking slots_root=", slots_root)

			if not is_instance_valid(slots_root):
				continue

			for s in slots_root.get_children():
				if not is_instance_valid(s):
					continue

				var slot_type := str(s.get("card_slot_type"))
				print("  SLOT name=", s.name, " type=", slot_type, " in_slot=", bool(s.get("card_in_slot")))

				if slot_type != "SpellTrap" and slot_type != "Spell" and slot_type != "Trap":
					continue

				if not bool(s.get("card_in_slot")):
					continue

				var c = s.get_meta("card_ref")
				if not is_instance_valid(c):
					print("    SLOT OCCUPIED BUT card_ref invalid")
					continue

				print("    CARD REF=", c.cardname if ("cardname" in c) else "<null>", " face_down=", card_runtime_service._is_card_face_down(c))

				if not card_runtime_service._is_card_face_down(c):
					continue

				candidates.append(c)

	print("REVEAL candidates final=", candidates.size())

	if candidates.is_empty():
		return

	var selected: Array = []

	if choose == "ALL" or count == 0:
		selected = candidates
	elif choose == "RANDOM":
		candidates.shuffle()
		for i in range(min(max(1, count), candidates.size())):
			selected.append(candidates[i])
	else:
		selected = candidates

	print("REVEAL selected=", selected.map(func(x): return x.cardname if ("cardname" in x) else str(x)))

	_begin_temporary_reveal(selected, source_zone, reveal_to, require_ack, controller)

func _begin_temporary_reveal(cards: Array, source_zone: String, reveal_to: String, require_ack: bool, controller: String) -> void:
	print("BEGIN TEMP REVEAL cards=", cards.map(func(x): return x.cardname if ("cardname" in x) else str(x)), " source_zone=", source_zone, " controller=", controller)

	if cards.is_empty():
		return

	bm.reveal_overlay_active = true
	bm.reveal_overlay_cards = []
	bm.reveal_overlay_original_states = []
	bm.reveal_overlay_waiting_ack = false

	for c in cards:
		if not is_instance_valid(c):
			continue

		var saved := {
			"card": c,
			"face_down": (card_runtime_service._is_card_face_down(c)),
			"show_back_only": (bool(c.show_back_only) if "show_back_only" in c else false),
			"z_index": (int(c.z_index) if "z_index" in c else 0)
		}
		bm.reveal_overlay_original_states.append(saved)
		bm.reveal_overlay_cards.append(c)

		card_runtime_service._set_card_face_down(c, false)
		if c.has_method("set_show_back_only"):
			c.set_show_back_only(false)
		if c.has_method("_update_visuals"):
			c._update_visuals()

		c.z_index = 50

	var is_player_review := (controller == "Player")
	print("BEGIN TEMP REVEAL is_player_review=", is_player_review, " require_ack=", require_ack)

	if require_ack and is_player_review:
		bm.reveal_overlay_waiting_ack = true
		_show_reveal_ack_popup()
	else:
		_finish_temporary_reveal()

func _finish_temporary_reveal() -> void:
	for item in bm.reveal_overlay_original_states:
		var c = item.get("card", null)
		if not is_instance_valid(c):
			continue

		if "face_down" in item:
			card_runtime_service._set_card_face_down(c, bool(item["face_down"]))

		if c.has_method("set_show_back_only") and item.has("show_back_only"):
			c.set_show_back_only(bool(item["show_back_only"]))

		if item.has("z_index"):
			c.z_index = int(item["z_index"])

		if c.has_method("_update_visuals"):
			c._update_visuals()

	bm.reveal_overlay_cards.clear()
	bm.reveal_overlay_original_states.clear()
	bm.reveal_overlay_active = false
	bm.reveal_overlay_waiting_ack = false

func _show_reveal_ack_popup() -> void:
	var panel = get_node_or_null("../../RevealAckPanel")
	print("SHOW REVEAL POPUP panel=", panel)
	if panel:
		panel.visible = true

func _on_reveal_ack_accept_pressed() -> void:
	var panel = get_node_or_null("../../RevealAckPanel")
	if panel:
		panel.visible = false
	_finish_temporary_reveal()
