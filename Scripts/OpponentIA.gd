extends Node

var fusion_manager: Node
var battle_manager: Node
var opponent_hand: Node
var card_manager: Node

var played_monster_card_this_turn: bool = false
var played_spellortrap_card_this_turn: bool = false

@onready var _slots_root_opponent: Node = get_node_or_null("../CardSlotsRival")
@onready var _slots_root_player: Node = get_node_or_null("../CardSlots")

func _ready() -> void:
	fusion_manager = get_node_or_null("../FusionManager")
	battle_manager = get_node_or_null("../BattleManager")
	opponent_hand = get_node_or_null("../OpponentHand")
	card_manager = get_node_or_null("../CardManager")

func make_turn_decisions() -> void:
	reset_played_cards()

	if _has_pending_fusion():
		place_pending_fusion()
		if played_monster_card_this_turn:
			adjust_all_battle_positions()
			await execute_intelligent_attacks()
			return

	var should_fuse := evaluate_fusion_vs_normal_play()
	if should_fuse:
		var fusion_done := await try_generic_fusion()
		if fusion_done and _has_pending_fusion():
			place_pending_fusion()

	if not _has_pending_fusion():
		await play_optimal_monsters()

	await play_one_spelltrap_set()

	adjust_all_battle_positions()
	await execute_intelligent_attacks()

func reset_played_cards() -> void:
	played_monster_card_this_turn = false
	played_spellortrap_card_this_turn = false

# ---------------------------
# Utilidades
# ---------------------------

func _has_pending_fusion() -> bool:
	return fusion_manager != null and fusion_manager.has_method("has_pending_fusion") and fusion_manager.has_pending_fusion()

func _get_free_slots(side: String, slot_type: String) -> Array:
	var root := _slots_root_player if side == "Player" else _slots_root_opponent
	if not is_instance_valid(root):
		return []
	var free: Array = []
	for child in root.get_children():
		if not is_instance_valid(child):
			continue
		var t := str(child.get("card_slot_type"))
		if t != slot_type:
			continue
		var occupied := bool(child.get("card_in_slot"))
		if not occupied:
			free.append(child)
	return free

func _pick_free_monster_slot_opponent():
	var free := _get_free_slots("Opponent", "Monster")
	if free.is_empty():
		return null
	return free[randi_range(0, free.size() - 1)]

func _register_card_played_to_battle(card: Node, owner: String) -> void:
	if not is_instance_valid(card) or battle_manager == null:
		return
	if battle_manager.has_method("register_card_played"):
		var owner_arg := owner
		var args := [card, owner_arg]
		battle_manager.callv("register_card_played", args)

func _get_opponent_hand_monsters() -> Array:
	if not opponent_hand:
		return []
	var arr: Array = opponent_hand.get("opponent_hand")
	if arr == null:
		return []
	return arr.filter(func(c):
		return is_instance_valid(c) and str(c.get("kind")).to_upper() == "MONSTER"
	)

# ---------------------------
# Fusión
# ---------------------------

func evaluate_fusion_vs_normal_play() -> bool:
	if played_monster_card_this_turn:
		return false
	if _get_free_slots("Opponent", "Monster").is_empty():
		return false

	var available_monsters := _get_opponent_hand_monsters()
	if available_monsters.size() < 2:
		return false

	var best_fusion_atk := find_best_possible_fusion_atk(available_monsters)
	if best_fusion_atk <= 0:
		return false

	var best_hand_atk := find_best_monster_in_hand_atk(available_monsters)
	var strongest_player = get_strongest_player_monster()

	if is_instance_valid(strongest_player):
		var required_atk_to_win := _required_atk_to_beat(strongest_player)
		if best_fusion_atk >= required_atk_to_win:
			return true
		elif best_hand_atk >= required_atk_to_win:
			return false
		else:
			return best_fusion_atk > best_hand_atk

	var fusion_threshold = max(best_hand_atk, 1200)
	return best_fusion_atk >= fusion_threshold

func _required_atk_to_beat(player_monster) -> int:
	var req := 0
	var in_def := bool(player_monster.get("in_defense"))
	if in_def:
		req = int(player_monster.get("def"))
	else:
		req = int(player_monster.get("atk"))
	return req + 100

func _fusion_probe(card1, card2):
	if fusion_manager == null:
		return null
	var fusion_service = fusion_manager.get("fusion")
	if fusion_service != null and fusion_service.has_method("find_generic_fusion"):
		return fusion_service.find_generic_fusion(card1, card2)
	var generic_db = fusion_manager.get("generic_db")
	if generic_db != null and generic_db.has_method("find_fusion"):
		return generic_db.find_fusion(card1, card2)
	return null

func find_best_possible_fusion_atk(monsters: Array) -> int:
	var best_atk := 0
	monsters.sort_custom(func(a, b): return int(a.get("atk")) < int(b.get("atk")))

	for i in range(monsters.size()):
		for j in range(i + 1, monsters.size()):
			var card1 = monsters[i]
			var card2 = monsters[j]
			var probe = _fusion_probe(card1, card2)
			if not is_instance_valid(probe):
				continue
			# Si es fusión, normalmente no devuelve card2.
			if probe != card2 and bool(probe.get("fusion_result")):
				best_atk = max(best_atk, int(probe.get("atk")))
				probe.queue_free()
			else:
				pass

	return best_atk

