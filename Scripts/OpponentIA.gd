extends Node

var fusion_manager: Node
var battle_manager: Node
var opponent_hand: Node
var card_manager: Node

var rule_service: Node
var event_service: Node
var card_db_service: Node
var card_runtime_service: Node
var zone_service: Node
var selection_service: Node
var turn_service: Node
var draw_service: Node
var combat_service: Node
var atk_state_service: Node
var damage_service: Node
var destruction_service: Node
var graveyard_service: Node
var summon_service: Node
var field_spell_service: Node
var card_play_service: Node
var card_activation_service: Node
var equip_service: Node
var kw_service: Node
var stat_service: Node
var reveal_service: Node
var animation_service: Node
var ui_service: Node
var fusion_replacement_service: Node
var special_effect_service: Node

var played_monster_card_this_turn: bool = false
var played_spellortrap_card_this_turn: bool = false

@onready var _slots_root_opponent: Node = get_node_or_null("../CardSlotsRival")
@onready var _slots_root_player: Node = get_node_or_null("../CardSlots")

func _ready() -> void:
	call_deferred("_setup_refs")


func _setup_refs() -> void:
	fusion_manager = get_node_or_null("../FusionManager")
	battle_manager = get_node_or_null("../BattleManager")
	opponent_hand = get_node_or_null("../OpponentHand")
	card_manager = get_node_or_null("../CardManager")

	if battle_manager == null:
		return

	rule_service = battle_manager.rule_service
	event_service = battle_manager.event_service
	card_db_service = battle_manager.card_db_service
	card_runtime_service = battle_manager.card_runtime_service
	zone_service = battle_manager.zone_service
	selection_service = battle_manager.selection_service
	turn_service = battle_manager.turn_service
	draw_service = battle_manager.draw_service
	combat_service = battle_manager.combat_service
	atk_state_service = battle_manager.atk_state_service
	damage_service = battle_manager.damage_service
	destruction_service = battle_manager.destruction_service
	graveyard_service = battle_manager.graveyard_service
	summon_service = battle_manager.summon_service
	field_spell_service = battle_manager.field_spell_service
	card_play_service = battle_manager.card_play_service
	card_activation_service = battle_manager.card_activation_service
	equip_service = battle_manager.equip_service
	kw_service = battle_manager.kw_service
	stat_service = battle_manager.stat_service
	reveal_service = battle_manager.reveal_service
	animation_service = battle_manager.animation_service
	ui_service = battle_manager.ui_service
	fusion_replacement_service = battle_manager.fusion_replacement_service
	special_effect_service = battle_manager.special_effect_service


func _ensure_refs() -> void:
	if battle_manager == null or zone_service == null or card_play_service == null:
		_setup_refs()

func make_turn_decisions() -> void:
	_ensure_refs()

	if battle_manager == null:
		return

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

func _get_opponent_hand_monsters() -> Array:
	if not opponent_hand:
		return []
	var arr: Array = opponent_hand.get("opponent_hand")
	if arr == null:
		return []
	return arr.filter(func(c):
		return is_instance_valid(c) and str(c.get("kind")).to_upper() == "MONSTER"
	)

func _get_free_slots(side: String, slot_type: String) -> Array:
	if zone_service != null:
		if zone_service.has_method("get_free_slots_for"):
			return zone_service.get_free_slots_for(side, slot_type)

		if zone_service.has_method("_get_free_slots_for"):
			return zone_service._get_free_slots_for(side, slot_type)

	var root := _slots_root_player if side == "Player" else _slots_root_opponent
	if not is_instance_valid(root):
		return []

	var free: Array = []

	for child in root.get_children():
		if not is_instance_valid(child):
			continue

		var t := str(child.get("card_slot_type"))

		if slot_type == "SpellTrap":
			if t != "SpellTrap" and t != "Spell" and t != "Trap":
				continue
		elif t != slot_type:
			continue

		if not bool(child.get("card_in_slot")):
			free.append(child)

	return free


func _pick_free_monster_slot_opponent():
	if zone_service != null:
		if zone_service.has_method("pick_free_monster_slot_for"):
			return zone_service.pick_free_monster_slot_for("Opponent")

		if zone_service.has_method("_get_free_monster_slot_for"):
			return zone_service._get_free_monster_slot_for("Opponent")

	var free := _get_free_slots("Opponent", "Monster")
	if free.is_empty():
		return null

	return free[randi_range(0, free.size() - 1)]

