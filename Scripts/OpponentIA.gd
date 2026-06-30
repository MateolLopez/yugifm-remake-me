extends Node

const AI_NEG_INF := -1000000000
const AI_CARD_USE_COST := 350
const AI_PLAYER_THREAT_WEIGHT := 12
const AI_OWN_FIELD_WEIGHT := 8
const AI_DIRECT_DAMAGE_WEIGHT := 5

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

var max_fusion_materials: int = 3
var played_monster_card_this_turn: bool = false
var played_spellortrap_card_this_turn: bool = false
var ai_used_cards_this_turn: Array = []

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

	rule_service = battle_manager.get("rule_service")
	event_service = battle_manager.get("event_service")
	card_db_service = battle_manager.get("card_db_service")
	card_runtime_service = battle_manager.get("card_runtime_service")
	zone_service = battle_manager.get("zone_service")
	selection_service = battle_manager.get("selection_service")
	turn_service = battle_manager.get("turn_service")
	draw_service = battle_manager.get("draw_service")
	combat_service = battle_manager.get("combat_service")
	atk_state_service = battle_manager.get("atk_state_service")
	damage_service = battle_manager.get("damage_service")
	destruction_service = battle_manager.get("destruction_service")
	graveyard_service = battle_manager.get("graveyard_service")
	summon_service = battle_manager.get("summon_service")
	field_spell_service = battle_manager.get("field_spell_service")
	card_play_service = battle_manager.get("card_play_service")
	card_activation_service = battle_manager.get("card_activation_service")
	equip_service = battle_manager.get("equip_service")
	kw_service = battle_manager.get("kw_service")
	stat_service = battle_manager.get("stat_service")
	reveal_service = battle_manager.get("reveal_service")
	animation_service = battle_manager.get("animation_service")
	ui_service = battle_manager.get("ui_service")
	fusion_replacement_service = battle_manager.get("fusion_replacement_service")
	special_effect_service = battle_manager.get("special_effect_service")

func set_opponent_config(opponent_def: Dictionary) -> void:
	if opponent_def.is_empty():
		max_fusion_materials = 3
		return

	max_fusion_materials = max(2, int(opponent_def.get("max_fusion_materials", 3)))

func _ensure_refs() -> void:
	if battle_manager == null or zone_service == null or card_play_service == null:
		_setup_refs()


# -----------------------------------------------------------------------------
# Turn flow
# -----------------------------------------------------------------------------

func make_turn_decisions() -> void:
	_ensure_refs()

	if battle_manager == null:
		return

	reset_played_cards()

	# Compatibilidad con el flujo viejo, por si aún queda alguna fusión pendiente.
	if _has_pending_fusion():
		await place_pending_fusion()

	var plan := _build_turn_plan()
	await _execute_turn_plan(plan)


func reset_played_cards() -> void:
	played_monster_card_this_turn = false
	played_spellortrap_card_this_turn = false
	ai_used_cards_this_turn.clear()


# -----------------------------------------------------------------------------
# Plan builder
# -----------------------------------------------------------------------------

func _build_turn_plan() -> Dictionary:
	var base_state := _build_ai_state()
	var monster_action := _get_best_monster_action()
	var spell_actions := _get_ai_hand_action_spells()

	var best_plan := {
		"score": AI_NEG_INF,
		"pre_summon_spell": null,
		"post_attack_spell": null,
		"monster_action": monster_action,
		"debug": "no_spell"
	}

	# Plan 0: no gastar spell activable.
	var state_no_spell := _simulate_monster_action(base_state, monster_action)
	state_no_spell = _simulate_best_attacks(state_no_spell)
	var score_no_spell := _score_ai_state(state_no_spell)

	best_plan["score"] = score_no_spell

	for spell in spell_actions:
		if not is_instance_valid(spell):
			continue

		# Plan A: usar spell antes de invocar/atacar.
		var state_pre := _simulate_effect_card(base_state, spell, "Opponent")
		state_pre = _simulate_monster_action(state_pre, monster_action)
		state_pre = _simulate_best_attacks(state_pre)
		var score_pre := _score_ai_state(state_pre)

		if score_pre > int(best_plan.get("score", AI_NEG_INF)):
			best_plan = {
				"score": score_pre,
				"pre_summon_spell": spell,
				"post_attack_spell": null,
				"monster_action": monster_action,
				"debug": "pre_spell"
			}

		# Plan B: invocar/atacar primero, usar spell después.
		var state_post := _simulate_monster_action(base_state, monster_action)
		state_post = _simulate_best_attacks(state_post)
		state_post = _simulate_effect_card(state_post, spell, "Opponent")
		var score_post := _score_ai_state(state_post)

		if score_post > int(best_plan.get("score", AI_NEG_INF)):
			best_plan = {
				"score": score_post,
				"pre_summon_spell": null,
				"post_attack_spell": spell,
				"monster_action": monster_action,
				"debug": "post_spell"
			}

	return best_plan