func find_best_monster_in_hand_atk(monsters: Array) -> int:
	var best := 0
	for m in monsters:
		best = max(best, int(m.get("atk")))
	return best

func find_best_fusion_combination(monsters: Array):
	var best_atk := 0
	var best_combo = null

	monsters.sort_custom(func(a, b): return int(a.get("atk")) < int(b.get("atk")))

	for i in range(monsters.size()):
		for j in range(i + 1, monsters.size()):
			var card1 = monsters[i]
			var card2 = monsters[j]
			var probe = _fusion_probe(card1, card2)
			if not is_instance_valid(probe):
				continue
			if probe != card2 and bool(probe.get("fusion_result")):
				var fusion_atk := int(probe.get("atk"))
				if fusion_atk > best_atk:
					best_atk = fusion_atk
					best_combo = [card1, card2]
				probe.queue_free()

	return best_combo

func try_generic_fusion() -> bool:
	if fusion_manager == null:
		return false
	if played_monster_card_this_turn:
		return false
	if _has_pending_fusion():
		return false
	if _get_free_slots("Opponent", "Monster").is_empty():
		return false

	var available_monsters := _get_opponent_hand_monsters()
	if available_monsters.size() < 2:
		return false

	var best_combo = find_best_fusion_combination(available_monsters)
	if best_combo == null:
		return false

	if fusion_manager.has_method("clear_materials"):
		fusion_manager.clear_materials()
	if fusion_manager.has_method("add_material"):
		fusion_manager.add_material(best_combo[0], "generic")
		fusion_manager.add_material(best_combo[1], "generic")

	if not fusion_manager.has_method("try_fusion"):
		return false

	var fusion_result = await fusion_manager.try_fusion("Opponent")
	if typeof(fusion_result) == TYPE_DICTIONARY and bool(fusion_result.get("success", false)):
		played_monster_card_this_turn = true
		return true
	return false

func place_pending_fusion() -> bool:
	if fusion_manager == null or not _has_pending_fusion():
		return false
	var slot = _pick_free_monster_slot_opponent()
	if slot == null:
		return false

	if not fusion_manager.has_method("place_fusion_card"):
		return false
	var placed = fusion_manager.place_fusion_card(slot)
	if placed:
		played_monster_card_this_turn = true
		var fusion_card = fusion_manager.get("pending_fusion_card")
		if is_instance_valid(fusion_card):
			_register_card_played_to_battle(fusion_card, "Opponent")
		return true
	return false

# ---------------------------
# Juego normal de monstruos
# ---------------------------

func play_optimal_monsters() -> void:
	if played_monster_card_this_turn:
		return
	if _has_pending_fusion():
		return

	var free_slots := _get_free_slots("Opponent", "Monster")
	if free_slots.is_empty():
		return

	var available_monsters := _get_opponent_hand_monsters()
	if available_monsters.is_empty():
		return

	available_monsters.sort_custom(func(a, b): return int(a.get("atk")) > int(b.get("atk")))
	var best_monster = available_monsters[0]
	await play_monster_to_field(best_monster)

func play_monster_to_field(monster) -> void:
	if not is_instance_valid(monster):
		return
	var slot = _pick_free_monster_slot_opponent()
	if slot == null:
		return

	if opponent_hand and opponent_hand.has_method("remove_card_from_hand"):
		opponent_hand.remove_card_from_hand(monster)

	if card_manager and card_manager.has_method("_place_card_in_slot"):
		card_manager._place_card_in_slot(monster, slot)
	else:
		slot.card_in_slot = true
		if monster.has_method("set_field_slot"):
			monster.set_field_slot(slot)
		if monster.has_method("set_show_back_only"):
			monster.set_show_back_only(false)
		if monster.has_method("set_face_down"):
			monster.set_face_down(true)

	_register_card_played_to_battle(monster, "Opponent")

	played_monster_card_this_turn = true
	await get_tree().process_frame

# ---------------------------
# Posicionamiento y ataques
# ---------------------------

func adjust_all_battle_positions() -> void:
	if not battle_manager:
		return

	var strongest_player_monster = get_strongest_player_monster()

	for card in battle_manager.opponent_cards_on_battlefield:
		if not is_instance_valid(card):
			continue

		var should_defend := false
		if battle_manager.player_cards_on_battlefield.size() == 0:
			should_defend = false
		elif is_instance_valid(strongest_player_monster):
			var can_destroy_any := false
			for player_monster in battle_manager.player_cards_on_battlefield:
				if is_instance_valid(player_monster) and can_destroy_target(card, player_monster):
					can_destroy_any = true
					break
			should_defend = not can_destroy_any

		var in_def := bool(card.get("in_defense"))
		if should_defend and not in_def:
			_set_position(card, "DEFENSE")
		elif not should_defend and in_def:
			_set_position(card, "ATTACK")

