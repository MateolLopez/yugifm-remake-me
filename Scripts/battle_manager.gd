extends Node

const BATTLE_POSS_OFFSET = 25
const CARD_MOVE_SPEED = 0.2
const DEFAULT_MAX_HAND_SIZE = 5
const DEFAULT_STARTING_HP = 8000

signal duel_over(result: String)

var duel_finished = false
var battle_timer
var empty_monster_card_slots = []
var opponent_cards_on_battlefield = []
var player_cards_on_battlefield = []
var opponent_cards_that_attacked_this_turn = []
var player_cards_that_attacked_this_turn = []
var opponent_graveyard = []
var player_graveyard = []
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
var turn_index: int = 0

signal attack_declared(attacker, defender, attacker_owner)
signal monster_played(monster, cardowner)
signal spell_activated(spell, cardowner)
signal trap_activated(trap, cardowner)
signal turn_started(turn_owner)
signal turn_ended(turn_owner)


func _rules_value(key: String, fallback):
	var rules = get_node_or_null("/root/DuelRules")
	if rules:
		if rules.has_method("get_rule"):
			return rules.get_rule(key, fallback)
	var json_rules = null
	if "duel_rules" in self:
		json_rules = get("duel_rules")
	if json_rules is Dictionary and json_rules.has(key):
		return json_rules[key]
	return fallback

func _norm_owner(owner_value) -> String:
	var s := str(owner_value).strip_edges().to_upper()
	if s == "PLAYER":
		return "Player"
	if s == "OPPONENT":
		return "Opponent"
	return "Player" if str(owner_value) == "" else str(owner_value)

func _card_kind(card) -> String:
	if not is_instance_valid(card):
		return ""
	var k := ""
	if "kind" in card:
		k = str(card.kind)
	elif "card_type" in card:
		k = str(card.card_type)
	elif "attribute" in card:
		var a := str(card.attribute).to_lower()
		if a == "spell":
			k = "SPELL"
		elif a == "trap":
			k = "TRAP"
	return k.to_upper()

func _card_name(card) -> String:
	if not is_instance_valid(card):
		return "<null>"
	if "cardname" in card and str(card.cardname) != "":
		return str(card.cardname)
	if "card_name" in card:
		return str(card.card_name)
	return str(card.name)

func _card_owner_side(card) -> String:
	if not is_instance_valid(card):
		return ""
	if "owner_side" in card:
		return _norm_owner(card.owner_side)
	if "card_owner" in card:
		return _norm_owner(card.card_owner)
	return ""

func _set_card_owner_side(card, cardowner: String) -> void:
	if not is_instance_valid(card):
		return
	var upper_owner := cardowner.to_upper()
	if "owner_side" in card:
		card.owner_side = upper_owner
	elif "card_owner" in card:
		card.card_owner = cardowner

func _is_card_face_down(card) -> bool:
	if not is_instance_valid(card):
		return false
	if "face_down" in card:
		return bool(card.face_down)
	if "is_facedown" in card:
		return bool(card.is_facedown)
	return false

func _set_card_face_down(card, value: bool) -> void:
	if not is_instance_valid(card):
		return
	if card.has_method("set_face_down"):
		card.set_face_down(value)
	elif card.has_method("set_facedown"):
		card.set_facedown(value)
	elif "face_down" in card:
		card.face_down = value
	elif "is_facedown" in card:
		card.is_facedown = value

func _card_slot(card):
	if not is_instance_valid(card):
		return null
	if "current_slot" in card:
		return card.current_slot
	if "card_slot_card_is_in" in card:
		return card.card_slot_card_is_in
	return null

func _set_card_slot(card, slot) -> void:
	if not is_instance_valid(card):
		return
	if card.has_method("set_field_slot"):
		card.set_field_slot(slot)
	else:
		if "current_slot" in card:
			card.current_slot = slot
		if "card_slot_card_is_in" in card:
			card.card_slot_card_is_in = slot

func _clear_card_slot(card) -> void:
	if not is_instance_valid(card):
		return
	if card.has_method("clear_field_slot"):
		card.clear_field_slot()
	else:
		if "current_slot" in card:
			card.current_slot = null
		if "card_slot_card_is_in" in card:
			card.card_slot_card_is_in = null

func _max_hand_size() -> int:
	return int(_rules_value("max_hand_size", DEFAULT_MAX_HAND_SIZE))

func _starting_hp() -> int:
	return int(_rules_value("starting_hp", DEFAULT_STARTING_HP))

func _ready() -> void:
	add_to_group("battle_manager")
	battle_timer = $"../BattleTimer"
	battle_timer.one_shot = true
	battle_timer.wait_time = 0.5

	empty_monster_card_slots.append($"../CardSlotsRival/CardSlot")
	empty_monster_card_slots.append($"../CardSlotsRival/CardSlot2")
	empty_monster_card_slots.append($"../CardSlotsRival/CardSlot3")
	empty_monster_card_slots.append($"../CardSlotsRival/CardSlot4")
	empty_monster_card_slots.append($"../CardSlotsRival/CardSlot5")
	
	player_hp = _starting_hp()
	$"../PlayerHP".text = str(player_hp)
	opponent_hp = _starting_hp()
	$"../OpponentHP".text = str(opponent_hp)

