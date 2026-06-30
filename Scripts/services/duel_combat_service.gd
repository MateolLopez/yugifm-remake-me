extends Node
class_name DuelCombatService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null
var kw_service: DuelKeywordService = null
var ui_service: DuelUiService = null
var reveal_service: DuelRevealService = null
var atk_state_service: DuelAttackStateService = null
var stat_service: DuelStatService = null
var damage_service: DuelDamageService = null
var turn_service: DuelTurnService = null
var animation_service: DuelAnimationService = null
var destruction_service: DuelDestructionService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service
	kw_service = bm.kw_service
	ui_service = bm.ui_service
	reveal_service = bm.reveal_service
	atk_state_service = bm.atk_state_service
	stat_service = bm.stat_service
	damage_service = bm.damage_service
	turn_service = bm.turn_service
	animation_service = bm.animation_service
	destruction_service = bm.destruction_service

func can_attack_directly(attacker_card):
	if not is_instance_valid(attacker_card):
		return
	if attacker_card.has_meta("only_direct_attack") and attacker_card.get_meta("only_direct_attack"):
		return true
	if attacker_card.has_meta("can_direct_attack") and attacker_card.get_meta("can_direct_attack"):
		return true
			
	var defenders = _live_defenders_for("Player" if zone_service._owner_of(attacker_card) == "Opponent" else "Opponent")
	return defenders.size() == 0

func attack(atk_card, defending, attacker):
	if card_runtime_service._card_kind(atk_card) != "MONSTER":
		return
	if bm.duel_finished:
		return
	if not is_instance_valid(atk_card):
		return
	if kw_service._has_kw(atk_card, "PARALYZED"):
		if attacker == "Player":
			$"../../InputManager".inputs_disabled = false
			ui_service.enable_end_turn_button(true)
		return

	if card_runtime_service._is_card_face_down(atk_card):
		reveal_service.reveal_card(atk_card)

	if not atk_state_service._can_card_declare_attack_against(atk_card, defending, attacker):
		_release_player_input_if_needed(attacker)
		return

	var battle_ctx := {
		"battle_manager": bm,
		"source": atk_card,
		"attacker": atk_card,
		"defender": defending,
		"attacker_owner": attacker,
		"controller": attacker,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
		"prevent_attack": false,
		"attack_negated": false,
		"suppress_trap_reactions": atk_state_service._attacker_suppresses_traps(atk_card)
	}
	bm.emit_signal("attack_declared", atk_card, defending, attacker)
	event_service._emit_duel_event("ON_ATTACK_DECLARATION", battle_ctx)

	if bool(battle_ctx.get("prevent_attack", false)) or bool(battle_ctx.get("attack_negated", false)):
		_release_player_input_if_needed(attacker)
		return

	if atk_card.has_meta("only_direct_attack") and atk_card.get_meta("only_direct_attack"):
		if is_instance_valid(defending):
			_release_player_input_if_needed(attacker)
			return
		else:
			await damage_service.direct_attack(atk_card, attacker)
			_release_player_input_if_needed(attacker)
			return

	if not is_instance_valid(defending):
		if attacker == "Opponent":
			var defenders = bm.player_cards_on_battlefield.filter(func(c):
				return is_instance_valid(c) and card_runtime_service._card_kind(c) == "MONSTER"
			)
			if defenders.is_empty():
				await damage_service.direct_attack(atk_card, "Opponent")
		else:
			_release_player_input_if_needed(attacker)
		return

	reveal_service.reveal_card(defending)

	if attacker == "Player":
		$"../../CardManager".selected_monster = null

	await event_service._trigger_on_attack_effects(atk_card, attacker, battle_ctx)

	if not is_instance_valid(atk_card):
		_release_player_input_if_needed(attacker)
		return
	if not is_instance_valid(defending):
		if attacker == "Opponent":
			var live_defenders2 = _live_defenders_for("Player")
			if live_defenders2.size() == 0:
				await damage_service.direct_attack(atk_card, "Opponent")
		else:
			$"../../InputManager".inputs_disabled = false
			ui_service.enable_end_turn_button(true)
		return
	if bm.duel_finished:
		return

	var gsm = $"../../GuardianStarManager"
	var atk_star = (atk_card.current_guardian_star() if atk_card.has_method("current_guardian_star") else "")
	var def_star = (defending.current_guardian_star() if defending.has_method("current_guardian_star") else "")
	var gs_bonus = (gsm.compute_bonuses(atk_star, def_star) if gsm else {
		"attacker_atk":0, "attacker_def":0, "defender_atk":0, "defender_def":0
	})

	if gs_bonus.attacker_atk > 0 or gs_bonus.attacker_def > 0:
		if is_instance_valid(atk_card) and atk_card.has_method("play_guardian_star_bonus_animation"):
			await atk_card.play_guardian_star_bonus_animation(atk_star)

	if gs_bonus.defender_atk > 0 or gs_bonus.defender_def > 0:
		if is_instance_valid(defending) and defending.has_method("play_guardian_star_bonus_animation"):
			await defending.play_guardian_star_bonus_animation(def_star)

	await turn_service.action_waiter()

	var base_atk = (atk_card.get_effective_atk() if atk_card.has_method("get_effective_atk") else atk_card.atk)
	var base_def_atk = (defending.get_effective_atk() if defending.has_method("get_effective_atk") else defending.atk)
	var base_def_def = (defending.get_effective_def() if defending.has_method("get_effective_def") else defending.def)

	var temp_atk_atk = base_atk + int(gs_bonus.attacker_atk)
	var temp_def_atk = base_def_atk + int(gs_bonus.defender_atk)
	var temp_def_def = base_def_def + int(gs_bonus.defender_def)

	atk_card.z_index = 5
	var target_pos: Vector2 = animation_service._anchored_target_position(atk_card, defending, bm.BATTLE_POSS_OFFSET)
	var t := get_tree().create_tween()
	t.tween_property(atk_card, "global_position", target_pos, bm.CARD_MOVE_SPEED)
	await turn_service.action_waiter()

	if defending.in_defense:
		await _handle_defense_attack(atk_card, defending, attacker, temp_atk_atk, temp_def_def)
	else:
		await _handle_attack_attack(atk_card, defending, attacker, temp_atk_atk, temp_def_atk)