func _execute_turn_plan(plan: Dictionary) -> void:
	var pre_spell = plan.get("pre_summon_spell", null)
	if is_instance_valid(pre_spell):
		await _ai_activate_spell_from_hand(pre_spell)

	var monster_action: Dictionary = plan.get("monster_action", {"type": "NONE"})
	await _execute_monster_action(monster_action)

	adjust_all_battle_positions()
	await execute_intelligent_attacks()

	var post_spell = plan.get("post_attack_spell", null)
	if is_instance_valid(post_spell):
		await _ai_activate_spell_from_hand(post_spell)

	await play_one_spelltrap_set()


func _execute_monster_action(action: Dictionary) -> void:
	if played_monster_card_this_turn:
		return

	match str(action.get("type", "NONE")):
		"FUSION_GENERIC":
			var combo = action.get("combo", null)

			if combo is Array and combo.size() >= 2:
				if fusion_manager.has_method("clear_materials"):
					fusion_manager.clear_materials()

				if fusion_manager.has_method("add_material"):
					for material in combo:
						if is_instance_valid(material):
							fusion_manager.add_material(material, "generic", "Opponent")

				if fusion_manager.has_method("try_fusion"):
					var fusion_result = await fusion_manager.try_fusion("Opponent")

					if typeof(fusion_result) == TYPE_DICTIONARY and bool(fusion_result.get("success", false)):
						played_monster_card_this_turn = true

		"NORMAL":
			var card = action.get("card", null)
			if is_instance_valid(card):
				await play_monster_to_field(card)

		_:
			return


# -----------------------------------------------------------------------------
# Hand helpers
# -----------------------------------------------------------------------------

func _get_opponent_hand_cards() -> Array:
	if not opponent_hand:
		return []

	var arr = opponent_hand.get("opponent_hand")
	if arr == null or not (arr is Array):
		return []

	return (arr as Array).filter(func(c):
		return is_instance_valid(c)
	)


func _get_opponent_hand_monsters() -> Array:
	return _get_opponent_hand_cards().filter(func(c):
		return str(c.get("kind")).to_upper() == "MONSTER"
	)

func _get_opponent_field_monsters() -> Array:
	if battle_manager == null:
		return []

	return battle_manager.opponent_cards_on_battlefield.filter(func(c):
		return is_instance_valid(c) and str(c.get("kind")).to_upper() == "MONSTER"
	)


func _get_opponent_fusion_materials() -> Array:
	var materials: Array = []

	for c in _get_opponent_hand_monsters():
		if is_instance_valid(c):
			materials.append(c)

	for c in _get_opponent_field_monsters():
		if is_instance_valid(c):
			materials.append(c)

	return materials


func _combo_uses_field_material(combo) -> bool:
	if not (combo is Array):
		return false

	for c in combo:
		if is_instance_valid(c) and _is_opponent_field_monster(c):
			return true

	return false


func _is_opponent_field_monster(card: Node) -> bool:
	if not is_instance_valid(card):
		return false

	if battle_manager == null:
		return false

	return card in battle_manager.opponent_cards_on_battlefield

func _get_opponent_hand_spelltraps() -> Array:
	return _get_opponent_hand_cards().filter(func(c):
		var k := str(c.get("kind")).to_upper()
		return k == "SPELL" or k == "TRAP"
	)


func _opponent_hand_has_card(card: Node) -> bool:
	if not opponent_hand:
		return false

	var arr = opponent_hand.get("opponent_hand")
	if arr == null or not (arr is Array):
		return false

	return (arr as Array).has(card)


# -----------------------------------------------------------------------------
# Slots
# -----------------------------------------------------------------------------

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


# -----------------------------------------------------------------------------
# Monster action evaluation
# -----------------------------------------------------------------------------

