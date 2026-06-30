extends Node
class_name DuelCardActivationService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null
var field_spell_service: DuelFieldSpellService = null
var reveal_service: DuelRevealService = null
var card_play_service: DuelCardPlayService = null
var animation_service: DuelAnimationService = null


func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service
	field_spell_service = bm.field_spell_service
	reveal_service = bm.reveal_service
	card_play_service = bm.card_play_service
	animation_service = bm.animation_service
	

func _has_immediate_effect(card) -> bool:
	if not is_instance_valid(card):
		return false
	var fx = card.get("effects")
	if typeof(fx) != TYPE_ARRAY:
		return false
	for e in fx:
		if e is Dictionary:
			var trig := str(e.get("trigger", "")).to_upper()
			if trig == "ON_PLAY":
				return true
			if str(e.get("type", "")) == "on_play":
				return true
	return false

func start_spell_activation(spell_card, who: String) -> void:
	if not is_instance_valid(spell_card):
		return

	var sub := str(spell_card.race).to_upper()
	if sub == "FIELD":
		var ctx := {
			"battle_manager": bm,
			"source": spell_card,
			"controller": who,
			"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
			"turn_index": bm.turn_index
		}
		field_spell_service._activate_field_spell(spell_card, who, ctx)
		return

	var spell_is_facedown := false
	if "face_down" in spell_card:
		spell_is_facedown = bool(spell_card.face_down)
	elif "is_facedown" in spell_card:
		spell_is_facedown = bool(spell_card.is_facedown)
	if spell_is_facedown:
		reveal_service.reveal_card(spell_card)

	var activation_ctx := {
		"battle_manager": bm,
		"source": spell_card,
		"controller": who,
		"source_controller": who,
		"source_player": who,
		"opponent_player": ("Opponent" if who == "Player" else "Player"),
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
		"turn_index": bm.turn_index,
		"activation_type": _activation_type_for_card(spell_card),
		"negated": false,
		"prevent_resolution": false,
		"destroy_activated_card": false
	}
	bm.emit_signal("spell_activated", spell_card, who)
	if _activation_type_for_card(spell_card) == "TRAP":
		bm.emit_signal("trap_activated", spell_card, who)
	event_service._emit_activation_declaration_events(spell_card, who, activation_ctx)

	if bool(activation_ctx.get("negated", false)) or bool(activation_ctx.get("prevent_resolution", false)):
		if bool(activation_ctx.get("destroy_activated_card", false)):
			card_play_service._send_spell_to_graveyard(spell_card, who)
		return

	event_service._register_card_with_effect_engine(spell_card, who)
	animation_service._play_card_activation_sfx(spell_card, activation_ctx)
	event_service._emit_duel_event("ON_ACTIVATE", activation_ctx)
	event_service._emit_duel_event("ON_ACTIVATION_RESOLVED", activation_ctx)

	if str(spell_card.race).to_upper() == "EQUIP":
		if not bm.equip_targeting:
			print("start_spell_activation: EQUIP activado pero no entró en modo targeting.")
		return

	card_play_service._send_spell_to_graveyard(spell_card, who)

func receive_spell_target(_card) -> void:
	return

func _clear_spell_targeting() -> void:
	bm.spell_targeting = false
	bm.pending_spell = null
	bm.pending_effects = []
	bm.pending_caster = ""
	bm.pending_required_targets = 0
	bm.pending_targets = []
	$"../../EndTurnButton".disabled = false

func _activation_type_for_card(card) -> String:
	match card_runtime_service._card_kind(card):
		"TRAP":
			return "TRAP"
		"SPELL":
			return "SPELL"
		_:
			return "MONSTER_EFFECT"

func try_activate_selected_card() -> void:
	if bm.duel_finished:
		return
	if bm.is_opponent_turn:
		return

	var cm := get_node_or_null("../../CardManager")
	if cm == null:
		return

	var card = null
	if "selected_card" in cm and is_instance_valid(cm.selected_card):
		card = cm.selected_card
	elif "selected_monster" in cm and is_instance_valid(cm.selected_monster):
		card = cm.selected_monster

	if not is_instance_valid(card):
		return

	var controller := "Player"
	if "owner_side" in card:
		controller = ("Player" if str(card.owner_side).to_upper() == "PLAYER" else "Opponent")
	if controller != "Player":
		return

	var effs = card.get("effects")
	if typeof(effs) != TYPE_ARRAY:
		return
	var ok := false
	for e in effs:
		if e is Dictionary and str(e.get("trigger","")).to_upper() == "ON_ACTIVATE":
			ok = true
			break
	if not ok:
		return

	var ctx := {
		"battle_manager": bm,
		"source": card,
		"controller": controller,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
		"prevent_activate": false,
		"activation_negated": false
	}

	event_service._emit_duel_event("ON_ACTIVATE", ctx)