func _set_position(card, pos: String) -> void:
	if battle_manager and battle_manager.has_method("_set_position"):
		battle_manager._set_position(card, pos)
	else:
		if pos == "DEFENSE":
			card.in_defense = true
		elif pos == "ATTACK":
			card.in_defense = false

func can_destroy_target(attacker, target) -> bool:
	var target_def := bool(target.get("in_defense"))
	if target_def:
		return int(attacker.get("atk")) > int(target.get("def"))
	return int(attacker.get("atk")) >= int(target.get("atk"))

func find_optimal_target(attacker):
	if not battle_manager:
		return null
	var player_monsters = battle_manager.player_cards_on_battlefield.duplicate()
	player_monsters = player_monsters.filter(func(c): return is_instance_valid(c))
	if player_monsters.is_empty():
		return null

	var atk_list = player_monsters.filter(func(m): return not bool(m.get("in_defense")))
	var def_list = player_monsters.filter(func(m): return bool(m.get("in_defense")))

	atk_list.sort_custom(func(a, b): return int(a.get("atk")) > int(b.get("atk")))
	def_list.sort_custom(func(a, b): return int(a.get("def")) > int(b.get("def")))

	var sorted = atk_list + def_list
	for t in sorted:
		if can_destroy_target(attacker, t):
			return t
	return null

func execute_intelligent_attacks() -> void:
	if not battle_manager:
		return

	var attackers = battle_manager.opponent_cards_on_battlefield.duplicate()
	attackers = attackers.filter(func(c):
		return is_instance_valid(c) and not bool(c.get("in_defense")) and not battle_manager._has_kw(c, "PARALYZED")
	)
	attackers.sort_custom(func(a, b): return int(a.get("atk")) > int(b.get("atk")))

	for attacker in attackers:
		if battle_manager.player_cards_on_battlefield.size() == 0:
			await battle_manager.attack(attacker, null, "Opponent")
			await get_tree().process_frame
			continue

		var best_target = find_optimal_target(attacker)
		if best_target:
			await battle_manager.attack(attacker, best_target, "Opponent")
			await get_tree().process_frame

func get_strongest_player_monster():
	if not battle_manager:
		return null
	var player_monsters = battle_manager.player_cards_on_battlefield.duplicate()
	player_monsters = player_monsters.filter(func(c): return is_instance_valid(c))
	if player_monsters.is_empty():
		return null
	player_monsters.sort_custom(func(a, b): return int(a.get("atk")) > int(b.get("atk")))
	return player_monsters[0]

func _pick_free_spelltrap_slot_opponent():
	var free := _get_free_spelltrap_slots_opponent()
	if free.is_empty():
		return null
	return free[randi_range(0, free.size() - 1)]

func _get_free_spelltrap_slots_opponent() -> Array:
	var root := _slots_root_opponent
	if not is_instance_valid(root):
		return []

	var free: Array = []
	for child in root.get_children():
		if not is_instance_valid(child):
			continue

		var t := str(child.get("card_slot_type"))
		if t != "SpellTrap" and t != "Spell" and t != "Trap":
			continue

		var occupied := bool(child.get("card_in_slot"))
		if not occupied:
			free.append(child)

	return free

func _get_opponent_hand_spelltraps() -> Array:
	if not opponent_hand:
		return []

	var arr: Array = opponent_hand.get("opponent_hand")
	if arr == null:
		return []

	return arr.filter(func(c):
		return is_instance_valid(c) and (str(c.get("kind")).to_upper() == "SPELL" or str(c.get("kind")).to_upper() == "TRAP")
	)

#SPELLS/TRAPS

func play_one_spelltrap_set() -> void:
	if played_spellortrap_card_this_turn:
		return
	if not is_instance_valid(battle_manager):
		return

	var free_slot = _pick_free_spelltrap_slot_opponent()
	if free_slot == null:
		return

	var spelltraps := _get_opponent_hand_spelltraps()
	if spelltraps.is_empty():
		return

	var chosen = spelltraps[0]

	if opponent_hand and opponent_hand.has_method("remove_card_from_hand"):
		opponent_hand.remove_card_from_hand(chosen)

	if "owner_side" in chosen:
		chosen.owner_side = "OPPONENT"
	if chosen.has_method("apply_owner_collision_layers"):
		chosen.apply_owner_collision_layers()

	if battle_manager.has_method("_set_card_slot"):
		battle_manager._set_card_slot(chosen, free_slot)

	if battle_manager.has_method("_place_card_in_slot"):
		battle_manager._place_card_in_slot(chosen, free_slot)
	else:
		free_slot.card_in_slot = true
		if "card_ref" in free_slot:
			free_slot.card_ref = chosen
		if chosen.has_method("set_field_slot"):
			chosen.set_field_slot(free_slot)
		if chosen.has_method("set_show_back_only"):
			chosen.set_show_back_only(false)
		if chosen.has_method("set_face_down"):
			chosen.set_face_down(true)

	_register_card_played_to_battle(chosen, "Opponent")

	played_spellortrap_card_this_turn = true
	await get_tree().process_frame