func _get_best_monster_action() -> Dictionary:
	if played_monster_card_this_turn:
		return {"type": "NONE"}

	var free_monster_slots := _get_free_slots("Opponent", "Monster")
	var has_free_monster_slot := not free_monster_slots.is_empty()

	var hand_monsters := _get_opponent_hand_monsters()
	var fusion_materials := _get_opponent_fusion_materials()

	var best_normal = null
	var best_normal_atk := 0

	# Normal summon: solo desde mano y solo si hay slot libre.
	if has_free_monster_slot:
		for m in hand_monsters:
			var m_atk := _atk(m)
			if m_atk > best_normal_atk:
				best_normal_atk = m_atk
				best_normal = m

	var best_combo = null
	var best_fusion_atk := 0
	var best_fusion_def := 0
	var best_fusion_uses_field := false
	var best_fusion_name := ""

	var best_sequence := {}

	if fusion_materials.size() >= 2:
		best_sequence = find_best_fusion_sequence(fusion_materials, max_fusion_materials)

	if not best_sequence.is_empty():
		best_combo = best_sequence.get("combo", [])
		best_fusion_uses_field = _combo_uses_field_material(best_combo)

		# Si no hay slot libre y la fusión no usa campo, no puede colocar resultado.
		if has_free_monster_slot or best_fusion_uses_field:
			best_fusion_atk = int(best_sequence.get("estimated_atk", 0))
			best_fusion_def = int(best_sequence.get("estimated_def", 0))
			best_fusion_name = str(best_sequence.get("estimated_name", ""))
		else:
			best_combo = null
			best_fusion_atk = 0
			best_fusion_def = 0
			best_fusion_name = ""

	if best_combo != null and best_fusion_atk > best_normal_atk:
		return {
			"type": "FUSION_GENERIC",
			"combo": best_combo,
			"estimated_atk": best_fusion_atk,
			"estimated_def": best_fusion_def,
			"estimated_name": best_fusion_name,
			"uses_field_material": best_fusion_uses_field
		}

	if is_instance_valid(best_normal):
		return {
			"type": "NORMAL",
			"card": best_normal,
			"estimated_atk": best_normal_atk
		}

	return {"type": "NONE"}

# -----------------------------------------------------------------------------
# Spell/effect action evaluation
# -----------------------------------------------------------------------------

func _get_ai_hand_action_spells() -> Array:
	var out: Array = []

	for c in _get_opponent_hand_cards():
		if not is_instance_valid(c):
			continue

		if ai_used_cards_this_turn.has(c):
			continue

		if str(c.get("kind")).to_upper() != "SPELL":
			continue

		var role := _ai_get_card_effect_role(c)
		if role == "REMOVAL" or role == "STAT_MOD" or role == "BURN":
			out.append(c)

	return out


func _ai_get_card_effect_role(card: Node) -> String:
	for effect_def in _get_activation_effects(card):
		var template := str(effect_def.get("template", ""))

		match template:
			"destroy_by_effect", "destroy_target", "destroy_all_matching", "destroy_all_others_monsters":
				return "REMOVAL"

			"debuff_opponent_monsters_conditional_field", "modify_self_stats", "graveyard_count_stat_buff_while_source_faceup":
				return "STAT_MOD"

			"inflict_effect_damage", "burn_scaled_by_opponent_field_card_count", "inflict_effect_damage_scaled_by_race_on_field":
				return "BURN"

			"recover_lp":
				return "HEAL"

			"summon_random_from_db", "summon_multiple_random_from_db":
				return "SUMMON"

	return ""


func _get_activation_effects(card: Node) -> Array:
	if not is_instance_valid(card):
		return []

	var effects: Array = []

	if card.has_method("get_effects"):
		effects = card.get_effects()
	elif "effects" in card and typeof(card.effects) == TYPE_ARRAY:
		effects = card.effects

	return effects.filter(func(e):
		return e is Dictionary and str(e.get("trigger", "")).to_upper() == "ON_ACTIVATE"
	)