func try_activate_from_hand(card) -> void:
	if animation_service.is_duel_animating():
		return
	if bm.duel_finished:
		return
	if bm.is_opponent_turn:
		return
	if not is_instance_valid(card):
		return

	var controller := card_runtime_service._norm_owner(zone_service._owner_of(card))
	if controller != "Player":
		return

	if not ("current_zone" in card) or str(card.current_zone).to_upper() != "HAND":
		return

	if str(card.kind).to_upper() != "SPELL":
		return

	var cm := get_node_or_null("../../CardManager")
	if cm != null and ("played_spellortrap_card_this_turn" in cm) and bool(cm.played_spellortrap_card_this_turn):
		return

	var spell_subtype := str(card.race).to_upper()
	if spell_subtype == "CONTINUOUS":
		return

	if spell_subtype == "FIELD":
		var act_ctx := {
			"battle_manager": bm,
			"source": card,
			"controller": controller,
			"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
			"turn_index": bm.turn_index,
			"from_hand": true
		}

		if cm != null and ("played_spellortrap_card_this_turn" in cm):
			cm.played_spellortrap_card_this_turn = true

		field_spell_service._activate_field_spell(card, controller, act_ctx)
		return

	if not card.has_method("get_effects"):
		return
	var effs: Array = card.get_effects()
	var has_activate := false
	for e in effs:
		if e is Dictionary and str(e.get("trigger","")).to_upper() == "ON_ACTIVATE":
			has_activate = true
			break
	if not has_activate:
		return

	if field_spell_service._is_field_spell(card):
		var act_ctx := {
			"battle_manager": bm,
			"source": card,
			"controller": controller,
			"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
			"turn_index": bm.turn_index
		}
		field_spell_service._activate_field_spell(card, controller, act_ctx)
		return

	var act_ctx := {
		"battle_manager": bm,
		"source": card,
		"controller": controller,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
		"turn_index": bm.turn_index,
		"prevent_activate": false,
		"activation_negated": false
	}
	animation_service._play_card_activation_sfx(card, act_ctx)
	event_service._emit_duel_event("ON_ACTIVATE", act_ctx)

	if bool(act_ctx.get("prevent_activate", false)) or bool(act_ctx.get("activation_negated", false)):
		return

	event_service._emit_duel_event("ON_ACTIVATION_RESOLVED", act_ctx)

	if cm != null and ("played_spellortrap_card_this_turn" in cm):
		cm.played_spellortrap_card_this_turn = true

	if spell_subtype == "EQUIP":
		if not bm.equip_targeting:
			print("activate_from_hand: EQUIP activado pero no entró en modo targeting (revisar template).")
		return

	var ph := get_node_or_null("../../PlayerHand")
	if ph and ph.has_method("remove_card_from_hand"):
		ph.remove_card_from_hand(card)

	card_play_service._send_spell_to_graveyard(card, controller)

func try_activate_card(card) -> void:
	if animation_service.is_duel_animating():
		return
	if bm.duel_finished:
		return
	if bm.is_opponent_turn:
		return
	if not is_instance_valid(card):
		return
	if card_runtime_service._card_kind(card) == "TRAP":
		return

	var controller := card_runtime_service._norm_owner(zone_service._owner_of(card))
	if controller != "Player":
		return

	if card_runtime_service._is_card_face_down(card):
		return

	if not card.has_method("get_effects"):
		return
	var effs: Array = card.get_effects()
	var has_activate := false
	for e in effs:
		if e is Dictionary and str(e.get("trigger","")).to_upper() == "ON_ACTIVATE":
			has_activate = true
			break
	if not has_activate:
		return

	if field_spell_service._is_field_spell(card):
		var act_ctx := {
			"battle_manager": bm,
			"source": card,
			"controller": controller,
			"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
			"turn_index": bm.turn_index
		}
		field_spell_service._activate_field_spell(card, controller, act_ctx)
		return

	var act_ctx := {
		"battle_manager": bm,
		"source": card,
		"controller": controller,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
		"turn_index": bm.turn_index,
		"prevent_activate": false,
		"activation_negated": false
	}

	event_service._emit_duel_event("ON_ACTIVATE", act_ctx)

	if bool(act_ctx.get("prevent_activate", false)) or bool(act_ctx.get("activation_negated", false)):
		return

	event_service._emit_duel_event("ON_ACTIVATION_RESOLVED", act_ctx)

func _targets_required_for(effect_list: Array) -> int:
	var n := 0
	for e in effect_list:
		if e == "target_enemy_monster":
			n += 1
	return n