func _pick_free_spelltrap_slot_opponent():
	if zone_service != null:
		if zone_service.has_method("pick_free_spelltrap_slot_for"):
			return zone_service.pick_free_spelltrap_slot_for("Opponent")

		if zone_service.has_method("_get_free_spelltrap_slot_for"):
			return zone_service._get_free_spelltrap_slot_for("Opponent")

	var free := _get_free_slots("Opponent", "SpellTrap")
	if free.is_empty():
		return null

	return free[randi_range(0, free.size() - 1)]

# ---------------------------
# Fusión
# ---------------------------

func evaluate_fusion_vs_normal_play() -> bool:
	if played_monster_card_this_turn:
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
	if not is_instance_valid(player_monster):
		return 0

	var in_def := bool(player_monster.get("in_defense"))

	if in_def:
		return _def(player_monster) + 50

	return _atk(player_monster) + 50

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

	monsters.sort_custom(func(a, b):
		return _atk(a) < _atk(b)
	)

	for i in range(monsters.size()):
		for j in range(i + 1, monsters.size()):
			var card1 = monsters[i]
			var card2 = monsters[j]
			var probe = _fusion_probe(card1, card2)

			if not is_instance_valid(probe):
				continue

			if probe != card2 and bool(probe.get("fusion_result")):
				best_atk = max(best_atk, _atk(probe))
				probe.queue_free()

	return best_atk

func find_best_monster_in_hand_atk(monsters: Array) -> int:
	var best := 0

	for m in monsters:
		best = max(best, _atk(m))

	return best

func find_best_fusion_combination(monsters: Array):
	var best_atk := 0
	var best_combo = null

	monsters.sort_custom(func(a, b):
		return _atk(a) < _atk(b)
	)

	for i in range(monsters.size()):
		for j in range(i + 1, monsters.size()):
			var card1 = monsters[i]
			var card2 = monsters[j]
			var probe = _fusion_probe(card1, card2)

			if not is_instance_valid(probe):
				continue

			if probe != card2 and bool(probe.get("fusion_result")):
				var fusion_atk := _atk(probe)

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

	var available_monsters := _get_opponent_hand_monsters()
	if available_monsters.size() < 2:
		return false

	var best_combo = find_best_fusion_combination(available_monsters)
	if best_combo == null:
		return false

	if fusion_manager.has_method("clear_materials"):
		fusion_manager.clear_materials()

	if fusion_manager.has_method("add_material"):
		fusion_manager.add_material(best_combo[0], "generic", "Opponent")
		fusion_manager.add_material(best_combo[1], "generic", "Opponent")

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

	return placed
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

	available_monsters.sort_custom(func(a, b):
		return _atk(a) > _atk(b))
	var best_monster = available_monsters[0]
	await play_monster_to_field(best_monster)

func play_monster_to_field(monster) -> void:
	if not is_instance_valid(monster):
		return

	if card_play_service == null:
		return

	var played := false

	if card_play_service.has_method("play_monster_from_hand_for_owner"):
		played = await card_play_service.play_monster_from_hand_for_owner(
			monster,
			"Opponent",
			"FACEDOWN_ATK"
		)
	elif card_play_service.has_method("play_monster_from_hand"):
		played = await card_play_service.play_monster_from_hand(
			monster,
			"Opponent",
			"FACEDOWN_ATK"
		)

	if played:
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
	if not is_instance_valid(card):
		return

	if combat_service != null:
		if combat_service.has_method("set_position"):
			combat_service.set_position(card, pos)
			return

		if combat_service.has_method("_set_position"):
			combat_service._set_position(card, pos)
			return

	if pos == "DEFENSE":
		if card.has_method("set_defense_position"):
			card.set_defense_position(true)
		elif "in_defense" in card:
			card.in_defense = true

	elif pos == "ATTACK":
		if card.has_method("set_defense_position"):
			card.set_defense_position(false)
		elif "in_defense" in card:
			card.in_defense = false

func can_destroy_target(attacker, target) -> bool:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return false

	var target_def := bool(target.get("in_defense"))

	if target_def:
		return _atk(attacker) > _def(target)

	return _atk(attacker) >= _atk(target)


