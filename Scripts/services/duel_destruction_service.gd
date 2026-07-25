extends Node
class_name DuelDestructionService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null
var graveyard_service: DuelGraveyardService = null
var field_spell_service: DuelFieldSpellService = null
var atk_state_service: DuelAttackStateService = null
var ui_service: DuelUiService = null
var animation_service: DuelAnimationService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service
	graveyard_service = bm.graveyard_service
	field_spell_service = bm.field_spell_service
	atk_state_service = bm.atk_state_service
	ui_service = bm.ui_service
	animation_service = bm.animation_service

func destroy_card(card, card_owner, cause := "DESTROY_EFFECT", effect_ctx: Dictionary = {}) -> bool:
	if not is_instance_valid(card):
		return false

	var eng = event_service._get_effect_engine()
	if not effect_ctx.is_empty() and eng and eng.has_method("is_effect_application_blocked"):
		if eng.is_effect_application_blocked(card, effect_ctx, "DESTROY"):
			return false

	event_service._unregister_card_with_effect_engine(card)
	card_owner = card_runtime_service._norm_owner(card_owner)

	var destroy_ctx := {
		"battle_manager": bm,
		"source": card,
		"controller": card_owner,
		"cause": cause,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player")
	}

	if cause == "DESTROY_BATTLE":
		event_service._emit_duel_event("ON_DESTROY_BATTLE", destroy_ctx)
	elif cause == "DESTROY_EFFECT":
		event_service._emit_duel_event("ON_DESTROY_EFFECT", destroy_ctx)

	event_service._emit_duel_event("ON_DESTROY", destroy_ctx)
	event_service._emit_duel_event("ON_LEAVE_FIELD", destroy_ctx)
	event_service._emit_duel_event("ON_SEND_TO_GRAVE", destroy_ctx)

	if cause == "DESTROY_EFFECT":
		event_service._emit_duel_event("ON_SEND_TO_GRAVE_BY_EFFECT", destroy_ctx)

	var slot = zone_service._card_slot(card)
	var grave_entry := graveyard_service._grave_entry_from_card(card)
	grave_entry["grave_owner"] = card_owner
	grave_entry["sent_order"] = graveyard_service._next_graveyard_order()
	grave_entry["cause"] = cause
	grave_entry["was_destroyed"] = str(cause).begins_with("DESTROY")
	var skip_destroy_animation := bool(
		effect_ctx.get("skip_destroy_animation", false)
	)

	if not skip_destroy_animation:
		var presentation = effect_ctx.get("presentation", {})

		if typeof(presentation) == TYPE_DICTIONARY:
			var pre_destroy_vfx_key := str(
				presentation.get("pre_destroy_vfx_key", "")
			)

			var pre_destroy_sfx_key := str(
				presentation.get("pre_destroy_sfx_key", "")
			)

			if pre_destroy_vfx_key != "":
				card.set_meta(
					"pre_destroy_vfx_key",
					pre_destroy_vfx_key
				)

			if pre_destroy_sfx_key != "":
				card.set_meta(
					"pre_destroy_sfx_key",
					pre_destroy_sfx_key
				)

	if card_owner == "Player":
		card.defeated = true

		var cshape = card.get_node_or_null("Area2D/CollisionShape2D")
		if cshape:
			cshape.disabled = true

		if card in bm.player_cards_on_battlefield:
			bm.player_graveyard.append(grave_entry)
			bm.player_cards_on_battlefield.erase(card)

			if slot:
				var slot_shape = slot.get_node_or_null("Area2D/CollisionShape2D")
				if slot_shape:
					slot_shape.disabled = false
	else:
		var cshape_opp = card.get_node_or_null("Area2D/CollisionShape2D")
		if cshape_opp:
			cshape_opp.disabled = true

		if card in bm.opponent_cards_on_battlefield:
			bm.opponent_graveyard.append(grave_entry)
			bm.opponent_cards_on_battlefield.erase(card)

	if slot:
		slot.set("card_in_slot", false)
		slot.set_meta("card_ref", null)

		if slot.get_parent() == $"../../CardSlotsRival":
			if not bm.empty_monster_card_slots.has(slot):
				bm.empty_monster_card_slots.append(slot)

	if card == bm.active_field_spell:
		bm.active_field_spell = null
		bm.active_field_spell_controller = ""
		field_spell_service._update_field_spell_name_ui()

	atk_state_service._clear_multi_for(card)
	zone_service._clear_card_slot(card)

	zone_service._clean_battlefield_lists()
	event_service._refresh_effect_engine_continuous_buffs()
	ui_service._refresh_card_usage_overlays()

	if skip_destroy_animation:
		if card is CanvasItem:
			(card as CanvasItem).visible = false

		animation_service.request_free_after_effect_resolutions(card)

	elif card is Node2D:
		animation_service._play_card_destroy_animation_and_free(
			card
		)

	else:
		card.queue_free()

	return true

func destroy_card_tie(
	card_a,
	card_b,
	effect_ctx: Dictionary = {}
) -> void:
	if is_instance_valid(card_a):
		var cardowner_a := zone_service._owner_of(card_a)

		if cardowner_a != "":
			destroy_card(
				card_a,
				cardowner_a,
				"DESTROY_BATTLE",
				effect_ctx
			)

	if is_instance_valid(card_b):
		var cardowner_b := zone_service._owner_of(card_b)

		if cardowner_b != "":
			destroy_card(
				card_b,
				cardowner_b,
				"DESTROY_BATTLE",
				effect_ctx
			)

	atk_state_service._clear_multi_for(card_a)
	atk_state_service._clear_multi_for(card_b)

func _process_scheduled_destruction_on_turn_end(turn_owner: String) -> void:
	var all_cards: Array = []
	all_cards.append_array(bm.player_cards_on_battlefield)
	all_cards.append_array(bm.opponent_cards_on_battlefield)
	for c in all_cards:
		if not is_instance_valid(c):
			continue
		if not c.has_meta("scheduled_destruction"):
			continue
		var sd = c.get_meta("scheduled_destruction")
		var should_destroy := false
		if sd is bool:
			should_destroy = bool(sd)
		elif sd is Dictionary:
			var due := str(sd.get("due_turn_end_owner", ""))
			should_destroy = (due == "" or due == turn_owner)
		if not should_destroy:
			continue
		c.remove_meta("scheduled_destruction")
		var cardowner := zone_service._owner_of(c)
		if cardowner != "":
			destroy_card(c, cardowner)
