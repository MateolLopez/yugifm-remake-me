extends Node

const BATTLE_POSS_OFFSET = 25
const CARD_MOVE_SPEED = 0.2
const MAX_HAND_SIZE = 5
const STARTING_HP = 8000

signal duel_over(result: String)

var duel_finished = false
var battle_timer
var empty_monster_card_slots = []
var opponent_cards_on_battlefield = []
var player_cards_on_battlefield = []
var player_cards_that_attacked_this_turn = []
var player_graveyard = []
var opponent_graveyard = []
var player_hp
var opponent_hp
var spell_targeting := false
var pending_spell = null
var pending_effects = []
var pending_effect: Array = []
var pending_caster := ""
var pending_required_targets := 0
var pending_targets: Array = []
var suppress_on_attack = false
var multi_mode = {}
var multi_remaining = {}
var multi_already_attacked = {}
var is_opponent_turn = false

signal attack_declared(attacker, defender, attacker_owner)
signal monster_played(monster, owner)
signal spell_activated(spell, owner)
signal trap_activated(trap, owner)
signal turn_started(turn_owner)
signal turn_ended(turn_owner)

func _ready() -> void:
	battle_timer = $"../BattleTimer"
	battle_timer.one_shot = true
	battle_timer.wait_time = 0.5

	empty_monster_card_slots.append($"../CardSlotsRival/CardSlot")
	empty_monster_card_slots.append($"../CardSlotsRival/CardSlot2")
	empty_monster_card_slots.append($"../CardSlotsRival/CardSlot3")
	empty_monster_card_slots.append($"../CardSlotsRival/CardSlot4")
	empty_monster_card_slots.append($"../CardSlotsRival/CardSlot5")
	
	player_hp = STARTING_HP
	$"../PlayerHP".text = str(player_hp)
	opponent_hp = STARTING_HP
	$"../OpponentHP".text = str(opponent_hp)
	
	# Verificar conexión de señales
	print(">>> BATTLE_MANAGER: Conectando señales...")
	print(">>> attack_declared conectado: ", attack_declared.get_connections().size(), " conexiones")
	print(">>> monster_played conectado: ", monster_played.get_connections().size(), " conexiones")
	print(">>> spell_activated conectado: ", spell_activated.get_connections().size(), " conexiones")
	print(">>> trap_activated conectado: ", trap_activated.get_connections().size(), " conexiones")
	await get_tree().create_timer(5.0).timeout
	_test_trap_system()

func _test_trap_system():
	print("\n=== TEST DEL SISTEMA DE TRAMPAS ===")
	print(">>> Emitiendo señal de prueba...")
	
	# Crear un contexto de prueba real
	if opponent_cards_on_battlefield.size() > 0:
		var test_attacker = opponent_cards_on_battlefield[0]
		emit_signal("attack_declared", test_attacker, null, "Opponent")
	else:
		print(">>> No hay monstruos del oponente para probar")

func _clear_multi_for(card):
	multi_mode.erase(card)
	multi_remaining.erase(card)
	multi_already_attacked.erase(card)

func _cleanup_multi_garbage():
	for k in multi_mode.keys():
		if not is_instance_valid(k) or (k not in player_cards_on_battlefield and k not in opponent_cards_on_battlefield):
			_clear_multi_for(k)

func _on_end_turn_button_pressed() -> void:
	for k in multi_mode.keys():
		if is_instance_valid(k) and (k in player_cards_on_battlefield):
			_clear_multi_for(k)
	_cleanup_multi_garbage()
	is_opponent_turn = true
	$"../CardManager".unselect_selected_monster()
	$"../FusionManager".reset_turn()
	player_cards_that_attacked_this_turn = []
	$"../CardManager".reset_played_cards()
	opponent_turn()

func opponent_turn():
	if duel_finished: return
	$"../EndTurnButton".disabled = true
	$"../EndTurnButton".visible = false
	
	await yield_to_refill_opponent_hand()
	await action_waiter()
	var opponent_ia = $"../OpponentIA"
	if opponent_ia:
		await opponent_ia.make_turn_decisions()
		await action_waiter()
	
	await end_opponent_turn()