func _clear_multi_for(card):
	multi_mode.erase(card)
	multi_remaining.erase(card)
	multi_already_attacked.erase(card)

func _cleanup_multi_garbage():
	for k in multi_mode.keys():
		if not is_instance_valid(k) or (k not in player_cards_on_battlefield and k not in opponent_cards_on_battlefield):
			_clear_multi_for(k)

func _on_end_turn_button_pressed() -> void:
	_emit_duel_event("TURN_END", {"turn_owner":"Player", "controller":"Player", "battle_manager": self})
	_process_scheduled_destruction_on_turn_end("Player")
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
	turn_index += 1
	_emit_duel_event("TURN_START", {"turn_owner":"Opponent", "controller":"Opponent", "battle_manager": self})
	if duel_finished: return
	$"../EndTurnButton".disabled = true
	$"../EndTurnButton".visible = false
	
	await yield_to_refill_opponent_hand()
	await action_waiter()
	var opponent_ia = $"../OpponentIA"
	if opponent_ia:
		await opponent_ia.make_turn_decisions()
		await action_waiter()
	
	opponent_cards_that_attacked_this_turn = []
	await end_opponent_turn()

func _set_position(card: Card, pos: String) -> bool:
	if not is_instance_valid(card):
		return false
	if not card.is_on_field():
		return false

	var cardowner := _norm_owner(_owner_of(card))

	if cardowner == "Player":
		if card in player_cards_that_attacked_this_turn:
			return false
	else:
		if card in opponent_cards_that_attacked_this_turn:
			return false

	var want_def := (pos.to_upper() == "DEFENSE")
	if card.has_method("set_defense_position"):
		card.set_defense_position(want_def)
	else:
		card.in_defense = want_def

	_emit_duel_event("ON_CHANGE_POSITION", {
		"battle_manager": self,
		"source": card,
		"controller": cardowner,
		"to_defense": want_def,
		"turn_owner": ("Opponent" if is_opponent_turn else "Player")
	})
	return true

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
	if not is_instance_valid(card):
		return
	_trigger_on_play_effects(card, who)

func attack(atk_card, defending, attacker):

	if _card_kind(atk_card) != "MONSTER":
		return
	if duel_finished: return
	if not is_instance_valid(atk_card):
		return

	var battle_ctx := {
		"battle_manager": self,
		"source": atk_card,
		"attacker": atk_card,
		"defender": defending,
		"attacker_owner": attacker,
		"controller": attacker,
		"turn_owner": ("Opponent" if is_opponent_turn else "Player"),
		"prevent_attack": false,
		"attack_negated": false
	}
	emit_signal("attack_declared", atk_card, defending, attacker)
	_emit_duel_event("ON_ATTACK_DECLARATION", battle_ctx)
	
	if bool(battle_ctx.get("prevent_attack", false)) or bool(battle_ctx.get("attack_negated", false)):
		if attacker == "Player":
			$"../InputManager".inputs_disabled = false
			enable_end_turn_button(true)
		return
	
	if atk_card.has_meta("only_direct_attack") and atk_card.get_meta("only_direct_attack"):
		if is_instance_valid(defending):
			return
		else:
			await direct_attack(atk_card, attacker)
			return
	
	if not is_instance_valid(defending):
		if attacker == "Opponent":
			var defenders := player_cards_on_battlefield.filter(func(c):
				return is_instance_valid(c) and _card_kind(c) == "MONSTER"
			)
			if defenders.is_empty():
				await direct_attack(atk_card, "Opponent")
		else:
			$"../InputManager".inputs_disabled = false
			enable_end_turn_button(true)
		return

	reveal_card(atk_card)
	reveal_card(defending)

	if attacker == "Player":
				$"../CardManager".selected_monster = null

	await _trigger_on_attack_effects(atk_card, attacker, battle_ctx)

	if not is_instance_valid(atk_card):
		if attacker == "Player":
			$"../InputManager".inputs_disabled = false
			enable_end_turn_button(true)
		return
	if not is_instance_valid(defending):
		if attacker == "Opponent":
			var live_defenders2 = _live_defenders_for("Player")
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

	var temp_atk_atk = atk_card.atk + int(gs_bonus.attacker_atk)
	var temp_def_atk = defending.atk + int(gs_bonus.defender_atk)
	var temp_def_def = defending.def + int(gs_bonus.defender_def)

	atk_card.z_index = 5
	var target_pos: Vector2 = _anchored_target_position(atk_card, defending, BATTLE_POSS_OFFSET)
	var t := get_tree().create_tween()
	t.tween_property(atk_card, "global_position", target_pos, CARD_MOVE_SPEED)
	await action_waiter()

	if defending.in_defense:
		await _handle_defense_attack(atk_card, defending, attacker, temp_atk_atk, temp_def_def)
	else:
		await _handle_attack_attack(atk_card, defending, attacker, temp_atk_atk, temp_def_atk)

