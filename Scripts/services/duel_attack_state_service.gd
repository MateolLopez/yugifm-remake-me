extends Node
class_name DuelAttackStateService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null
var kw_service: DuelKeywordService = null
var combat_service: DuelCombatService = null
var ui_service: DuelUiService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service
	kw_service = bm.kw_service
	combat_service = bm.combat_service
	ui_service = bm.ui_service

func _clear_multi_for(card):
	bm.multi_mode.erase(card)
	bm.multi_remaining.erase(card)
	bm.multi_already_attacked.erase(card)

func _cleanup_multi_garbage():
	for k in bm.multi_mode.keys():
		if not is_instance_valid(k) or (k not in bm.player_cards_on_battlefield and k not in bm.opponent_cards_on_battlefield):
			_clear_multi_for(k)

func _attack_key(card: Node) -> String:
	if not is_instance_valid(card):
		return ""
	return str(card.get_instance_id())

func _get_attack_count(card: Node) -> int:
	var key := _attack_key(card)
	if key == "":
		return 0
	return int(bm.attack_count_this_turn.get(key, 0))

func _max_attacks_for_card(card: Node) -> int:
	if not is_instance_valid(card):
		return 1

	if card.has_method("get_max_attacks_per_turn"):
		return max(1, int(card.get_max_attacks_per_turn()))

	var max_attacks := 1

	if kw_service._has_kw(card, "MULTI_ATTACK_2"):
		max_attacks = max(max_attacks, 2)

	if card.has_meta("extra_attacks_this_turn"):
		max_attacks += max(0, int(card.get_meta("extra_attacks_this_turn")))

	return max_attacks

func _is_card_attack_exhausted(card: Node, attacker_owner: String) -> bool:
	if not is_instance_valid(card):
		return true

	attacker_owner = card_runtime_service._norm_owner(attacker_owner)

	# MULTI_ATTACK_ALL no se agota por cantidad fija,
	# sino cuando ya atacó a todos los monstruos enemigos disponibles. posible cambio lpm
	if kw_service._has_kw(card, "MULTI_ATTACK_ALL"):
		var defenders = combat_service._live_defenders_for(attacker_owner)

		# Si no quedan defensores, cualquier ataque directo consume/termina la posibilidad.
		if defenders.is_empty():
			return _get_attack_count(card) > 0

		var a_id := _attack_key(card)
		var per_attacker = bm.multi_attack_targets_this_turn.get(a_id, {})
		if typeof(per_attacker) != TYPE_DICTIONARY:
			return false

		for d in defenders:
			if not is_instance_valid(d):
				continue

			var d_id := str(d.get_instance_id())
			if not bool(per_attacker.get(d_id, false)):
				return false

		return true

	return _get_attack_count(card) >= _max_attacks_for_card(card)

func _can_card_declare_attack_against(card: Node, defending: Node, attacker_owner: String) -> bool:
	if not is_instance_valid(card):
		return false

	attacker_owner = card_runtime_service._norm_owner(attacker_owner)

	if _is_card_attack_exhausted(card, attacker_owner):
		return false

	if kw_service._has_kw(card, "MULTI_ATTACK_ALL") and is_instance_valid(defending):
		var a_id := _attack_key(card)
		var d_id := str(defending.get_instance_id())

		var per_attacker = bm.multi_attack_targets_this_turn.get(a_id, {})
		if typeof(per_attacker) != TYPE_DICTIONARY:
			per_attacker = {}

		if bool(per_attacker.get(d_id, false)):
			return false

	return true

func _register_attack_spent(card: Node, attacker_owner: String, defending: Node = null) -> void:
	if not is_instance_valid(card):
		return

	attacker_owner = card_runtime_service._norm_owner(attacker_owner)

	var key := _attack_key(card)
	if key == "":
		return

	bm.attack_count_this_turn[key] = int(bm.attack_count_this_turn.get(key, 0)) + 1

	if kw_service._has_kw(card, "MULTI_ATTACK_ALL") and is_instance_valid(defending):
		var d_id := str(defending.get_instance_id())

		var per_attacker = bm.multi_attack_targets_this_turn.get(key, {})
		if typeof(per_attacker) != TYPE_DICTIONARY:
			per_attacker = {}

		per_attacker[d_id] = true
		bm.multi_attack_targets_this_turn[key] = per_attacker

	var exhausted := _is_card_attack_exhausted(card, attacker_owner)

	if exhausted:
		var used_list: Array = bm.player_cards_that_attacked_this_turn if attacker_owner == "Player" else bm.opponent_cards_that_attacked_this_turn

		if not used_list.has(card):
			used_list.append(card)

		if attacker_owner == "Player":
			bm.player_cards_that_attacked_this_turn = used_list
		else:
			bm.opponent_cards_that_attacked_this_turn = used_list

	ui_service._refresh_card_usage_overlays()

func _attacker_suppresses_traps(attacker_card: Node) -> bool:
	if not is_instance_valid(attacker_card):
		return false

	var eng = event_service._get_effect_engine()
	if eng == null or not eng.has_method("is_effect_application_blocked"):
		return false

	var effect_ctx := {
		"source": attacker_card,
		"activation_type": "TRAP"
	}

	return bool(eng.is_effect_application_blocked(attacker_card, effect_ctx, "AFFECT"))
