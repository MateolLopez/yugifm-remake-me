extends Node
class_name DuelDamageService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null
var kw_service: DuelKeywordService = null
var reveal_service: DuelRevealService = null
var turn_service: DuelTurnService = null
var atk_state_service: DuelAttackStateService = null
var animation_service: DuelAnimationService = null
var ui_service: DuelUiService

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service
	kw_service = bm.kw_service
	reveal_service = bm.reveal_service
	turn_service = bm.turn_service
	atk_state_service = bm.atk_state_service
	animation_service = bm.animation_service
	ui_service = bm.ui_service

func direct_attack(atk_card, attacker):
	if bm.duel_finished:
		return
	if not is_instance_valid(atk_card):
		return
	if kw_service._has_kw(atk_card, "PARALYZED"):
		return
	if card_runtime_service._card_kind(atk_card) != "MONSTER":
		return

	attacker = card_runtime_service._norm_owner(attacker)

	reveal_service.reveal_card(atk_card)

	var effective_atk: int = int(atk_card.get_effective_atk() if atk_card.has_method("get_effective_atk") else atk_card.atk)

	if attacker == "Opponent":
		var new_pos_y := 1000

		atk_card.z_index = 5

		var t := get_tree().create_tween()
		t.tween_property(atk_card, "global_position", Vector2(atk_card.global_position.x, new_pos_y), bm.CARD_MOVE_SPEED)
		await turn_service.action_waiter()

		_apply_battle_damage_to_side("Player", effective_atk, atk_card, null)

		atk_state_service._register_attack_spent(atk_card, "Opponent", null)

		if bm.duel_finished:
			return

		var t2 := get_tree().create_tween()
		t2.tween_property(atk_card, "global_position", animation_service._anchored_slot_position(atk_card), bm.CARD_MOVE_SPEED)
		await turn_service.action_waiter()

		if is_instance_valid(atk_card):
			atk_card.z_index = 0

		return

	$"../../InputManager".inputs_disabled = true
	ui_service.enable_end_turn_button(false)

	atk_card.z_index = 5

	var tw := get_tree().create_tween()
	tw.tween_property(atk_card, "global_position", Vector2(atk_card.global_position.x, 0), bm.CARD_MOVE_SPEED)
	await turn_service.action_waiter()

	_apply_battle_damage_to_side("Opponent", effective_atk, atk_card, null)

	atk_state_service._register_attack_spent(atk_card, "Player", null)

	if bm.duel_finished:
		return

	var tw2 := get_tree().create_tween()
	tw2.tween_property(atk_card, "global_position", animation_service._anchored_slot_position(atk_card), bm.CARD_MOVE_SPEED)
	await turn_service.action_waiter()

	if is_instance_valid(atk_card):
		atk_card.z_index = 0

	$"../../InputManager".inputs_disabled = false
	ui_service.enable_end_turn_button(true)

func _apply_battle_damage_to_side(target_owner: String, amount: int, source_card = null, defender_card = null) -> void:
	if amount <= 0:
		return

	target_owner = card_runtime_service._norm_owner(target_owner)

	if target_owner == "Player":
		bm.player_hp = max(0, bm.player_hp - amount)
		$"../../PlayerHP".text = str(bm.player_hp)
	elif target_owner == "Opponent":
		bm.opponent_hp = max(0, bm.opponent_hp - amount)
		$"../../OpponentHP".text = str(bm.opponent_hp)
	else:
		return

	event_service._emit_duel_event("ON_INFLICT_BATTLE_DAMAGE", {
		"battle_manager": bm,
		"source": source_card,
		"defender": defender_card,
		"target_player": target_owner,
		"amount": amount,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
		"turn_index": bm.turn_index
	})

	_apply_lifesteal_from_battle_damage_source(source_card, amount)

	_check_end_duel()

func _apply_effect_damage_to_side(target_owner: String, amount: int, ctx: Dictionary = {}) -> void:
	if amount <= 0:
		return
	if target_owner == "Player":
		bm.player_hp = max(0, bm.player_hp - amount)
		$"../../PlayerHP".text = str(bm.player_hp)
	elif target_owner == "Opponent":
		bm.opponent_hp = max(0, bm.opponent_hp - amount)
		$"../../OpponentHP".text = str(bm.opponent_hp)
	else:
		return
	event_service._emit_duel_event("ON_INFLICT_EFFECT_DAMAGE", {"battle_manager": bm, "source": ctx.get("source", null), "target_player": target_owner, "amount": amount, "turn_owner": ("Opponent" if bm.is_opponent_turn else "Player")})
	_check_end_duel()