func _trigger_on_attack_effects(_card, _who: String, _ctx: Dictionary) -> void:
	return

func _place_card_in_slot(card: Node2D, slot: Node2D) -> void:
	if not is_instance_valid(card) or not is_instance_valid(slot):
		return
	var cardowner := _card_owner_side(card)
	var kind := _card_kind(card)

	_set_card_slot(card, slot)
	slot.card_in_slot = true
	if "card_ref" in slot:
		slot.card_ref = card

	var should_reveal := false
	if kind == "TRAP":
		_set_card_face_down(card, true)
		should_reveal = false
	elif kind == "SPELL":
		if _has_immediate_effect(card):
			_set_card_face_down(card, false)
			should_reveal = true
		else:
			_set_card_face_down(card, true)
	else:
		# Monstruo
		if bool(card.get("fusion_result")) or _has_immediate_effect(card):
			_set_card_face_down(card, false)
			should_reveal = true
		else:
			_set_card_face_down(card, true)

	if card.has_method("set_show_back_only"):
		card.set_show_back_only(false)
	if card.has_method("move_to_zone"):
		card.move_to_zone("FIELD")
	var cm = get_node_or_null("../CardManager")
	if cm:
		card.scale = Vector2(cm.FIELD_SCALE, cm.FIELD_SCALE)
		cm._snap_card_to_slot_center(card, slot)
	card.z_index = -4

	if kind == "MONSTER":
		var arr = (player_cards_on_battlefield if cardowner == "Player" else opponent_cards_on_battlefield)
		if not arr.has(card):
			arr.append(card)

	_register_card_with_effect_engine(card, cardowner)

	match kind:
		"MONSTER":
			emit_signal("monster_played", card, cardowner)
		"SPELL":
			emit_signal("spell_activated", card, cardowner)
		"TRAP":
			emit_signal("trap_activated", card, cardowner)
	if kind == "SPELL" or kind == "TRAP":
		var cm_track := get_node_or_null("../CardManager")
		if cm_track:
			if "played_spellortrap_card_this_turn" in cm_track:
				cm_track.played_spellortrap_card_this_turn = true

	if kind == "MONSTER":
		_emit_duel_event("ON_PLAY", {"battle_manager": self, "source": card, "controller": cardowner, "turn_owner": ("Opponent" if is_opponent_turn else "Player")})
	elif kind == "TRAP":
		_emit_duel_event("ON_PLAY", {"battle_manager": self, "source": card, "controller": cardowner, "turn_owner": ("Opponent" if is_opponent_turn else "Player")})
	elif kind == "SPELL" and should_reveal:
		start_spell_activation(card, cardowner)
		return

	if should_reveal:
		reveal_card(card)
		if kind == "MONSTER":
			_trigger_on_play_effects(card, cardowner)

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

func _trigger_on_play_effects(card, card_owner: String) -> void:
	if not is_instance_valid(card):
		return
	_register_card_with_effect_engine(card, card_owner)
	_emit_duel_event("ON_PLAY", {
		"battle_manager": self,
		"source": card,
		"controller": card_owner,
		"turn_owner": ("Opponent" if is_opponent_turn else "Player")
	})

func _handle_defense_attack(atk_card, defending, attacker, atk_power, def_power):
	var defender_owner := ("Opponent" if attacker == "Player" else "Player")
	var result_str = "lose"

	var has_piercing = atk_card.get_meta("piercing_damage", false)

	if atk_power > def_power:
		destroy_card(defending, defender_owner, "DESTROY_BATTLE")
		result_str = "win"
	elif atk_power == def_power:
		result_str = "tie"
	else:
		var diff = def_power - atk_power
		if attacker == "Opponent":
			_apply_battle_damage_to_side("Opponent", diff, defending, atk_card)
		else:
			_apply_battle_damage_to_side("Player", diff, defending, atk_card)

	if has_piercing and atk_power > def_power:
		var piercing_damage = atk_power - def_power
		if attacker == "Opponent":
			_apply_battle_damage_to_side("Player", piercing_damage, atk_card, defending)
		else:
			_apply_battle_damage_to_side("Opponent", piercing_damage, atk_card, defending)

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

	if attacker == "Player":
		if not (atk_card in player_cards_that_attacked_this_turn):
			player_cards_that_attacked_this_turn.append(atk_card)
		_enable_player_input()
	else:
		if not (atk_card in opponent_cards_that_attacked_this_turn):
			opponent_cards_that_attacked_this_turn.append(atk_card)