func can_attack_directly(attacker_card):
	if not is_instance_valid(attacker_card):
		return
	if attacker_card.has_meta("only_direct_attack") and attacker_card.get_meta("only_direct_attack"):
		return true
	if attacker_card.has_meta("can_direct_attack") and attacker_card.get_meta("can_direct_attack"):
		return true
			
	var defenders = _live_defenders_for("Player" if _owner_of(attacker_card) == "Opponent" else "Opponent")
	return defenders.size() == 0

func trigger_on_play_effects(card, who: String) -> void:
	if not is_instance_valid(card) or card.effects == null:
		return
		
	for effect in card.effects:
		if effect is Dictionary and effect.get("type") == "on_play":
			await $"../Effect_Manager".execute_effect(effect, card, who, {"card": card})

func attack(atk_card, defending, attacker):
	if(atk_card.card_type != "Monster"):
		return
	if duel_finished: return
	if not is_instance_valid(atk_card):
		return
	print(">>> BATTLE_MANAGER: Emitiendo attack_declared")
	print(">>>   Atacante: ", atk_card.card_name)
	print(">>>   Defensor: ", defending.card_name if defending else "DIRECT_ATTACK")
	print(">>>   Owner atacante: ", attacker)
	
	emit_signal("attack_declared", atk_card, defending, attacker)
	
	if atk_card.has_meta("only_direct_attack") and atk_card.get_meta("only_direct_attack"):
		if is_instance_valid(defending):
			return
		else:
			await direct_attack(atk_card, attacker)
			return
	
	if not is_instance_valid(defending):
		if attacker == "Opponent":
			var live_defenders = _live_defenders_for("Opponent")
			if live_defenders.size() == 0:
				await direct_attack(atk_card, "Opponent")
		else:
			$"../InputManager".inputs_disabled = false
			enable_end_turn_button(true)
		return

	reveal_card(atk_card)
	reveal_card(defending)

	if attacker == "Player":
		$"../InputManager".inputs_disabled = true
		enable_end_turn_button(false)
		$"../CardManager".selected_monster = null

	await _trigger_on_attack_effects(atk_card, attacker, {
		"phase": "declare",
		"attacker": atk_card,
		"defender": defending
	})

	if not is_instance_valid(atk_card):
		if attacker == "Player":
			$"../InputManager".inputs_disabled = false
			enable_end_turn_button(true)
		return
	if not is_instance_valid(defending):
		if attacker == "Opponent":
			var live_defenders2 = _live_defenders_for("Opponent")
			if live_defenders2.size() == 0:
				await direct_attack(atk_card, "Opponent")
		else:
			$"../InputManager".inputs_disabled = false
			enable_end_turn_button(true)
		return
	if duel_finished:
		return

	var gsm = $"../GuardianStarManager"
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

	await action_waiter()

	var temp_atk_atk = atk_card.Atk + int(gs_bonus.attacker_atk)
	var temp_def_atk = defending.Atk + int(gs_bonus.defender_atk)
	var temp_def_def = defending.Def + int(gs_bonus.defender_def)

	atk_card.z_index = 5
	var target_pos: Vector2 = _anchored_target_position(atk_card, defending, BATTLE_POSS_OFFSET)
	var t := get_tree().create_tween()
	t.tween_property(atk_card, "global_position", target_pos, CARD_MOVE_SPEED)
	await action_waiter()

	if defending.in_defense:
		await _handle_defense_attack(atk_card, defending, attacker, temp_atk_atk, temp_def_def)
	else:
		await _handle_attack_attack(atk_card, defending, attacker, temp_atk_atk, temp_def_atk)

func _trigger_on_attack_effects(card, who: String, ctx: Dictionary) -> void:
	if not card.get("effects"):
		return
	
	for effect_data in card.effects:
		if effect_data.get("type") == "on_attack":
			await $"../Effect_Manager".execute_effect(effect_data, card, who, ctx)