func _ai_activate_spell_from_hand(spell_card: Node) -> bool:
	if not is_instance_valid(spell_card):
		return false

	if played_spellortrap_card_this_turn:
		return false

	if card_activation_service == null:
		return false

	var was_in_hand := _opponent_hand_has_card(spell_card)
	var result = null
	var called := false

	if card_activation_service.has_method("try_activate_from_hand_for_owner"):
		called = true
		result = await card_activation_service.try_activate_from_hand_for_owner(spell_card, "Opponent")
	elif card_activation_service.has_method("activate_from_hand_for_owner"):
		called = true
		result = await card_activation_service.activate_from_hand_for_owner(spell_card, "Opponent")
	elif card_activation_service.has_method("try_activate_card_for_owner"):
		called = true
		result = await card_activation_service.try_activate_card_for_owner(spell_card, "Opponent")
	elif card_activation_service.has_method("try_activate_from_hand"):
		# Fallback. Puede no servir si el método bloquea durante turno del oponente.
		called = true
		result = await card_activation_service.try_activate_from_hand(spell_card)

	if not called:
		return false

	var ok := false

	if typeof(result) == TYPE_BOOL:
		ok = bool(result)
	else:
		# Si el método viejo retorna void, inferimos éxito si salió de la mano o fue liberada.
		ok = was_in_hand and (not is_instance_valid(spell_card) or not _opponent_hand_has_card(spell_card))

	if ok:
		played_spellortrap_card_this_turn = true
		ai_used_cards_this_turn.append(spell_card)

	return ok


# -----------------------------------------------------------------------------
# Simulation model
# -----------------------------------------------------------------------------

func _build_ai_state() -> Dictionary:
	return {
		"player_monsters": _snapshot_monsters(battle_manager.player_cards_on_battlefield),
		"opponent_monsters": _snapshot_monsters(battle_manager.opponent_cards_on_battlefield),
		"used_spell": null,
		"damage_to_player": 0,
		"damage_to_opponent": 0
	}


func _snapshot_monsters(cards: Array) -> Array:
	var out: Array = []

	for c in cards:
		if is_instance_valid(c):
			out.append(_snapshot_monster(c))

	return out


func _snapshot_monster(card: Node) -> Dictionary:
	return {
		"ref": card,
		"atk": _atk(card),
		"def": _def(card),
		"in_defense": bool(card.get("in_defense")),
		"face_down": bool(card.get("face_down")) if ("face_down" in card) else false,
		"cardname": str(card.get("cardname")) if ("cardname" in card) else ""
	}

func _simulate_monster_action(state: Dictionary, action: Dictionary) -> Dictionary:
	var next_state := state.duplicate(true)

	match str(action.get("type", "NONE")):
		"NORMAL":
			var card = action.get("card", null)
			if is_instance_valid(card):
				next_state["opponent_monsters"].append(_snapshot_monster(card))

		"FUSION_GENERIC":
			var combo = action.get("combo", [])
			if combo is Array:
				next_state = _simulate_remove_opponent_field_materials(next_state, combo)

			next_state["opponent_monsters"].append({
				"ref": null,
				"atk": int(action.get("estimated_atk", 0)),
				"def": int(action.get("estimated_def", 0)),
				"in_defense": false,
				"face_down": false,
				"cardname": "Estimated Fusion"
			})

	return next_state


func _simulate_remove_opponent_field_materials(state: Dictionary, combo: Array) -> Dictionary:
	var next_state := state.duplicate(true)
	var monsters: Array = next_state.get("opponent_monsters", [])

	for material in combo:
		if not is_instance_valid(material):
			continue

		if not _is_opponent_field_monster(material):
			continue

		for i in range(monsters.size() - 1, -1, -1):
			var snap: Dictionary = monsters[i]
			if snap.get("ref", null) == material:
				monsters.remove_at(i)
				break

	next_state["opponent_monsters"] = monsters
	return next_state

func _simulate_effect_card(state: Dictionary, card: Node, acting_side: String) -> Dictionary:
	var next_state := state.duplicate(true)

	for effect_def in _get_activation_effects(card):
		var template := str(effect_def.get("template", ""))

		match template:
			"destroy_by_effect":
				next_state = _simulate_destroy_by_effect(next_state, card, acting_side, effect_def)

			"inflict_effect_damage":
				next_state = _simulate_inflict_effect_damage(next_state, card, acting_side, effect_def)

			_:
				# Template desconocido para la IA: no se simula.
				pass

	return next_state