func _handle_defense_attack(atk_card, defending, attacker, atk_power, def_power):
	var defender_owner := ("Opponent" if attacker == "Player" else "Player")
	var result_str = "lose"

	var has_piercing := kw_service._has_kw(atk_card, "PIERCING") or bool(atk_card.get_meta("piercing_damage", false))

	if atk_power > def_power:
		var destroyed_atk := int(defending.get_effective_atk() if defending.has_method("get_effective_atk") else defending.atk)
		var destroyed_original_atk := int(defending.atk if ("atk" in defending) else 0)
		var destroyed_ref = defending
		var destroyed_ok := destruction_service.destroy_card(defending, defender_owner, "DESTROY_BATTLE")

		if destroyed_ok:
			event_service._emit_duel_event("ON_DESTROY_MONSTER_BY_BATTLE", {
				"battle_manager": bm,
				"source": atk_card,
				"attacker": atk_card,
				"destroyed": destroyed_ref,
				"destroyed_atk": destroyed_atk,
				"destroyed_original_atk": destroyed_original_atk,
				"controller": card_runtime_service._norm_owner(attacker),
				"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player")
			})

		result_str = "win"

	elif atk_power == def_power:
		result_str = "tie"

	else:
		var diff = def_power - atk_power

		if attacker == "Opponent":
			damage_service._apply_battle_damage_to_side("Opponent", diff, defending, atk_card)
		else:
			damage_service._apply_battle_damage_to_side("Player", diff, defending, atk_card)

	if has_piercing and atk_power > def_power:
		var piercing_damage = atk_power - def_power

		if attacker == "Opponent":
			damage_service._apply_battle_damage_to_side("Player", piercing_damage, atk_card, defending)
		else:
			damage_service._apply_battle_damage_to_side("Opponent", piercing_damage, atk_card, defending)

	if not card_runtime_service._is_card_alive(atk_card):
		stat_service._clear_bonuses([atk_card, defending])

		if attacker == "Player":
			ui_service._enable_player_input()

		return

	var return_pos: Vector2 = animation_service._anchored_slot_position(atk_card)
	var t2 := get_tree().create_tween()
	t2.tween_property(atk_card, "global_position", return_pos, bm.CARD_MOVE_SPEED)
	await t2.finished

	if card_runtime_service._is_card_alive(atk_card):
		atk_card.z_index = 0

	var defender_ref = defending if is_instance_valid(defending) else null

	await event_service._trigger_on_attack(atk_card, attacker, {
		"phase": "after_damage",
		"attacker": atk_card,
		"defender": defender_ref,
		"result": result_str
	})

	stat_service._clear_bonuses([atk_card, defending])

	atk_state_service._register_attack_spent(atk_card, attacker, defending)

	if attacker == "Player":
		ui_service._enable_player_input()