func _place_card_in_slot(card: Node2D, slot: Node2D) -> void:
	card.card_slot_card_is_in = slot
	slot.card_in_slot = true
	
	var should_reveal = false
	
	# Cartas de trampa siempre boca abajo
	if card.attribute == "trap":
		card.set_facedown(true)
		should_reveal = false
		# IMPORTANTE: Activar efectos de trampa inmediatamente al colocarla
		if card.has_method("activate_trap_effects"):
			print(">>> Colocando trampa - activando efectos: ", card.card_name)
			card.activate_trap_effects()
	
	if card.card_type == "Monster":
		print(">>> BATTLE_MANAGER: Emitiendo monster_played - ", card.card_name, " - Owner: ", card.card_owner)
		emit_signal("monster_played", card, card.card_owner)
	elif card.attribute == "spell":
		print(">>> BATTLE_MANAGER: Emitiendo spell_activated - ", card.card_name, " - Owner: ", card.card_owner)
		emit_signal("spell_activated", card, card.card_owner)
	elif card.attribute == "trap":
		print(">>> BATTLE_MANAGER: Emitiendo trap_activated - ", card.card_name, " - Owner: ", card.card_owner)
		emit_signal("trap_activated", card, card.card_owner)
	# Cartas de hechizo: boca abajo a menos que tengan efecto inmediato
	elif card.attribute == "spell":
		if _has_immediate_effect(card):
			card.set_facedown(false)
			should_reveal = true
		else:
			card.set_facedown(true)
			should_reveal = false
	# Monstruos: boca abajo a menos que tengan efecto inmediato o sean fusión/ritual
	elif card.card_type == "Monster":
		if card.fusion_result or _has_immediate_effect(card):
			card.set_facedown(false)
			should_reveal = true
		else:
			card.set_facedown(true)
			should_reveal = false
	
	card.set_show_back_only(false)
	card.scale = Vector2($"../CardManager".FIELD_SCALE, $"../CardManager".FIELD_SCALE)
	$"../CardManager"._snap_card_to_slot_center(card, slot)
	card.z_index = -4
	
	# EMITIR SEÑAL para trampas - después de colocar
	if card.card_type == "Monster":
		print(">>> BATTLE_MANAGER: Emitiendo monster_played - ", card.card_name, " - Owner: ", card.card_owner)
		emit_signal("monster_played", card, card.card_owner)
	elif card.attribute == "spell":
		print(">>> BATTLE_MANAGER: Emitiendo spell_activated - ", card.card_name, " - Owner: ", card.card_owner)
		emit_signal("spell_activated", card, card.card_owner)
	elif card.attribute == "trap":
		print(">>> BATTLE_MANAGER: Emitiendo trap_activated - ", card.card_name, " - Owner: ", card.card_owner)
		emit_signal("trap_activated", card, card.card_owner)
	
	# Si la carta se revela, activar efectos on_play inmediatos
	if should_reveal:
		reveal_card(card)
		# Activar efectos on_play si los tiene
		_trigger_on_play_effects(card, card.card_owner)

func _has_immediate_effect(card) -> bool:
	if not card.get("effects"):
		return false
	
	for effects in card.effects:
		if effects.get("type") == "on_play":
			return true
		if effects.get("type") == "spell_activation" and effects.get("immediate", false):
			return true
	
	return false

func _trigger_on_play_effects(card, card_owner: String) -> void:
	if not card.get("effects"):
		return
	
	for effect_data in card.effects:
		if effect_data.get("type") == "on_play":
			$"../Effect_Manager".execute_effect(effect_data, card, card_owner, {"card": card})