func _handle_attack_attack(atk_card, defending, _attacker, atk_power, def_power) -> void:
	var attacker_owner: String = _norm_owner(_owner_of(atk_card)) # "Player"/"Opponent"
	var defender_owner: String = _norm_owner(_owner_of(defending))

	var atk_i: int = int(atk_power)
	var def_i: int = int(def_power)

	if atk_i == def_i:
		destroy_card_tie(atk_card, defending)
		await _trigger_on_attack(atk_card, attacker_owner, {
			"phase": "after_damage",
			"attacker": atk_card,
			"defender": defending,
			"result": "tie"
		})
		_clear_bonuses([atk_card, defending])

		if attacker_owner == "Player":
			if not (atk_card in player_cards_that_attacked_this_turn):
				player_cards_that_attacked_this_turn.append(atk_card)
			_enable_player_input()
		else:
			if not (atk_card in opponent_cards_that_attacked_this_turn):
				opponent_cards_that_attacked_this_turn.append(atk_card)
		return

	var attacker_won: bool = atk_i > def_i
	var damage: int = abs(atk_i - def_i)

	if attacker_won:
		_apply_battle_damage_to_side(defender_owner, damage, atk_card, defending)
		destroy_card(defending, defender_owner, "DESTROY_BATTLE")
	else:
		_apply_battle_damage_to_side(attacker_owner, damage, atk_card, defending)
		destroy_card(atk_card, attacker_owner, "DESTROY_BATTLE")

	if not _is_card_alive(atk_card):
		_clear_bonuses([atk_card, defending])
		if attacker_owner == "Player":
			_enable_player_input()
		return

	var return_pos2: Vector2 = _anchored_slot_position(atk_card)
	var t2b := get_tree().create_tween()
	t2b.tween_property(atk_card, "global_position", return_pos2, CARD_MOVE_SPEED)
	await t2b.finished

	if _is_card_alive(atk_card):
		atk_card.z_index = 0

	var defender_ref2: Node = defending if is_instance_valid(defending) else null
	await _trigger_on_attack(atk_card, attacker_owner, {
		"phase": "after_damage",
		"attacker": atk_card,
		"defender": defender_ref2,
		"result": ("win" if attacker_won else "lose")
	})

	_clear_bonuses([atk_card, defending])

	if attacker_owner == "Player":
		if not (atk_card in player_cards_that_attacked_this_turn):
			player_cards_that_attacked_this_turn.append(atk_card)
		_enable_player_input()
	else:
		if not (atk_card in opponent_cards_that_attacked_this_turn):
			opponent_cards_that_attacked_this_turn.append(atk_card)

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
		var cardowner_a := _owner_of(card_a)
		if cardowner_a != "":
			destroy_card(card_a, cardowner_a, "DESTROY_BATTLE")
	if is_instance_valid(card_b):
		var cardowner_b := _owner_of(card_b)
		if cardowner_b != "":
			destroy_card(card_b, cardowner_b, "DESTROY_BATTLE")
	_clear_multi_for(card_a)
	_clear_multi_for(card_b)

func direct_attack(atk_card, attacker):
	if duel_finished:
		return

	reveal_card(atk_card)

	if attacker == "Opponent":
		var new_pos_y := 1000
		atk_card.z_index = 5
		var t := get_tree().create_tween()
		t.tween_property(atk_card, "global_position", Vector2(atk_card.global_position.x, new_pos_y), CARD_MOVE_SPEED)
		await action_waiter()

		_apply_battle_damage_to_side("Player", int(atk_card.atk), atk_card, null)

		if not (atk_card in opponent_cards_that_attacked_this_turn):
			opponent_cards_that_attacked_this_turn.append(atk_card)

		if duel_finished:
			return

		var t2 := get_tree().create_tween()
		t2.tween_property(atk_card, "global_position", _anchored_slot_position(atk_card), CARD_MOVE_SPEED)
		await action_waiter()
		atk_card.z_index = 0
		return

	$"../InputManager".inputs_disabled = true
	enable_end_turn_button(false)

	if not (atk_card in player_cards_that_attacked_this_turn):
		player_cards_that_attacked_this_turn.append(atk_card)

	atk_card.z_index = 5
	var tw := get_tree().create_tween()
	tw.tween_property(atk_card, "global_position", Vector2(atk_card.global_position.x, 0), CARD_MOVE_SPEED)
	await action_waiter()

	_apply_battle_damage_to_side("Opponent", int(atk_card.atk), atk_card, null)

	if duel_finished:
		return

	var tw2 := get_tree().create_tween()
	tw2.tween_property(atk_card, "global_position", _anchored_slot_position(atk_card), CARD_MOVE_SPEED)
	await action_waiter()
	atk_card.z_index = 0

	$"../InputManager".inputs_disabled = false
	enable_end_turn_button(true)

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

func _trigger_on_attack(_card, _who: String, _ctx: Dictionary) -> void:	# Migrado a DuelEventBus + DuelEffectEngine.
	return

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

func register_card_played(card, cardowner: String) -> void:
	if not is_instance_valid(card):
		return
	cardowner = _norm_owner(cardowner)
	_set_card_owner_side(card, cardowner)
	if card.has_method("apply_owner_collision_layers"):
		card.apply_owner_collision_layers()
	var slot = _card_slot(card)
	if slot == null:
		return
	_place_card_in_slot(card, slot)

