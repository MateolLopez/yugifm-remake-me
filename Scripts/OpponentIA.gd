extends Node

var fusion_manager
var battle_manager
var opponent_hand
var card_manager
var played_monster_card_this_turn = false
var played_spellortrap_card_this_turn = false

func _ready() -> void:
	fusion_manager = $"../FusionManager"
	battle_manager = $"../BattleManager"
	opponent_hand = $"../OpponentHand"
	card_manager = $"../CardManager"

func make_turn_decisions():
	reset_played_cards()
	
	if fusion_manager.has_pending_fusion():
		await place_pending_fusion()
		if played_monster_card_this_turn:
			await adjust_all_battle_positions()
			await execute_intelligent_attacks()
			return
	
	var should_fuse = await evaluate_fusion_vs_normal_play()
	if should_fuse:
		var fusion_done = await try_generic_fusion()
		if fusion_done and fusion_manager.has_pending_fusion():
			await place_pending_fusion()
	
	if not fusion_manager.has_pending_fusion():
		await play_optimal_monsters()
	
	await adjust_all_battle_positions()
	await execute_intelligent_attacks()

func reset_played_cards():
	played_monster_card_this_turn = false
	played_spellortrap_card_this_turn = false

func evaluate_fusion_vs_normal_play() -> bool:
	if battle_manager.empty_monster_card_slots.size() == 0:
		return false
	if played_monster_card_this_turn:
		return false
	
	var available_monsters = opponent_hand.opponent_hand.filter(func(card): 
		return card.card_type == "Monster"
	)
	
	if available_monsters.size() < 2:
		return false
	
	var best_fusion_atk = find_best_possible_fusion_atk(available_monsters)
	if best_fusion_atk == 0:
		return false
	
	var best_hand_atk = find_best_monster_in_hand_atk(available_monsters)
	var strongest_player = get_strongest_player_monster()
	
	if strongest_player:
		var required_atk_to_win = strongest_player.Atk + 100
		if strongest_player.in_defense:
			required_atk_to_win = strongest_player.Def + 100
		
		if best_fusion_atk >= required_atk_to_win:
			return true
		elif best_hand_atk >= required_atk_to_win:
			return false
		else:
			return best_fusion_atk > best_hand_atk
	
	var fusion_threshold = max(best_hand_atk, 1200)
	return best_fusion_atk >= fusion_threshold

func find_best_possible_fusion_atk(monsters: Array) -> int:
	var best_atk = 0
	monsters.sort_custom(func(a, b): return a.Atk < b.Atk)
	
	for i in range(monsters.size()):
		for j in range(i + 1, monsters.size()):
			var card1 = monsters[i]
			var card2 = monsters[j]
			var probe_result = fusion_manager.generic_db.find_fusion(card1, card2)
			if probe_result != card2 and is_instance_valid(probe_result) and probe_result.fusion_result:
				var fusion_atk = probe_result.Atk
				if fusion_atk > best_atk:
					best_atk = fusion_atk
				probe_result.queue_free()
	
	return best_atk

func find_best_monster_in_hand_atk(monsters: Array) -> int:
	if monsters.size() == 0:
		return 0
	var best_atk = 0
	for monster in monsters:
		if monster.Atk > best_atk:
			best_atk = monster.Atk
	return best_atk

func try_generic_fusion() -> bool:
	if battle_manager.empty_monster_card_slots.size() == 0:
		return false
	if played_monster_card_this_turn:
		return false
	if fusion_manager.has_pending_fusion():
		return false

	var available_monsters = opponent_hand.opponent_hand.filter(func(card): 
		return card.card_type == "Monster"
	)
	
	if available_monsters.size() < 2:
		return false

	var best_combination = find_best_fusion_combination(available_monsters)
	if best_combination == null:
		return false

	fusion_manager.clear_materials()
	fusion_manager.add_material(best_combination[0], "generic")
	fusion_manager.add_material(best_combination[1], "generic")

	var fusion_result = fusion_manager.try_fusion("Opponent")
	if fusion_result.success:
		played_monster_card_this_turn = true
		return true

	return false

func find_best_fusion_combination(monsters: Array):
	var best_atk = 0
	var best_combination = null
	monsters.sort_custom(func(a, b): return a.Atk < b.Atk)
	
	for i in range(monsters.size()):
		for j in range(i + 1, monsters.size()):
			var card1 = monsters[i]
			var card2 = monsters[j]
			var probe_result = fusion_manager.generic_db.find_fusion(card1, card2)
			if probe_result != card2 and is_instance_valid(probe_result) and probe_result.fusion_result:
				var fusion_atk = probe_result.Atk
				if fusion_atk > best_atk:
					best_atk = fusion_atk
					best_combination = [card1, card2]
				probe_result.queue_free()
	
	return best_combination

func try_fusions() -> bool:
	if fusion_manager.fusion_performed_this_turn:
		return false
	var available_cards = opponent_hand.opponent_hand.duplicate()
	if try_specific_fusion(available_cards):
		return true
	return false

func try_specific_fusion(available_cards: Array) -> bool:
	return false

func _pick_opponent_monster_slot():
	if battle_manager.empty_monster_card_slots.size() == 0:
		return null
	var idx := randi_range(0, battle_manager.empty_monster_card_slots.size() - 1)
	return battle_manager.empty_monster_card_slots[idx]