func _handle_defense_attack(atk_card, defending, attacker, atk_power, def_power):
	var defender_owner := ("Opponent" if attacker == "Player" else "Player")
	var result_str = "lose"
	
	var has_piercing = atk_card.get_meta("piercing_damage", false)
	
	if atk_power > def_power:
		destroy_card(defending, defender_owner)
		result_str = "win"
	elif atk_power == def_power:
		result_str = "tie"
	else:
		var diff = def_power - atk_power
		if attacker == "Opponent":
			opponent_hp = max(0, opponent_hp - diff)
			$"../OpponentHP".text = str(opponent_hp)
		else:
			player_hp = max(0, player_hp - diff)
			$"../PlayerHP".text = str(player_hp)
		_check_end_duel()
	
	if has_piercing and atk_power > def_power:
		var piercing_damage = atk_power - def_power
		if attacker == "Opponent":
			player_hp = max(0, player_hp - piercing_damage)
			$"../PlayerHP".text = str(player_hp)
		else:
			opponent_hp = max(0, opponent_hp - piercing_damage)
			$"../OpponentHP".text = str(opponent_hp)
		_check_end_duel()

	if not _is_card_alive(atk_card):
		_clear_bonuses([atk_card, defending])
		if attacker == "Player":
			_enable_player_input()
		return

	var return_pos: Vector2 = _anchored_slot_position(atk_card)
	var t2 := get_tree().create_tween()
	t2.tween_property(atk_card, "global_position", return_pos, CARD_MOVE_SPEED)
	await t2.finished
	
	if _is_card_alive(atk_card):
		atk_card.z_index = 0

	var defender_ref = defending if is_instance_valid(defending) else null
	await _trigger_on_attack(atk_card, attacker, {
		"phase": "after_damage",
		"attacker": atk_card,
		"defender": defender_ref,
		"result": result_str
	})

	_clear_bonuses([atk_card, defending])
	
	if attacker == "Player" and not (atk_card in player_cards_that_attacked_this_turn):
		player_cards_that_attacked_this_turn.append(atk_card)

	if attacker == "Player":
		_enable_player_input()

func _handle_attack_attack(atk_card, defending, attacker, atk_power, def_power):
	if atk_power == def_power:
		destroy_card_tie(atk_card, defending)
		await _trigger_on_attack(atk_card, attacker, {
			"phase": "after_damage",
			"attacker": atk_card,
			"defender": defending,
			"result": "tie"
		})
		_clear_bonuses([atk_card, defending])
		if attacker == "Player" and not (atk_card in player_cards_that_attacked_this_turn):
			player_cards_that_attacked_this_turn.append(atk_card)
		_enable_player_input()
		return

	var attacker_won = atk_power > def_power
	var damage = abs(atk_power - def_power)
	
	if attacker_won:
		if attacker == "Opponent":
			player_hp = max(0, player_hp - damage)
			$"../PlayerHP".text = str(player_hp)
			_check_end_duel()
			destroy_card(defending, "Player")
		else:
			opponent_hp = max(0, opponent_hp - damage)
			$"../OpponentHP".text = str(opponent_hp)
			_check_end_duel()
			destroy_card(defending, "Opponent")
	else:
		if attacker == "Opponent":
			opponent_hp = max(0, opponent_hp - damage)
			$"../OpponentHP".text = str(opponent_hp)
			_check_end_duel()
			destroy_card(atk_card, "Opponent")
		else:
			player_hp = max(0, player_hp - damage)
			$"../PlayerHP".text = str(player_hp)
			_check_end_duel()
			destroy_card(atk_card, "Player")

	if not _is_card_alive(atk_card):
		_clear_bonuses([atk_card, defending])
		if attacker == "Player":
			_enable_player_input()
		return

	var return_pos2: Vector2 = _anchored_slot_position(atk_card)
	var t2b := get_tree().create_tween()
	t2b.tween_property(atk_card, "global_position", return_pos2, CARD_MOVE_SPEED)
	await t2b.finished
	
	if _is_card_alive(atk_card):
		atk_card.z_index = 0

	var defender_ref2 = defending if is_instance_valid(defending) else null
	await _trigger_on_attack(atk_card, attacker, {
		"phase": "after_damage",
		"attacker": atk_card,
		"defender": defender_ref2,
		"result": ("win" if attacker_won else "lose")
	})

	_clear_bonuses([atk_card, defending])
	
	if attacker == "Player" and not (atk_card in player_cards_that_attacked_this_turn):
		player_cards_that_attacked_this_turn.append(atk_card)

	if attacker == "Player":
		_enable_player_input()

func _is_card_alive(card) -> bool:
	return is_instance_valid(card) and (card in player_cards_on_battlefield or card in opponent_cards_on_battlefield)

func _clear_bonuses(cards: Array):
	for card in cards:
		if is_instance_valid(card) and card.has_method("clear_temporary_display_bonus"):
			card.clear_temporary_display_bonus()

func _enable_player_input():
	$"../InputManager".inputs_disabled = false
	enable_end_turn_button(true)

func _owner_of(card) -> String:
	if card in player_cards_on_battlefield:
		return "Player"
	if card in opponent_cards_on_battlefield:
		return "Opponent"
	return ""