func start_spell_activation(spell_card, who: String) -> void:
	if not is_instance_valid(spell_card):
		return
	var spell_is_facedown := false
	if "face_down" in spell_card:
		spell_is_facedown = bool(spell_card.face_down)
	elif "is_facedown" in spell_card:
		spell_is_facedown = bool(spell_card.is_facedown)
	if spell_is_facedown:
		reveal_card(spell_card)

	var activation_ctx := {
		"battle_manager": self,
		"source": spell_card,
		"controller": who,
		"source_controller": who,
		"source_player": who,
		"opponent_player": ("Opponent" if who == "Player" else "Player"),
		"turn_owner": ("Opponent" if is_opponent_turn else "Player"),
		"activation_type": _activation_type_for_card(spell_card),
		"negated": false,
		"prevent_resolution": false,
		"destroy_activated_card": false
	}
	emit_signal("spell_activated", spell_card, who)
	if _activation_type_for_card(spell_card) == "TRAP":
		emit_signal("trap_activated", spell_card, who)
	_emit_activation_declaration_events(spell_card, who, activation_ctx)

	if bool(activation_ctx.get("negated", false)) or bool(activation_ctx.get("prevent_resolution", false)):
		if bool(activation_ctx.get("destroy_activated_card", false)):
			_send_spell_to_graveyard(spell_card, who)
		return

	_register_card_with_effect_engine(spell_card, who)
	_emit_duel_event("ON_ACTIVATE", activation_ctx)
	_emit_duel_event("ON_ACTIVATION_RESOLVED", activation_ctx)
	_send_spell_to_graveyard(spell_card, who)

func receive_spell_target(_card) -> void:
	return

func _clear_spell_targeting() -> void:
	spell_targeting = false
	pending_spell = null
	pending_effects = []
	pending_caster = ""
	pending_required_targets = 0
	pending_targets = []
	$"../EndTurnButton".disabled = false

func _send_spell_to_graveyard(spell_card, who: String) -> void:
	if not is_instance_valid(spell_card):
		return

	var slot = _card_slot(spell_card)
	if slot:
		slot.card_in_slot = false
		if "card_ref" in slot:
			slot.card_ref = null
		var slot_shape = slot.get_node_or_null("Area2D/CollisionShape2D")
		if slot_shape:
			slot_shape.disabled = false

	var norm_who := _norm_owner(who)
	if norm_who == "Player":
		player_graveyard.append(spell_card)
	else:
		opponent_graveyard.append(spell_card)

	_unregister_card_with_effect_engine(spell_card)
	_clear_card_slot(spell_card)
	spell_card.queue_free()
	_clean_battlefield_lists()

func _get_duel_bus():
	var bus = get_node_or_null("/root/DuelEventBus")
	if bus == null:
		bus = get_node_or_null("/root/EventBus")
	return bus

func _emit_duel_event(event_name: String, payload: Dictionary = {}) -> void:
	var bus = _get_duel_bus()
	if bus and bus.has_method("emit_event"):
		bus.emit_event(event_name, payload)

func _get_effect_engine():
	var eng = get_node_or_null("/root/DuelEffectEngine")
	if eng == null:
		eng = get_node_or_null("/root/EffectEngine")
	return eng

func _register_card_with_effect_engine(card, controller: String) -> void:
	var eng = _get_effect_engine()
	if eng and eng.has_method("register_card_entered_field"):
		eng.register_card_entered_field(card, controller)

func _unregister_card_with_effect_engine(card) -> void:
	var eng = _get_effect_engine()
	if eng and eng.has_method("register_card_left_field"):
		eng.register_card_left_field(card)

func _activation_type_for_card(card) -> String:
	match _card_kind(card):
		"TRAP":
			return "TRAP"
		"SPELL":
			return "SPELL"
		_:
			return "MONSTER_EFFECT"

func _emit_activation_declaration_events(card, controller: String, ctx: Dictionary) -> void:
	var t := _activation_type_for_card(card)
	match t:
		"TRAP":
			_emit_duel_event("ON_TRAP_ACTIVATE", ctx)
			_emit_duel_event("ON_OPPONENT_TRAP_ACTIVATE", ctx)
		"SPELL":
			_emit_duel_event("ON_SPELL_ACTIVATE", ctx)
			_emit_duel_event("ON_OPPONENT_SPELL_ACTIVATE", ctx)
		_:
			_emit_duel_event("ON_MONSTER_EFFECT_ACTIVATE", ctx)
			_emit_duel_event("ON_OPPONENT_MONSTER_EFFECT_ACTIVATE", ctx)

func _process_scheduled_destruction_on_turn_end(turn_owner: String) -> void:
	var all_cards: Array = []
	all_cards.append_array(player_cards_on_battlefield)
	all_cards.append_array(opponent_cards_on_battlefield)
	for c in all_cards:
		if not is_instance_valid(c):
			continue
		if not c.has_meta("scheduled_destruction"):
			continue
		var sd = c.get_meta("scheduled_destruction")
		var should_destroy := false
		if sd is bool:
			should_destroy = bool(sd)
		elif sd is Dictionary:
			var due := str(sd.get("due_turn_end_owner", ""))
			should_destroy = (due == "" or due == turn_owner)
		if not should_destroy:
			continue
		c.remove_meta("scheduled_destruction")
		var cardowner := _owner_of(c)
		if cardowner != "":
			destroy_card(c, cardowner)