func find_optimal_target(attacker):
	if battle_manager == null:
		return null

	var player_monsters = battle_manager.player_cards_on_battlefield.duplicate()
	player_monsters = player_monsters.filter(func(c):
		return is_instance_valid(c)
	)

	if player_monsters.is_empty():
		return null

	var atk_list = player_monsters.filter(func(m):
		return not bool(m.get("in_defense"))
	)

	var def_list = player_monsters.filter(func(m):
		return bool(m.get("in_defense"))
	)

	atk_list.sort_custom(func(a, b):
		return _atk(a) > _atk(b)
	)

	def_list.sort_custom(func(a, b):
		return _def(a) > _def(b)
	)

	var sorted = atk_list + def_list

	for t in sorted:
		if can_destroy_target(attacker, t):
			return t

	return null

func get_strongest_player_monster():
	if battle_manager == null:
		return null

	var player_monsters = battle_manager.player_cards_on_battlefield.duplicate()
	player_monsters = player_monsters.filter(func(c):
		return is_instance_valid(c)
	)

	if player_monsters.is_empty():
		return null

	player_monsters.sort_custom(func(a, b):
		return _atk(a) > _atk(b)
	)

	return player_monsters[0]

func execute_intelligent_attacks() -> void:
	if battle_manager == null or combat_service == null:
		return

	var attackers = battle_manager.opponent_cards_on_battlefield.duplicate()

	attackers = attackers.filter(func(c):
		return is_instance_valid(c) and not bool(c.get("in_defense")) and not _has_keyword(c, "PARALYZED")
	)

	attackers.sort_custom(func(a, b):
		return _atk(a) > _atk(b)
	)

	for attacker in attackers:
		if not is_instance_valid(attacker):
			continue

		if battle_manager.player_cards_on_battlefield.size() == 0:
			if combat_service.has_method("attack"):
				await combat_service.attack(attacker, null, "Opponent")
			elif battle_manager.has_method("attack"):
				await battle_manager.attack(attacker, null, "Opponent")

			await get_tree().process_frame
			continue

		var best_target = find_optimal_target(attacker)

		if best_target:
			if combat_service.has_method("attack"):
				await combat_service.attack(attacker, best_target, "Opponent")
			elif battle_manager.has_method("attack"):
				await battle_manager.attack(attacker, best_target, "Opponent")

			await get_tree().process_frame

func _get_free_spelltrap_slots_opponent() -> Array:
	return _get_free_slots("Opponent", "SpellTrap")
	
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

	if card_play_service == null:
		return

	var spelltraps := _get_opponent_hand_spelltraps()
	if spelltraps.is_empty():
		return

	var free_slot = _pick_free_spelltrap_slot_opponent()
	if free_slot == null:
		return

	var chosen = spelltraps[0]
	var played := false

	if card_play_service.has_method("set_spelltrap_from_hand_for_owner"):
		played = await card_play_service.set_spelltrap_from_hand_for_owner(
			chosen,
			"Opponent",
			free_slot
		)
	elif card_play_service.has_method("set_spelltrap_from_hand"):
		played = await card_play_service.set_spelltrap_from_hand(
			chosen,
			"Opponent",
			free_slot
		)

	if played:
		played_spellortrap_card_this_turn = true

	await get_tree().process_frame
func try_play_highest_atk_card() -> void:
	if animation_service != null:
		if animation_service.has_method("is_duel_animating"):
			if animation_service.is_duel_animating():
				return
		elif animation_service.has_method("_is_duel_animating"):
			if animation_service._is_duel_animating():
				return

	await play_optimal_monsters()
func _has_keyword(card: Node, keyword: String) -> bool:
	if not is_instance_valid(card):
		return false

	if kw_service != null:
		if kw_service.has_method("has_kw"):
			return kw_service.has_kw(card, keyword)

		if kw_service.has_method("_has_kw"):
			return kw_service._has_kw(card, keyword)

	if card.has_method("has_keyword"):
		return card.has_keyword(keyword)

	if "keywords" in card and typeof(card.keywords) == TYPE_ARRAY:
		for k in card.keywords:
			if str(k).to_upper() == str(keyword).to_upper():
				return true

	return false


func _atk(card: Node) -> int:
	if not is_instance_valid(card):
		return 0

	if card.has_method("get_effective_atk"):
		return int(card.get_effective_atk())

	if "atk" in card:
		return int(card.atk)

	return 0


func _def(card: Node) -> int:
	if not is_instance_valid(card):
		return 0

	if card.has_method("get_effective_def"):
		return int(card.get_effective_def())

	if "def" in card:
		return int(card.def)

	return 0