func destroy_card_tie(card_a, card_b):
	if is_instance_valid(card_a):
		var owner_a := _owner_of(card_a)
		if owner_a != "":
			destroy_card(card_a, owner_a)
	if is_instance_valid(card_b):
		var owner_b := _owner_of(card_b)
		if owner_b != "":
			destroy_card(card_b, owner_b)
	_clear_multi_for(card_a)
	_clear_multi_for(card_b)

func direct_attack(atk_card, attacker):
	if duel_finished: return
	var new_pos_y
	reveal_card(atk_card)
	if attacker == "Opponent":
		new_pos_y = 1000
	else:
		$"../InputManager".inputs_disabled = true
		enable_end_turn_button(false)
		new_pos_y = 0
		player_cards_that_attacked_this_turn.append(atk_card)
	var new_pos = Vector2(atk_card.global_position.x,new_pos_y)
	
	atk_card.z_index = 5
	
	var t := get_tree().create_tween()
	t.tween_property(atk_card, "global_position", new_pos, CARD_MOVE_SPEED)
	await action_waiter()
	
	if attacker == "Opponent":
		player_hp = max(0,player_hp - atk_card.Atk)
		$"../PlayerHP".text = str(player_hp)
		_check_end_duel()
	else:
		opponent_hp = max(0,opponent_hp - atk_card.Atk)
		$"../OpponentHP".text = str(opponent_hp)
		_check_end_duel()
	if duel_finished:
		return
	var return_pos :Vector2 = _anchored_slot_position(atk_card)
	var t2 := get_tree().create_tween()
	t2.tween_property(atk_card, "global_position", return_pos, CARD_MOVE_SPEED)
	await action_waiter()
	atk_card.z_index = 0
	if attacker == "Player":
		$"../InputManager".inputs_disabled = true
		enable_end_turn_button(false)

func _clean_battlefield_lists():
	player_cards_on_battlefield = player_cards_on_battlefield.filter(is_instance_valid)
	opponent_cards_on_battlefield = opponent_cards_on_battlefield.filter(is_instance_valid)

func _has_on_attack(card) -> bool:
	if card == null: return false
	if card.effects == null: return false
	var eff_list = card.effects
	if typeof(eff_list) != TYPE_ARRAY: return false
	if eff_list.size() == 0: return false
	
	for effect in eff_list:
		if effect is Dictionary and effect.get("type") == "on_attack":
			return true
	
	return false

func _trigger_on_attack(card, who: String, ctx: Dictionary) -> void:
	if suppress_on_attack: 
		return
	if not is_instance_valid(card): 
		return
	if not _has_on_attack(card):
		return
	
	suppress_on_attack = true
	
	# Ejecutar todos los efectos "on_attack" de la carta
	for effect in card.effects:
		if effect is Dictionary and effect.get("type") == "on_attack":
			await $"../Effect_Manager".execute_effect(effect, card, who, ctx)
	
	suppress_on_attack = false

func _live_defenders_for(attacker_side: String):
	var list = []
	if attacker_side == "Player":
		for d in opponent_cards_on_battlefield:
			if is_instance_valid(d):
				list.append(d)
	else:
		for d in player_cards_on_battlefield:
			if is_instance_valid(d):
				list.append(d)
	return list

func _targets_required_for(effect_list: Array) -> int:
	var n := 0
	for e in effect_list:
		if e == "target_enemy_monster":
			n += 1
	return n