func destroy_card(card, card_owner, cause := "DESTROY_EFFECT"):
	if not is_instance_valid(card):
		return
	_unregister_card_with_effect_engine(card)
	card_owner = _norm_owner(card_owner)
	var destroy_ctx := {
		"battle_manager": self,
		"source": card,
		"controller": card_owner,
		"cause": cause,
		"turn_owner": ("Opponent" if is_opponent_turn else "Player")
	}
	if cause == "DESTROY_BATTLE":
		_emit_duel_event("ON_DESTROY_BATTLE", destroy_ctx)
	elif cause == "DESTROY_EFFECT":
		_emit_duel_event("ON_DESTROY_EFFECT", destroy_ctx)
	_emit_duel_event("ON_DESTROY", destroy_ctx)
	_emit_duel_event("ON_LEAVE_FIELD", destroy_ctx)
	_emit_duel_event("ON_SEND_TO_GRAVE", destroy_ctx)
	if cause == "DESTROY_EFFECT":
		_emit_duel_event("ON_SEND_TO_GRAVE_BY_EFFECT", destroy_ctx)

	var slot = _card_slot(card)
	if card_owner == "Player":
		card.defeated = true
		var cshape = card.get_node_or_null("Area2D/CollisionShape2D")
		if cshape:
			cshape.disabled = true
		if card in player_cards_on_battlefield:
			player_graveyard.append(card)
			player_cards_on_battlefield.erase(card)
			if slot:
				var slot_shape = slot.get_node_or_null("Area2D/CollisionShape2D")
				if slot_shape:
					slot_shape.disabled = false
	else:
		if card in opponent_cards_on_battlefield:
			opponent_graveyard.append(card)
			opponent_cards_on_battlefield.erase(card)

	if slot:
		slot.card_in_slot = false
		if "card_ref" in slot:
			slot.card_ref = null
		if slot.get_parent() == $"../CardSlotsRival":
			if not empty_monster_card_slots.has(slot):
				empty_monster_card_slots.append(slot)

	_clear_multi_for(card)
	_clear_card_slot(card)
	card.queue_free()
	_clean_battlefield_lists()

func yield_to_refill_opponent_hand():
	var deck_rival = $"../DeckRival/Deck"
	var opp_hand = $"../OpponentHand"
	while deck_rival.opponent_deck.size() > 0 and opp_hand.opponent_hand.size() < _max_hand_size():
		deck_rival.draw_card()
		await action_waiter()

func enemy_card_selected(defending_card) -> void:
	if duel_finished:
		return
	if is_opponent_turn:
		return
	if not is_instance_valid(defending_card):
		return
	if _card_kind(defending_card) != "MONSTER":
		return

	var attacker = $"../CardManager".selected_monster
	if not is_instance_valid(attacker):
		return
	if _card_kind(attacker) != "MONSTER":
		return
	if attacker.in_defense:
		return
	if attacker in player_cards_that_attacked_this_turn:
		return

	$"../InputManager".inputs_disabled = true
	enable_end_turn_button(false)
	$"../CardManager".selected_monster = null

	await attack(attacker, defending_card, "Player")

	$"../InputManager".inputs_disabled = false
	enable_end_turn_button(true)

func try_play_highest_atk_card():
	var opp_hand_node = $"../OpponentHand"
	var opponent_hand = opp_hand_node.opponent_hand
	if opponent_hand.is_empty() or empty_monster_card_slots.is_empty():
		return

	var monsters: Array = []
	for c in opponent_hand:
		if _card_kind(c) == "MONSTER":
			monsters.append(c)
	if monsters.is_empty():
		return

	var slot_index := randi_range(0, empty_monster_card_slots.size() - 1)
	var slot = empty_monster_card_slots[slot_index]
	empty_monster_card_slots.erase(slot)

	var card_highestatk = monsters[0]
	for c in monsters:
		if int(c.atk) > int(card_highestatk.atk):
			card_highestatk = c

	opp_hand_node.remove_card_from_hand(card_highestatk)
	_set_card_owner_side(card_highestatk, "Opponent")

	var shape := slot.get_node_or_null("Area2D/CollisionShape2D") as CollisionShape2D
	if shape:
		shape.disabled = true

	_place_card_in_slot(card_highestatk, slot)
	await action_waiter()

func end_opponent_turn():
	_emit_duel_event("TURN_END", {"turn_owner":"Opponent", "controller":"Opponent", "turn_index": turn_index, "battle_manager": self})
	_process_scheduled_destruction_on_turn_end("Opponent")
	var player_deck = $"../Deck"
	var player_hand_node = $"../PlayerHand"
	var card_manager = $"../CardManager"
	is_opponent_turn = false
	card_manager.reset_played_cards()
	for k in multi_mode.keys():
		if is_instance_valid(k) and (k in opponent_cards_on_battlefield):
			_clear_multi_for(k)
		_cleanup_multi_garbage()
	while player_deck.player_deck.size() > 0 and player_hand_node.player_hand.size() < _max_hand_size():
		player_deck.draw_card()
		card_manager.reset_played_cards()
		await action_waiter()

	turn_index += 1
	_emit_duel_event("TURN_START", {"turn_owner":"Player", "controller":"Player", "turn_index": turn_index, "battle_manager": self,})
	$"../EndTurnButton".disabled = false
	$"../EndTurnButton".visible = true