func place_pending_fusion() -> bool:
	if not fusion_manager.has_pending_fusion():
		return false
	if battle_manager.empty_monster_card_slots.size() == 0:
		return false
	var slot = _pick_opponent_monster_slot()
	if slot == null:
		return false
	var placed = fusion_manager.place_fusion_card(slot)
	if placed:
		played_monster_card_this_turn = true
		if battle_manager.empty_monster_card_slots.has(slot):
			battle_manager.empty_monster_card_slots.erase(slot)
		return true
	return false

func play_optimal_monsters():
	if battle_manager.empty_monster_card_slots.size() == 0:
		return
	if played_monster_card_this_turn:
		return
	if fusion_manager.has_pending_fusion():
		return
	
	var available_monsters = opponent_hand.opponent_hand.filter(func(card):
		return card.card_type == "Monster"
	)
	if available_monsters.size() == 0:
		return
	available_monsters.sort_custom(func(a, b):
		return a.Atk > b.Atk
	)
	var best_monster = available_monsters[0]
	await play_monster_to_field(best_monster)

func play_monster_to_field(monster):
	if battle_manager.empty_monster_card_slots.size() == 0:
		return
	var slot_index = randi_range(0, battle_manager.empty_monster_card_slots.size() - 1)
	var slot = battle_manager.empty_monster_card_slots[slot_index]
	battle_manager.empty_monster_card_slots.erase(slot)
	opponent_hand.remove_card_from_hand(monster)
	monster.card_slot_card_is_in = slot
	slot.card_in_slot = true
	if "card_ref" in slot:
		slot.card_ref = monster
	var shape = slot.get_node("Area2D/CollisionShape2D") as CollisionShape2D
	if shape:
		shape.disabled = true
	monster.set_show_back_only(false)
	monster.set_facedown(true)
	monster.z_index = 5
	monster.scale = Vector2(card_manager.FIELD_SCALE, card_manager.FIELD_SCALE)
	var final_pos = battle_manager._anchored_slot_position(monster)
	var tw = get_tree().create_tween()
	tw.tween_property(monster, "global_position", final_pos, battle_manager.CARD_MOVE_SPEED)
	await tw.finished
	battle_manager.opponent_cards_on_battlefield.append(monster)
	played_monster_card_this_turn = true
	await battle_manager.action_waiter()

func adjust_all_battle_positions():
	var strongest_player_monster = get_strongest_player_monster()
	
	for card in battle_manager.opponent_cards_on_battlefield:
		if not is_instance_valid(card):
			continue
			
		var should_defend = false
		
		if battle_manager.player_cards_on_battlefield.size() == 0:
			should_defend = false
		elif strongest_player_monster:
			var can_destroy_any = false
			for player_monster in battle_manager.player_cards_on_battlefield:
				if is_instance_valid(player_monster) and can_destroy_target(card, player_monster):
					can_destroy_any = true
					break
			
			if not can_destroy_any:
				should_defend = true
			else:
				should_defend = false
		else:
			should_defend = false
		
		if should_defend and not card.in_defense:
			card.toggle_defense_position()
		elif not should_defend and card.in_defense:
			card.toggle_defense_position()

func can_beat_monster(attacker, defender):
	if defender.in_defense:
		return attacker.Atk > defender.Def
	else:
		return attacker.Atk >= defender.Atk

func find_optimal_target(attacker):
	var player_monsters = battle_manager.player_cards_on_battlefield.duplicate()
	player_monsters = player_monsters.filter(func(card): return is_instance_valid(card))
	if player_monsters.size() == 0:
		return null
	
	var attack_monsters = player_monsters.filter(func(m): return not m.in_defense)
	var defense_monsters = player_monsters.filter(func(m): return m.in_defense)
	
	attack_monsters.sort_custom(func(a, b): return a.Atk > b.Atk)
	defense_monsters.sort_custom(func(a, b): return a.Def > b.Def)
	
	var sorted_monsters = attack_monsters + defense_monsters
	
	for target in sorted_monsters:
		if can_destroy_target(attacker, target):
			return target
	
	return null

func can_destroy_target(attacker, target):
	if target.in_defense:
		return attacker.Atk > target.Def
	else:
		return attacker.Atk >= target.Atk

func execute_intelligent_attacks():
	var attackable_monsters = battle_manager.opponent_cards_on_battlefield.duplicate()
	attackable_monsters = attackable_monsters.filter(func(card):
		return is_instance_valid(card) and not card.in_defense
	)
	
	attackable_monsters.sort_custom(func(a, b): return a.Atk > b.Atk)
	
	for attacker in attackable_monsters:
		if battle_manager.player_cards_on_battlefield.size() == 0:
			await battle_manager.direct_attack(attacker, "Opponent")
			await battle_manager.action_waiter()
			continue
		
		var best_target = find_optimal_target(attacker)
		if best_target:
			await battle_manager.attack(attacker, best_target, "Opponent")
			await battle_manager.action_waiter()

func get_strongest_player_monster():
	var player_monsters = battle_manager.player_cards_on_battlefield.duplicate()
	player_monsters = player_monsters.filter(func(card): return is_instance_valid(card))
	if player_monsters.size() == 0:
		return null
	player_monsters.sort_custom(func(a, b): return a.Atk > b.Atk)
	return player_monsters[0]