func start_spell_activation(spell_card, who: String) -> void:
	emit_signal("spell_activated", spell_card, who)
	# Revelar la carta si está boca abajo
	if spell_card.is_facedown:
		reveal_card(spell_card)
	
	# EMITIR SEÑAL para trampas que respondan a activación de hechizos
	emit_signal("spell_activated", spell_card, who)
	
	# Verificar si tiene efectos
	if not spell_card.get("effects"):
		_send_spell_to_graveyard(spell_card, who)
		return
	
	# Buscar efectos de activación de hechizo
	var activation_effects = []
	for effects in spell_card.effects:
		if effects.get("type") == "spell_activation":
			activation_effects.append(effects)
	
	if activation_effects.is_empty():
		_send_spell_to_graveyard(spell_card, who)
		return
	
	# Verificar si necesita targets
	var need_targets = false
	for effects in activation_effects:
		if effects.get("requires_target", false):
			need_targets = true
			break
	
	if not need_targets:
		# Ejecutar todos los efectos sin targets
		for effects in activation_effects:
			await $"../Effect_Manager".execute_effect(effects, spell_card, who, {})
		_send_spell_to_graveyard(spell_card, who)
	else:
		# Configurar targeting
		spell_targeting = true
		pending_spell = spell_card
		pending_effects = activation_effects  # Ahora puede tener múltiples efectos
		pending_caster = who
		pending_required_targets = 1  # Por simplicidad, asumimos 1 target por ahora
		pending_targets = []
		$"../EndTurnButton".disabled = true

func receive_spell_target(card) -> void:
	if not spell_targeting: return

	var is_enemy = (pending_caster == "Player" and card in opponent_cards_on_battlefield) \
		or (pending_caster == "Opponent" and card in player_cards_on_battlefield)
	if not is_enemy:
		return
	if pending_targets.has(card):
		return

	pending_targets.append(card)

	if pending_targets.size() >= pending_required_targets:
		$"../Effects".execute(pending_effect, pending_caster, {"targets": pending_targets})
		_send_spell_to_graveyard(pending_spell, pending_caster)
		_clear_spell_targeting()

func _clear_spell_targeting() -> void:
	spell_targeting = false
	pending_spell = null
	pending_effects = []
	pending_caster = ""
	pending_required_targets = 0
	pending_targets = []
	$"../EndTurnButton".disabled = false

func _send_spell_to_graveyard(spell_card, who: String) -> void:
	if spell_card.card_slot_card_is_in:
		spell_card.card_slot_card_is_in.card_in_slot = false
		if "card_ref" in spell_card.card_slot_card_is_in:
			spell_card.card_slot_card_is_in.card_ref = null
	if who == "Player":
		player_graveyard.append(spell_card)
	else:
		opponent_graveyard.append(spell_card)
	spell_card.queue_free()
	_clean_battlefield_lists()

func destroy_card(card, card_owner):
	if card_owner == "Player":
		card.defeated = true
		card.get_node("Area2D/CollisionShape2D").disabled = true
		if card in player_cards_on_battlefield:
			player_graveyard.append(card)
			player_cards_on_battlefield.erase(card)
			card.card_slot_card_is_in.get_node("Area2D/CollisionShape2D").disabled = false
	else:
		if card in opponent_cards_on_battlefield:
			opponent_graveyard.append(card)
			opponent_cards_on_battlefield.erase(card)
	if card.card_slot_card_is_in:
		card.card_slot_card_is_in.card_in_slot = false
		if "card_ref" in card.card_slot_card_is_in:
			card.card_slot_card_is_in.card_ref = null
		var slot = card.card_slot_card_is_in
		if slot.get_parent() == $"../CardSlotsRival":
			if not empty_monster_card_slots.has(slot):
				empty_monster_card_slots.append(slot)
	if multi_mode.has(card): multi_mode.erase(card)
	if multi_remaining.has(card): multi_remaining.erase(card)
	if multi_already_attacked.has(card): multi_already_attacked.erase(card)
	card.queue_free()
	_clean_battlefield_lists()
	_clear_multi_for(card)

func yield_to_refill_opponent_hand():
	var deck_rival = $"../DeckRival/Deck"
	var opp_hand = $"../OpponentHand"
	while deck_rival.opponent_deck.size() > 0 and opp_hand.opponent_hand.size() < MAX_HAND_SIZE:
		deck_rival.draw_card()
		await action_waiter()

func enemy_card_selected(defending_card):
	var atk_card = $"../CardManager".selected_monster
	if atk_card:
		if defending_card in opponent_cards_on_battlefield:
			attack(atk_card, defending_card, "Player")