func _simulate_destroy_by_effect(state: Dictionary, card: Node, acting_side: String, effect_def: Dictionary) -> Dictionary:
	var next_state := state.duplicate(true)
	var params: Dictionary = effect_def.get("params", {})

	var target_side := str(params.get("target_side", "OPPONENT")).to_upper()
	var choose := str(params.get("choose", "RANDOM")).to_upper()
	var count = max(1, int(params.get("count", 1)))
	var faceup_only := bool(params.get("faceup_only", false))

	var target_array_name := ""

	if target_side == "OPPONENT":
		target_array_name = "player_monsters" if acting_side == "Opponent" else "opponent_monsters"
	elif target_side == "SELF" or target_side == "OWNER":
		target_array_name = "opponent_monsters" if acting_side == "Opponent" else "player_monsters"
	elif target_side == "BOTH":
		# Para evitar sobreestimar cartas globales, se simula como si afectara a ambos lados
		# usando un tratamiento simple.
		var after_player := _simulate_destroy_from_array(next_state, "player_monsters", choose, count, faceup_only)
		var after_both := _simulate_destroy_from_array(after_player, "opponent_monsters", choose, count, faceup_only)
		after_both["used_spell"] = card
		return after_both
	else:
		return next_state

	if target_array_name == "":
		return next_state

	next_state = _simulate_destroy_from_array(next_state, target_array_name, choose, count, faceup_only)
	next_state["used_spell"] = card

	return next_state


func _simulate_destroy_from_array(state: Dictionary, array_name: String, choose: String, count: int, faceup_only: bool) -> Dictionary:
	var next_state := state.duplicate(true)
	var source_array: Array = next_state.get(array_name, [])
	var candidates: Array = source_array.duplicate()

	if faceup_only:
		candidates = candidates.filter(func(m):
			return not bool(m.get("face_down", false))
		)

	if candidates.is_empty():
		return next_state

	match choose:
		"LOWEST_ATK":
			candidates.sort_custom(func(a, b):
				return int(a.get("atk", 0)) < int(b.get("atk", 0))
			)
		"HIGHEST_ATK":
			candidates.sort_custom(func(a, b):
				return int(a.get("atk", 0)) > int(b.get("atk", 0))
			)
		"LOWEST_DEF":
			candidates.sort_custom(func(a, b):
				return int(a.get("def", 0)) < int(b.get("def", 0))
			)
		"HIGHEST_DEF":
			candidates.sort_custom(func(a, b):
				return int(a.get("def", 0)) > int(b.get("def", 0))
			)
		"HIGHEST_LEVEL", "LOWEST_LEVEL":
			# El snapshot actual no guarda level. Si luego lo necesitás, agregalo en _snapshot_monster.
			pass
		_:
			candidates.shuffle()

	var destroyed := candidates.slice(0, count)

	for d in destroyed:
		source_array.erase(d)

	next_state[array_name] = source_array
	return next_state


func _simulate_inflict_effect_damage(state: Dictionary, card: Node, acting_side: String, effect_def: Dictionary) -> Dictionary:
	var next_state := state.duplicate(true)
	var params: Dictionary = effect_def.get("params", {})

	var amount := int(params.get("amount", 0))
	var target := str(params.get("target", "OPPONENT")).to_upper()

	if amount <= 0:
		return next_state

	if target == "OPPONENT":
		if acting_side == "Opponent":
			next_state["damage_to_player"] = int(next_state.get("damage_to_player", 0)) + amount
		else:
			next_state["damage_to_opponent"] = int(next_state.get("damage_to_opponent", 0)) + amount
	elif target == "SELF":
		if acting_side == "Opponent":
			next_state["damage_to_opponent"] = int(next_state.get("damage_to_opponent", 0)) + amount
		else:
			next_state["damage_to_player"] = int(next_state.get("damage_to_player", 0)) + amount

	next_state["used_spell"] = card
	return next_state


func _simulate_best_attacks(state: Dictionary) -> Dictionary:
	var next_state := state.duplicate(true)
	var attackers: Array = next_state["opponent_monsters"].duplicate()
	var defenders: Array = next_state["player_monsters"]

	attackers.sort_custom(func(a, b):
		return int(a.get("atk", 0)) > int(b.get("atk", 0))
	)

	for attacker in attackers:
		if defenders.is_empty():
			next_state["damage_to_player"] = int(next_state.get("damage_to_player", 0)) + int(attacker.get("atk", 0))
			continue

		var best_target = _sim_find_best_attack_target(attacker, defenders)

		if best_target == null:
			continue

		if _sim_can_destroy(attacker, best_target):
			defenders.erase(best_target)

	next_state["player_monsters"] = defenders
	return next_state