func recover_lp_to_side(target_owner: String, amount: int, ctx: Dictionary = {}) -> void:
	if amount <= 0:
		return

	target_owner = card_runtime_service._norm_owner(target_owner)

	if target_owner == "Player":
		bm.player_hp += amount
		$"../../PlayerHP".text = str(bm.player_hp)
	elif target_owner == "Opponent":
		bm.opponent_hp += amount
		$"../../OpponentHP".text = str(bm.opponent_hp)
	else:
		return

	event_service._emit_duel_event("ON_RECOVER_LP", {
		"battle_manager": bm,
		"source": ctx.get("source", null),
		"target_player": target_owner,
		"amount": amount,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player")
	})

func _check_end_duel() -> bool:
	if bm.duel_finished:
		return true
	if bm.player_hp <= 0 and bm.opponent_hp <= 0:
		bm.duel_finished = true
		bm.emit_signal("duel_over", "draw")
	elif bm.player_hp <= 0:
		bm.duel_finished = true
		bm.emit_signal("duel_over","player_defeat")
	elif bm.opponent_hp <= 0:
		bm.duel_finished = true
		bm.emit_signal("duel_over","player_victory")
	return bm.duel_finished

func _apply_lifesteal_from_battle_damage_source(source_card, amount: int) -> void:
	if amount <= 0:
		return

	if not is_instance_valid(source_card):
		return

	if not _damage_source_has_lifesteal(source_card):
		return

	var source_owner := _owner_of_damage_source(source_card)

	if source_owner == "":
		return

	_recover_lp_from_lifesteal(source_owner, amount, source_card)

func _damage_source_has_lifesteal(card: Node) -> bool:
	if not is_instance_valid(card):
		return false

	if bm != null and bm.kw_service != null and bm.kw_service.has_method("_has_kw"):
		return bool(bm.kw_service._has_kw(card, "LIFESTEAL"))

	if card.has_method("equip_has_keyword"):
		if bool(card.call("equip_has_keyword", "LIFESTEAL")):
			return true

	if card.has_method("has_keyword"):
		if bool(card.call("has_keyword", "LIFESTEAL")):
			return true

	if "keywords" in card and typeof(card.keywords) == TYPE_ARRAY:
		for k in card.keywords:
			if str(k).to_upper() == "LIFESTEAL":
				return true

	if card.has_meta("runtime_keywords"):
		var runtime_keywords: Array = card.get_meta("runtime_keywords")
		for k in runtime_keywords:
			if str(k).to_upper() == "LIFESTEAL":
				return true

	return false


func _owner_of_damage_source(card: Node) -> String:
	if not is_instance_valid(card):
		return ""

	if bm != null and bm.zone_service != null and bm.zone_service.has_method("_owner_of"):
		var zone_owner := card_runtime_service._norm_owner(bm.zone_service._owner_of(card))

		if zone_owner != "":
			return zone_owner

	if "owner_side" in card:
		return card_runtime_service._norm_owner(card.owner_side)

	if card.has_meta("owner_side"):
		return card_runtime_service._norm_owner(card.get_meta("owner_side"))

	if card.has_meta("controller"):
		return card_runtime_service._norm_owner(card.get_meta("controller"))

	return ""


func _recover_lp_from_lifesteal(owner: String, amount: int, source_card: Node) -> void:
	owner = card_runtime_service._norm_owner(owner)

	if owner == "":
		return

	if has_method("recover_lp_to_side"):
		recover_lp_to_side(owner, amount, {
			"source": source_card,
			"controller": owner,
			"reason": "LIFESTEAL",
			"amount": amount,
			"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
			"turn_index": bm.turn_index
		})
		return

	if owner == "Player":
		bm.player_hp += amount
		$"../../PlayerHP".text = str(bm.player_hp)
	elif owner == "Opponent":
		bm.opponent_hp += amount
		$"../../OpponentHP".text = str(bm.opponent_hp)