func try_play_highest_atk_card():
	var opponent_hand = $"../OpponentHand".opponent_hand
	if opponent_hand.is_empty():
		return

	var monsters: Array = []
	for c in opponent_hand:
		if c.card_type == "Monster":
			monsters.append(c)
	if monsters.is_empty():
		return

	var slot_index := randi_range(0, empty_monster_card_slots.size() - 1)
	var slot = empty_monster_card_slots[slot_index]
	empty_monster_card_slots.erase(slot)

	var card_highestAtk = monsters[0]
	for c in monsters:
		if c.Atk > card_highestAtk.Atk:
			card_highestAtk = c

	$"../OpponentHand".remove_card_from_hand(card_highestAtk)

	card_highestAtk.card_slot_card_is_in = slot
	slot.card_in_slot = true
	if "card_ref" in slot:
		slot.card_ref = card_highestAtk
	var shape := slot.get_node("Area2D/CollisionShape2D") as CollisionShape2D
	if shape:
		shape.disabled = true

	card_highestAtk.set_show_back_only(false)
	card_highestAtk.set_facedown(true)  
	card_highestAtk.z_index = 5

	var mgr := $"../CardManager"
	card_highestAtk.scale = Vector2(mgr.FIELD_SCALE, mgr.FIELD_SCALE)

	var final_pos = _anchored_slot_position(card_highestAtk)

	var tw := get_tree().create_tween()
	tw.tween_property(card_highestAtk, "global_position", final_pos, CARD_MOVE_SPEED)
	await tw.finished

	opponent_cards_on_battlefield.append(card_highestAtk)
	await action_waiter()

func end_opponent_turn():
	var player_deck = $"../Deck"
	var player_hand_node = $"../PlayerHand"
	var card_manager = $"../CardManager"
	is_opponent_turn = false
	card_manager.reset_played_cards()
	for k in multi_mode.keys():
		if is_instance_valid(k) and (k in opponent_cards_on_battlefield):
			_clear_multi_for(k)
		_cleanup_multi_garbage()
	while player_deck.player_deck.size() > 0 and player_hand_node.player_hand.size() < MAX_HAND_SIZE:
		player_deck.draw_card()
		card_manager.reset_played_monster()
		await action_waiter()

	$"../EndTurnButton".disabled = false
	$"../EndTurnButton".visible = true

func reveal_card(card: Node):
	if not is_instance_valid(card): return
	if "is_facedown" in card and card.is_facedown:
		card.set_facedown(false)
		if card.has_method("ensure_guardian_initialized"):
			card.ensure_guardian_initialized()
		if card.has_method("_update_guardian_star_label"):
			card._update_guardian_star_label()

func enable_end_turn_button(is_enabled):
	if is_enabled:
		$"../EndTurnButton".disabled = false
		$"../EndTurnButton".visible = true
	else:
		$"../EndTurnButton".disabled = true
		$"../EndTurnButton".visible = false

func action_waiter():
	battle_timer.start()
	await battle_timer.timeout

func _check_end_duel() -> bool:
	if duel_finished:
		return true
	if player_hp <= 0 and opponent_hp <= 0:
		duel_finished = true
		emit_signal("duel_over", "draw")
	elif player_hp <= 0:
		duel_finished = true
		emit_signal("duel_over","player_defeat")
	elif opponent_hp <= 0:
		duel_finished = true
		emit_signal("duel_over","player_victory")
	return duel_finished

func _anchored_slot_position(card: Node2D):
	if card == null or card.card_slot_card_is_in == null:
		return card.global_position
	var slot = card.card_slot_card_is_in as Node2D
	var card_anchor = card.get_node_or_null("AnchorCenter") as Node2D
	var slot_anchor = slot.get_node_or_null("Anchor") as Node2D
	var target = slot_anchor if slot_anchor else slot
	var delta = card_anchor.to_global(Vector2.ZERO) - card.to_global(Vector2.ZERO)
	return target.global_position - delta

func _anchored_target_position(attacker: Node2D, defender: Node2D, y_offset := 0.0) -> Vector2:
	var def_anchor := defender.get_node_or_null("AnchorCenter") as Node2D
	var def_center := (def_anchor if def_anchor else defender) as Node2D
	var atk_anchor := attacker.get_node_or_null("AnchorCenter") as Node2D
	var atk_delta := atk_anchor.to_global(Vector2.ZERO) - attacker.to_global(Vector2.ZERO)
	return def_center.global_position - atk_delta + Vector2(0, y_offset)