func reveal_card(card: Node):
	if not is_instance_valid(card):
		return
	if not _is_card_face_down(card):
		return
	_set_card_face_down(card, false)
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

func _apply_battle_damage_to_side(target_owner: String, amount: int, source_card = null, defender_card = null) -> void:
	if amount <= 0:
		return

	target_owner = _norm_owner(target_owner)

	if target_owner == "Player":
		player_hp = max(0, player_hp - amount)
		$"../PlayerHP".text = str(player_hp)
	elif target_owner == "Opponent":
		opponent_hp = max(0, opponent_hp - amount)
		$"../OpponentHP".text = str(opponent_hp)
	else:
		return

	_emit_duel_event("ON_INFLICT_BATTLE_DAMAGE", {
		"battle_manager": self,
		"source": source_card,
		"defender": defender_card,
		"target_player": target_owner,
		"amount": amount,
		"turn_owner": ("Opponent" if is_opponent_turn else "Player")
	})
	_check_end_duel()

func _apply_effect_damage_to_side(target_owner: String, amount: int, ctx: Dictionary = {}) -> void:
	if amount <= 0:
		return
	if target_owner == "Player":
		player_hp = max(0, player_hp - amount)
		$"../PlayerHP".text = str(player_hp)
	elif target_owner == "Opponent":
		opponent_hp = max(0, opponent_hp - amount)
		$"../OpponentHP".text = str(opponent_hp)
	else:
		return
	_emit_duel_event("ON_INFLICT_EFFECT_DAMAGE", {"battle_manager": self, "source": ctx.get("source", null), "target_player": target_owner, "amount": amount, "turn_owner": ("Opponent" if is_opponent_turn else "Player")})
	_check_end_duel()

func recover_lp_to_side(target_owner: String, amount: int, _ctx: Dictionary = {}) -> void:
	if amount <= 0:
		return
	if target_owner == "Player":
		player_hp += amount
		$"../PlayerHP".text = str(player_hp)
	elif target_owner == "Opponent":
		opponent_hp += amount
		$"../OpponentHP".text = str(opponent_hp)

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

func _anchored_slot_position(card: Node2D) -> Vector2:
	if card == null:
		return Vector2.ZERO

	var slot = card.get("current_slot")
	if slot == null or not is_instance_valid(slot):
		return (card as Node2D).global_position

	var slot2d := slot as Node2D
	if slot2d == null:
		return (card as Node2D).global_position

	var card_anchor := card.get_node_or_null("AnchorCenter") as Node2D
	var slot_anchor := slot2d.get_node_or_null("Anchor") as Node2D
	var target := slot_anchor if slot_anchor else slot2d

	if card_anchor == null:
		return target.global_position

	var delta := card_anchor.to_global(Vector2.ZERO) - card.to_global(Vector2.ZERO)
	return target.global_position - delta

func _anchored_target_position(attacker: Node2D, defender: Node2D, y_offset := 0.0) -> Vector2:
	var def_anchor := defender.get_node_or_null("AnchorCenter") as Node2D
	var def_center := (def_anchor if def_anchor else defender) as Node2D
	var atk_anchor := attacker.get_node_or_null("AnchorCenter") as Node2D
	var atk_delta := atk_anchor.to_global(Vector2.ZERO) - attacker.to_global(Vector2.ZERO)
	return def_center.global_position - atk_delta + Vector2(0, y_offset)


func reveal_all_set_monsters_for_side(side: String) -> void:
	var norm_side := _norm_owner(side)
	var cards: Array = player_cards_on_battlefield if norm_side == "Player" else opponent_cards_on_battlefield
	for c in cards:
		if not is_instance_valid(c):
			continue
		if _card_kind(c) != "MONSTER":
			continue
		if _is_card_face_down(c):
			reveal_card(c)

func set_guardian_star_bonus_multiplier(source_card, multiplier: float, _ctx: Dictionary = {}) -> void:
	if not is_instance_valid(source_card):
		return
	source_card.set_meta("guardian_star_bonus_multiplier", float(multiplier))

