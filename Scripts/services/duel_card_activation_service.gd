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

func _hand_node_for_owner(owner: String) -> Node:
	owner = card_runtime_service._norm_owner(owner)

	if owner == "Player":
		return get_node_or_null("../../PlayerHand")

	if owner == "Opponent":
		return get_node_or_null("../../OpponentHand")

	return null


func _remove_card_from_owner_hand(card: Node, owner: String) -> void:
	var hand := _hand_node_for_owner(owner)

	if hand == null:
		return

	if hand.has_method("remove_card_from_hand"):
		hand.remove_card_from_hand(card)
		return

	# Fallback por si OpponentHand usa array directo.
	if owner == "Opponent" and "opponent_hand" in hand:
		var arr: Array = hand.opponent_hand
		while card in arr:
			arr.erase(card)

	if owner == "Player" and "player_hand" in hand:
		var arr2: Array = hand.player_hand
		while card in arr2:
			arr2.erase(card)


func _mark_spelltrap_played_for_owner(owner: String) -> void:
	owner = card_runtime_service._norm_owner(owner)

	if owner == "Player":
		var cm := get_node_or_null("../../CardManager")
		if cm != null and ("played_spellortrap_card_this_turn" in cm):
			cm.played_spellortrap_card_this_turn = true
		return

	if owner == "Opponent":
		var ia := get_node_or_null("../../OpponentIA")
		if ia != null and ("played_spellortrap_card_this_turn" in ia):
			ia.played_spellortrap_card_this_turn = true
		return


func _spelltrap_played_this_turn_for_owner(owner: String) -> bool:
	owner = card_runtime_service._norm_owner(owner)

	if owner == "Player":
		var cm := get_node_or_null("../../CardManager")
		if cm != null and ("played_spellortrap_card_this_turn" in cm):
			return bool(cm.played_spellortrap_card_this_turn)
		return false

	if owner == "Opponent":
		var ia := get_node_or_null("../../OpponentIA")
		if ia != null and ("played_spellortrap_card_this_turn" in ia):
			return bool(ia.played_spellortrap_card_this_turn)
		return false

	return false

func try_activate_from_hand(card) -> bool:
	return await try_activate_from_hand_for_owner(card, "Player")


func try_activate_from_hand_for_owner(card: Node, owner: String) -> bool:
	owner = card_runtime_service._norm_owner(owner)

	if owner == "":
		return false

	if animation_service.is_duel_animating():
		return false

	if bm.duel_finished:
		return false

	if owner == "Player" and bm.is_opponent_turn:
		return false

	if owner == "Opponent" and not bm.is_opponent_turn:
		return false

	if not is_instance_valid(card):
		return false

	if not ("current_zone" in card) or str(card.current_zone).to_upper() != "HAND":
		return false

	if str(card_runtime_service._card_kind(card)).to_upper() != "SPELL":
		return false

	if _spelltrap_played_this_turn_for_owner(owner):
		return false

	var spell_subtype := str(card.race).to_upper()

	# De momento mantenemos tu regla actual:
	# Continuous no se activa directamente desde mano.
	if spell_subtype == "CONTINUOUS":
		return false

	# Field Spell desde mano.
	if spell_subtype == "FIELD" or field_spell_service._is_field_spell(card):
		var act_ctx := {
			"battle_manager": bm,
			"source": card,
			"controller": owner,
			"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
			"turn_index": bm.turn_index,
			"from_hand": true
		}

		_mark_spelltrap_played_for_owner(owner)
		_remove_card_from_owner_hand(card, owner)

		field_spell_service._activate_field_spell(card, owner, act_ctx)
		return true

	if not card.has_method("get_effects"):
		return false

	var effs: Array = card.get_effects()
	var has_activate := false

	for e in effs:
		if e is Dictionary and str(e.get("trigger", "")).to_upper() == "ON_ACTIVATE":
			has_activate = true
			break

	if not has_activate:
		return false

	var act_ctx := {
		"battle_manager": bm,
		"source": card,
		"controller": owner,
		"source_controller": owner,
		"source_player": owner,
		"opponent_player": ("Opponent" if owner == "Player" else "Player"),
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
		"turn_index": bm.turn_index,
		"prevent_activate": false,
		"activation_negated": false
	}

	animation_service._play_card_activation_sfx(card, act_ctx)
	event_service._emit_duel_event("ON_ACTIVATE", act_ctx)

	if bool(act_ctx.get("prevent_activate", false)) or bool(act_ctx.get("activation_negated", false)):
		return false

	event_service._emit_duel_event("ON_ACTIVATION_RESOLVED", act_ctx)

	_mark_spelltrap_played_for_owner(owner)

	if spell_subtype == "EQUIP":
		if not bm.equip_targeting:
			print("activate_from_hand_for_owner: EQUIP activado pero no entró en modo targeting.")
		return true

	_remove_card_from_owner_hand(card, owner)
	card_play_service._send_spell_to_graveyard(card, owner)

	return true

func try_activate_card(card) -> bool:
	return try_activate_card_for_owner(card, "Player")


func try_activate_card_for_owner(card: Node, owner: String) -> bool:
	owner = card_runtime_service._norm_owner(owner)

	if owner == "":
		return false

	if animation_service.is_duel_animating():
		return false

	if bm.duel_finished:
		return false

	if owner == "Player" and bm.is_opponent_turn:
		return false

	if owner == "Opponent" and not bm.is_opponent_turn:
		return false

	if not is_instance_valid(card):
		return false

	if card_runtime_service._card_kind(card) == "TRAP":
		return false

	var controller := ""

	if "owner_side" in card:
		var side := str(card.owner_side).to_upper()

		if side == "PLAYER":
			controller = "Player"
		elif side == "OPPONENT":
			controller = "Opponent"

	if controller == "":
		controller = card_runtime_service._norm_owner(zone_service._owner_of(card))

	if controller != owner:
		return false

	if card_runtime_service._is_card_face_down(card):
		return false

	if not card.has_method("get_effects"):
		return false

	var effs: Array = card.get_effects()
	var has_activate := false

	for e in effs:
		if e is Dictionary and str(e.get("trigger", "")).to_upper() == "ON_ACTIVATE":
			has_activate = true
			break

	if not has_activate:
		return false

	if field_spell_service._is_field_spell(card):
		var field_ctx := {
			"battle_manager": bm,
			"source": card,
			"controller": owner,
			"source_controller": owner,
			"source_player": owner,
			"opponent_player": ("Opponent" if owner == "Player" else "Player"),
			"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
			"turn_index": bm.turn_index
		}

		field_spell_service._activate_field_spell(card, owner, field_ctx)
		return true

	var act_ctx := {
		"battle_manager": bm,
		"source": card,
		"controller": owner,
		"source_controller": owner,
		"source_player": owner,
		"opponent_player": ("Opponent" if owner == "Player" else "Player"),
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
		"turn_index": bm.turn_index,
		"prevent_activate": false,
		"activation_negated": false
	}

	event_service._emit_duel_event("ON_ACTIVATE", act_ctx)

	if bool(act_ctx.get("prevent_activate", false)) or bool(act_ctx.get("activation_negated", false)):
		return false

	event_service._emit_duel_event("ON_ACTIVATION_RESOLVED", act_ctx)

	return true

func _targets_required_for(effect_list: Array) -> int:
	var n := 0
	for e in effect_list:
		if e == "target_enemy_monster":
			n += 1
	return n