func _sim_find_best_attack_target(attacker: Dictionary, defenders: Array):
	var killable := defenders.filter(func(d):
		return _sim_can_destroy(attacker, d)
	)

	if killable.is_empty():
		return null

	killable.sort_custom(func(a, b):
		return _sim_monster_threat_value(a) > _sim_monster_threat_value(b)
	)

	return killable[0]


func _sim_can_destroy(attacker: Dictionary, target: Dictionary) -> bool:
	var atk_value := int(attacker.get("atk", 0))

	if bool(target.get("in_defense", false)):
		return atk_value > int(target.get("def", 0))

	return atk_value >= int(target.get("atk", 0))


func _sim_monster_threat_value(monster: Dictionary) -> int:
	if bool(monster.get("in_defense", false)):
		return max(int(monster.get("atk", 0)), int(monster.get("def", 0)))

	return int(monster.get("atk", 0))


func _score_ai_state(state: Dictionary) -> int:
	var score := 0

	for m in state.get("opponent_monsters", []):
		score += _sim_monster_threat_value(m) * AI_OWN_FIELD_WEIGHT

	for m in state.get("player_monsters", []):
		score -= _sim_monster_threat_value(m) * AI_PLAYER_THREAT_WEIGHT

	score += int(state.get("damage_to_player", 0)) * AI_DIRECT_DAMAGE_WEIGHT
	score -= int(state.get("damage_to_opponent", 0)) * AI_DIRECT_DAMAGE_WEIGHT

	if state.get("used_spell", null) != null:
		score -= AI_CARD_USE_COST

	return score


# -----------------------------------------------------------------------------
# Fusion
# -----------------------------------------------------------------------------

func _has_pending_fusion() -> bool:
	if fusion_manager == null:
		return false

	if fusion_manager.has_method("has_pending_fusion"):
		return bool(fusion_manager.has_pending_fusion())

	if "pending_fusion_card" in fusion_manager:
		return is_instance_valid(fusion_manager.get("pending_fusion_card"))

	return false


func place_pending_fusion() -> void:
	if fusion_manager == null:
		return

	if not _has_pending_fusion():
		return

	if not fusion_manager.has_method("place_fusion_card"):
		return

	var free_slots := _get_free_slots("Opponent", "Monster")
	if free_slots.is_empty():
		return

	var slot = free_slots[0]
	var ok := bool(fusion_manager.place_fusion_card(slot))

	if ok:
		played_monster_card_this_turn = true


func evaluate_fusion_vs_normal_play() -> bool:
	if played_monster_card_this_turn:
		return false

	var action := _get_best_monster_action()
	return str(action.get("type", "")) == "FUSION_GENERIC"


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
	var best := find_best_fusion_sequence(monsters, max_fusion_materials)
	return int(best.get("estimated_atk", 0))



func find_best_monster_in_hand_atk(monsters: Array) -> int:
	var best := 0

	for m in monsters:
		best = max(best, _atk(m))

	return best

func find_best_fusion_combination(monsters: Array):
	var best := find_best_fusion_sequence(monsters, max_fusion_materials)

	if best.is_empty():
		return null

	var combo = best.get("combo", null)

	if combo is Array and combo.size() >= 2:
		return combo

	return null

func find_best_fusion_sequence(materials: Array, max_materials: int = 3) -> Dictionary:
	var valid_materials := []

	for c in materials:
		if is_instance_valid(c):
			valid_materials.append(c)

	if valid_materials.size() < 2:
		return {}

	max_materials = clamp(max_materials, 2, valid_materials.size())

	var best := {
		"combo": [],
		"estimated_atk": 0,
		"estimated_def": 0,
		"estimated_name": "",
		"material_count": 0
	}

	for start in valid_materials:
		var used := {}
		used[start.get_instance_id()] = true

		_search_fusion_sequence_recursive(
			start,
			[start],
			valid_materials,
			used,
			max_materials,
			best
		)

	if int(best.get("estimated_atk", 0)) <= 0:
		return {}

	return best


func _search_fusion_sequence_recursive(
	current_card: Node,
	sequence: Array,
	materials: Array,
	used: Dictionary,
	max_materials: int,
	best: Dictionary
) -> void:
	if sequence.size() >= max_materials:
		return

	for next_material in materials:
		if not is_instance_valid(next_material):
			continue

		var next_id = next_material.get_instance_id()

		if used.has(next_id):
			continue

		var result = _fusion_probe(current_card, next_material)

		if not is_instance_valid(result):
			continue

		var success := result != next_material and bool(result.get("fusion_result"))

		if not success:
			if result != next_material and is_instance_valid(result):
				result.queue_free()
			continue

		var new_sequence := sequence.duplicate()
		new_sequence.append(next_material)

		_register_best_fusion_sequence(best, new_sequence, result)

		used[next_id] = true

		_search_fusion_sequence_recursive(
			result,
			new_sequence,
			materials,
			used,
			max_materials,
			best
		)

		used.erase(next_id)

		if is_instance_valid(result):
			result.queue_free()