func _handle_attack_attack(atk_card, defending, _attacker, atk_power, def_power) -> void:
	var attacker_owner: String = card_runtime_service._norm_owner(_attacker)
	var defender_owner: String = card_runtime_service._norm_owner(zone_service._owner_of(defending))
	if defender_owner == "":
		defender_owner = ("Opponent" if attacker_owner == "Player" else "Player")

	var atk_i: int = int(atk_power)
	var def_i: int = int(def_power)

	if atk_i == def_i:
		destruction_service.destroy_card_tie(atk_card, defending)
		await event_service._trigger_on_attack(atk_card, attacker_owner, {
			"phase": "after_damage",
			"attacker": atk_card,
			"defender": defending,
			"result": "tie"
		})
		stat_service._clear_bonuses([atk_card, defending])

		atk_state_service._register_attack_spent(atk_card, attacker_owner, defending)

		if attacker_owner == "Player":
			ui_service._enable_player_input()
		return

	var attacker_won: bool = atk_i > def_i
	var damage: int = atk_i - def_i if attacker_won else def_i - atk_i

	if attacker_won:
		damage_service._apply_battle_damage_to_side(defender_owner, damage, atk_card, defending)
		var destroyed_atk := int(defending.get_effective_atk() if defending.has_method("get_effective_atk") else defending.atk)
		var destroyed_original_atk := int(defending.atk if ("atk" in defending) else 0)
		var destroyed_ref = defending
		var destroyed_ok := destruction_service.destroy_card(defending, defender_owner, "DESTROY_BATTLE")
		if destroyed_ok:
			event_service._emit_duel_event("ON_DESTROY_MONSTER_BY_BATTLE", {
				"battle_manager": bm,
				"source": atk_card,
				"attacker": atk_card,
				"destroyed": destroyed_ref,
				"destroyed_atk": destroyed_atk,
				"destroyed_original_atk": destroyed_original_atk,
				"controller": attacker_owner,
				"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player")
			})
	else:
		damage_service._apply_battle_damage_to_side(attacker_owner, damage, atk_card, defending)
		destruction_service.destroy_card(atk_card, attacker_owner, "DESTROY_BATTLE")

	if not card_runtime_service._is_card_alive(atk_card):
		stat_service._clear_bonuses([atk_card, defending])
		if attacker_owner == "Player":
			ui_service._enable_player_input()
		return

	var return_pos2: Vector2 = animation_service._anchored_slot_position(atk_card)
	var t2b := get_tree().create_tween()
	t2b.tween_property(atk_card, "global_position", return_pos2, bm.CARD_MOVE_SPEED)
	await t2b.finished

	if card_runtime_service._is_card_alive(atk_card):
		atk_card.z_index = 0

	var defender_ref2: Node = defending if is_instance_valid(defending) else null
	await event_service._trigger_on_attack(atk_card, attacker_owner, {
		"phase": "after_damage",
		"attacker": atk_card,
		"defender": defender_ref2,
		"result": ("win" if attacker_won else "lose")
	})

	stat_service._clear_bonuses([atk_card, defending])
	atk_state_service._register_attack_spent(atk_card, attacker_owner, defending)

	if attacker_owner == "Player":
		ui_service._enable_player_input()

func _live_defenders_for(attacker_side: String):
	var list = []
	if attacker_side == "Player":
		for d in bm.opponent_cards_on_battlefield:
			if is_instance_valid(d):
				list.append(d)
	else:
		for d in bm.player_cards_on_battlefield:
			if is_instance_valid(d):
				list.append(d)
	return list

func enemy_card_selected(defending_card) -> void:
	if animation_service.is_duel_animating():
		return
	if bm.duel_finished:
		return
	if bm.is_opponent_turn:
		return
	if not is_instance_valid(defending_card):
		return
	if card_runtime_service._card_kind(defending_card) != "MONSTER":
		return

	var attacker = $"../../CardManager".selected_monster
	if not is_instance_valid(attacker):
		return
	if card_runtime_service._card_kind(attacker) != "MONSTER":
		return
	if attacker.in_defense:
		return
	if kw_service._has_kw(attacker, "PARALYZED"):
		return
	if attacker in bm.player_cards_that_attacked_this_turn and not kw_service._has_kw(attacker, "MULTI_ATTACK_ALL"):
		return

	$"../../InputManager".inputs_disabled = true
	ui_service.enable_end_turn_button(false)
	$"../../CardManager".selected_monster = null

	await attack(attacker, defending_card, "Player")

	$"../../InputManager".inputs_disabled = false
	ui_service.enable_end_turn_button(true)

func _set_position(card: Card, pos: String) -> bool:
	if not is_instance_valid(card):
		return false
	if not card.is_on_field():
		return false

	var cardowner := card_runtime_service._norm_owner(zone_service._owner_of(card))

	if cardowner == "Player":
		if card in bm.player_cards_that_attacked_this_turn:
			return false
	else:
		if card in bm.opponent_cards_that_attacked_this_turn:
			return false

	var want_def := (pos.to_upper() == "DEFENSE")
	if card.has_method("set_defense_position"):
		card.set_defense_position(want_def)
	else:
		card.in_defense = want_def

	event_service._emit_duel_event("ON_CHANGE_POSITION", {
		"battle_manager": bm,
		"source": card,
		"controller": cardowner,
		"to_defense": want_def,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player")
	})
	return true

func _release_player_input_if_needed(attacker: String) -> void:
	if card_runtime_service._norm_owner(attacker) != "Player":
		return
	var im := get_node_or_null("../../InputManager")
	if im != null and bool(im.get("inputs_disabled")):
		im.inputs_disabled = false
	ui_service.enable_end_turn_button(true)