func apply_keyword_to_card_if_matches_side(source_card, target_card, target_side: String, keyword: String, _ctx: Dictionary = {}) -> void:
	if not is_instance_valid(target_card):
		return
	var desired := str(target_side).to_upper()
	var actual := str(_card_owner_side(target_card)).to_upper()
	if desired in ["OPPONENT", "ENEMY"]:
		var src_side := str(_card_owner_side(source_card)).to_upper() if is_instance_valid(source_card) else ""
		if src_side == "PLAYER":
			desired = "OPPONENT"
		elif src_side == "OPPONENT":
			desired = "PLAYER"
	if desired in ["PLAYER","OPPONENT"] and actual != desired:
		return
	if target_card.has_method("add_runtime_keyword"):
		target_card.add_runtime_keyword(keyword)
	elif target_card.has_method("add_keyword"):
		target_card.add_keyword(keyword)
	else:
		var kws: Array = []
		if target_card.has_meta("runtime_keywords"):
			kws = target_card.get_meta("runtime_keywords")
		if keyword not in kws:
			kws.append(keyword)
			target_card.set_meta("runtime_keywords", kws)

func summon_token_from_source_basestats(source_card, params: Dictionary, ctx: Dictionary = {}) -> void:
	if not is_instance_valid(source_card):
		return

	var controller := ""
	if ctx is Dictionary and ctx.has("controller"):
		controller = _norm_owner(ctx["controller"])
	else:
		controller = _norm_owner(_owner_of(source_card))

	var slots_root := $"../CardSlots" if controller == "Player" else $"../CardSlotsRival"
	if not is_instance_valid(slots_root):
		return

	var free_slot: Node2D = null
	for s in slots_root.get_children():
		if not is_instance_valid(s):
			continue
		if str(s.get("card_slot_type")) != "Monster":
			continue
		if bool(s.get("card_in_slot")):
			continue
		free_slot = s
		break

	if free_slot == null:
		return

	var card_scene: PackedScene = preload("res://Scenes/Card.tscn")
	var token: Card = card_scene.instantiate()
	if not is_instance_valid(token):
		return

	get_tree().current_scene.add_child(token)

	token.kind = "MONSTER"
	token.id = "" 
	token.cardname = str(params.get("token_name", "Token"))
	token.attribute = str(source_card.attribute)
	token.race = str(source_card.race)
	token.level = int(source_card.level)
	token.atk = int(source_card.atk)
	token.def = int(source_card.def)
	token.guardian_star = source_card.guardian_star.duplicate() if source_card.guardian_star != null else []

	token.tags = (params.get("token_tags", ["token"]) as Array).duplicate()
	token.keywords = []
	token.effects = []
	token.description = ""
	if token.has_method("_update_visuals"):
		token._update_visuals()
	token.set_meta("is_token", true)

	token.owner_side = ("PLAYER" if controller == "Player" else "OPPONENT")
	token.set_show_back_only(false)
	token.set_face_down(false)
	token.apply_owner_collision_layers()

	var src_art: TextureRect = source_card.get_node_or_null("CardArt")
	var tok_art: TextureRect = token.get_node_or_null("CardArt")
	if is_instance_valid(src_art) and is_instance_valid(tok_art):
		tok_art.texture = src_art.texture

	free_slot.card_in_slot = true
	if "card_ref" in free_slot:
		free_slot.card_ref = token

	token.set_field_slot(free_slot)
	if token.has_method("set_defense_position"):
		token.set_defense_position(true)
	else:
		token.in_defense = true
	token.scale = Vector2($"../CardManager".FIELD_SCALE, $"../CardManager".FIELD_SCALE)
	$"../CardManager"._snap_card_to_slot_center(token, free_slot)
	token.z_index = -4

	_register_card_with_effect_engine(token, controller)
	
	if controller == "Player":
		if not player_cards_on_battlefield.has(token):
			player_cards_on_battlefield.append(token)
	else:
		if not opponent_cards_on_battlefield.has(token):
			opponent_cards_on_battlefield.append(token)

	_clean_battlefield_lists()
	
	_emit_duel_event("ON_SUMMON_BY_EFFECT", {
		"battle_manager": self,
		"source": token,
		"controller": controller,
		"turn_owner": ("Opponent" if is_opponent_turn else "Player"),
		"created_from": source_card
	})

func try_activate_selected_card() -> void:
	if duel_finished:
		return
	if is_opponent_turn:
		return

	var cm := get_node_or_null("../CardManager")
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
		"battle_manager": self,
		"source": card,
		"controller": controller,
		"turn_owner": ("Opponent" if is_opponent_turn else "Player"),
		"prevent_activate": false,
		"activation_negated": false
	}

	_emit_duel_event("ON_ACTIVATE", ctx)

func try_activate_card(card) -> void:
	if duel_finished:
		return
	if is_opponent_turn:
		return
	if not is_instance_valid(card):
		return

	var controller := _norm_owner(_owner_of(card))
	if controller != "Player":
		return

	if _is_card_face_down(card):
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

	var act_ctx := {
		"battle_manager": self,
		"source": card,
		"controller": controller,
		"turn_owner": ("Opponent" if is_opponent_turn else "Player"),
		"turn_index": turn_index,
		"prevent_activate": false,
		"activation_negated": false
	}

	_emit_duel_event("ON_ACTIVATE", act_ctx)

	if bool(act_ctx.get("prevent_activate", false)) or bool(act_ctx.get("activation_negated", false)):
		return

	_emit_duel_event("ON_ACTIVATION_RESOLVED", act_ctx)