func _register_best_fusion_sequence(best: Dictionary, sequence: Array, result_card: Node) -> void:
	if not is_instance_valid(result_card):
		return

	var result_atk := _atk(result_card)
	var result_def := _def(result_card)
	var current_best_atk := int(best.get("estimated_atk", 0))
	var current_best_def := int(best.get("estimated_def", 0))
	var current_best_count := int(best.get("material_count", 999))

	var should_replace := false

	if result_atk > current_best_atk:
		should_replace = true
	elif result_atk == current_best_atk:
		if result_def > current_best_def:
			should_replace = true
		elif result_def == current_best_def and sequence.size() < current_best_count:
			should_replace = true

	if not should_replace:
		return

	best["combo"] = sequence.duplicate()
	best["estimated_atk"] = result_atk
	best["estimated_def"] = result_def
	best["estimated_name"] = str(result_card.get("cardname")) if ("cardname" in result_card) else ""
	best["material_count"] = sequence.size()

func try_generic_fusion() -> bool:
	if fusion_manager == null:
		return false

	if played_monster_card_this_turn:
		return false

	var available_materials := _get_opponent_fusion_materials()

	if available_materials.size() < 2:
		return false

	var best_sequence := find_best_fusion_sequence(available_materials, max_fusion_materials)

	if best_sequence.is_empty():
		return false

	var best_combo = best_sequence.get("combo", null)

	if not (best_combo is Array) or best_combo.size() < 2:
		return false

	if fusion_manager.has_method("clear_materials"):
		fusion_manager.clear_materials()

	if fusion_manager.has_method("add_material"):
		for material in best_combo:
			if is_instance_valid(material):
				fusion_manager.add_material(material, "generic", "Opponent")

	if not fusion_manager.has_method("try_fusion"):
		return false

	var fusion_result = await fusion_manager.try_fusion("Opponent")

	if typeof(fusion_result) == TYPE_DICTIONARY:
		return bool(fusion_result.get("success", false))

	return false

# -----------------------------------------------------------------------------
# Normal monster play
# -----------------------------------------------------------------------------

func play_optimal_monsters() -> void:
	var action := _get_best_monster_action()
	await _execute_monster_action(action)


func play_monster_to_field(monster) -> void:
	if not is_instance_valid(monster):
		return

	if card_play_service == null:
		return

	if not card_play_service.has_method("play_monster_from_hand_for_owner"):
		push_warning("OpponentIA: card_play_service no tiene play_monster_from_hand_for_owner.")
		return

	var played: bool = await card_play_service.play_monster_from_hand_for_owner(
		monster,
		"Opponent",
		"FACEDOWN_ATK"
	)

	if played:
		played_monster_card_this_turn = true

	await get_tree().process_frame


# -----------------------------------------------------------------------------
# Battle position and attacks
# -----------------------------------------------------------------------------

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


# -----------------------------------------------------------------------------
# Spell/trap setting
# -----------------------------------------------------------------------------

func play_one_spelltrap_set() -> void:
	if played_spellortrap_card_this_turn:
		return

	if card_play_service == null:
		return

	var spelltraps := _get_opponent_hand_spelltraps()
	spelltraps = spelltraps.filter(func(c):
		return is_instance_valid(c) and not ai_used_cards_this_turn.has(c)
	)

	if spelltraps.is_empty():
		return

	var free_slot = _pick_free_spelltrap_slot_opponent()
	if free_slot == null:
		return

	# Si hay trampa, prioriza setear trampa. Si no, setea una spell no usada.
	spelltraps.sort_custom(func(a, b):
		var ak := str(a.get("kind")).to_upper()
		var bk := str(b.get("kind")).to_upper()

		if ak == "TRAP" and bk != "TRAP":
			return true

		if ak != "TRAP" and bk == "TRAP":
			return false

		return false
	)

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


# -----------------------------------------------------------------------------
# Generic card value helpers
# -----------------------------------------------------------------------------

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
