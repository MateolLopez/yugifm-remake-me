extends Node

enum EffectType {
	ON_PLAY,          
	ON_ATTACK,          
	ON_DESTROY,       
	ON_FIELD,         
	TRIGGERED,        
	SPELL_ACTIVATION, 
	TRAP_ACTIVATION   
}

enum TriggerCondition {
	OPPONENT_ATTACK_DECLARED,
	OPPONENT_MONSTER_PLAYED,
	OPPONENT_SPELL_ACTIVATED,
	OPPONENT_TRAP_ACTIVATED,
	MONSTER_DESTROYED,
	DAMAGE_RECEIVED,
	TURN_START,
	TURN_END,
	BATTLE_STEP,
	DIRECT_ATTACK_DECLARED
}

# Registro de efectos
var _effect_handlers := {}
var _active_traps := []  # Trampas esperando activación
@onready var battle_manager = get_node("res://Scripts/battle_manager.gd")

func _ready():
	_register_effect_handlers()

func _register_effect_handlers():
	# Efectos de destrucción
	_effect_handlers["destroy_enemy_monsters"] = _handle_destroy_enemy_monsters
	_effect_handlers["destroy_all_monsters"] = _handle_destroy_all_monsters
	_effect_handlers["destroy_target_enemy"] = _handle_destroy_target_enemy
	_effect_handlers["destroy_lowest_atk"] = _handle_destroy_lowest_atk
	_effect_handlers["destroy_spell_trap"] = _handle_destroy_spell_trap
	_effect_handlers["destroy_all_spell_trap"] = _handle_destroy_all_spell_trap
	_effect_handlers["destroy_attackers_in_attack_position"] = _handle_destroy_attackers_in_attack_position
	
	# Efectos de daño/recuperación
	_effect_handlers["inflict_damage"] = _handle_inflict_damage
	_effect_handlers["recover_lp"] = _handle_recover_lp
	
	# Efectos de control
	_effect_handlers["take_control"] = _handle_take_control
	_effect_handlers["prevent_attack"] = _handle_prevent_attack
	_effect_handlers["change_position"] = _handle_change_position
	_effect_handlers["negate_attack"] = _handle_negate_attack
	
	# Efectos de stats
	_effect_handlers["increase_atk_def"] = _handle_increase_atk_def
	_effect_handlers["decrease_atk_def"] = _handle_decrease_atk_def
	_effect_handlers["invert_stats"] = _handle_invert_stats
	
	# Efectos varios
	_effect_handlers["summon_monster"] = _handle_summon_monster
	_effect_handlers["reborn_from_grave"] = _handle_reborn_from_grave
	_effect_handlers["multi_attack"] = _handle_multi_attack
	_effect_handlers["kill_destroyer_next_EP"] = _handle_kill_destroyer_next_ep
	_effect_handlers["only_direct_attack"] = _handle_only_direct_attack
	_effect_handlers["can_direct_attack"] = _handle_can_direct_attack
	_effect_handlers["piercing_damage"] = _handle_piercing_damage
	_effect_handlers["inflict_destroyed_atk"] = _handle_inflict_destroyed_atk
	_effect_handlers["recover_hp"] = _handle_recover_hp_on_attack
	_effect_handlers["destroy_defense_monsters"] = _handle_destroy_defense_monsters
	_effect_handlers["immune"] = _handle_immune 
	
	await get_tree().create_timer(3.0).timeout
	get_node("/root/EffectManager").test_trap_activation()

func execute_effect(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary = {}) -> void:
	var effect_key = _effect_data.get("action", "")
	if _effect_handlers.has(effect_key):
		await _effect_handlers[effect_key].call(_effect_data, _source_card, _card_owner, _context)

func register_trap_effect(card, trigger_condition, effect_data):
	if card == null:
		push_warning("No se puede registrar trampa: carta nula")
		return
	
	print(">>> EffectManager: Registrando trampa - Carta: ", card.card_name, 
		  " - Condición: ", trigger_condition, 
		  " - Efecto: ", effect_data.get("action", ""))
	
	_active_traps.append({
		"card": card,
		"condition": trigger_condition,
		"effect": effect_data,
		"owner": card.card_owner
	})
	
	print(">>> Trampas activas totales: ", _active_traps.size())

func check_trap_triggers(condition: int, context: Dictionary = {}):
	print(">> check_trap_triggers llamado - Condición: ", condition, " - Contexto: ", context)
	print(">> Trampas activas: ", _active_traps.size())
	
	var triggered = []
	for trap in _active_traps.duplicate():
		print(">> Evaluando trampa: ", trap.card.card_name, " - Condición esperada: ", trap.condition)
		
		if trap.condition == condition:
			print(">>   Condición coincide - verificando condiciones específicas...")
			if _check_trap_conditions(trap, context):
				print(">>   ¡CONDICIONES CUMPLIDAS! Activando trampa: ", trap.card.card_name)
				triggered.append(trap)
			else:
				print(">>   Condiciones NO cumplidas para: ", trap.card.card_name)
		else:
			print(">>   Condición NO coincide (esperaba: ", trap.condition, ", recibió: ", condition, ")")
	
	print(">> Trampas a activar: ", triggered.size())
	for trap in triggered:
		print(">> Procesando activación de: ", trap.card.card_name)
		await execute_effect(trap.effect, trap.card, trap.owner, context)
		_send_to_graveyard(trap.card, trap.owner)
		_active_traps.erase(trap)
		print(">> Trampa eliminada de activas. Restantes: ", _active_traps.size())

func _check_trap_conditions(trap, context):
	var effect_data = trap.effect
	var params = effect_data.get("condition_params", {})

	match trap.condition:
		TriggerCondition.OPPONENT_ATTACK_DECLARED:
			# Mirror Force
			var attacker_card_owner = context.get("attacker_card_owner", "")
			return attacker_card_owner != trap.owner

		TriggerCondition.OPPONENT_MONSTER_PLAYED:
			# Trap Hole
			var atk = context.get("atk", 0)
			var min_atk = params.get("min_atk", 0)
			var monster_card_owner = context.get("monster_card_owner", "")
			return atk >= min_atk and monster_card_owner != trap.owner

		TriggerCondition.OPPONENT_SPELL_ACTIVATED:
			var spell_card_owner = context.get("spell_card_owner", "")
			return spell_card_owner != trap.owner

		TriggerCondition.TURN_START, TriggerCondition.TURN_END:
			var turn_card_owner = context.get("turn_card_owner", "")
			return turn_card_owner != trap.owner

		_:
			return true

#IMPLEMENTACIONES

# Efectos de destrucción
func _handle_destroy_enemy_monsters(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var _bm = $"../BattleManager"
	var enemy_list = _bm.opponent_cards_on_battlefield if _card_owner == "Player" else _bm.player_cards_on_battlefield
	
	for card in enemy_list.duplicate():
		if is_instance_valid(card) and not _is_immune_to(card, "spells"):
			_bm.destroy_card(card, "Opponent" if _card_owner == "Player" else "Player")

func _handle_destroy_all_monsters(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var _bm = $"../BattleManager"
	
	# Destruir monstruos del jugador
	for card in _bm.player_cards_on_battlefield.duplicate():
		if is_instance_valid(card) and not _is_immune_to(card, "spells"):
			_bm.destroy_card(card, "Player")
	
	# Destruir monstruos del oponente
	for card in _bm.opponent_cards_on_battlefield.duplicate():
		if is_instance_valid(card) and not _is_immune_to(card, "spells"):
			_bm.destroy_card(card, "Opponent")

func _handle_destroy_target_enemy(_effect_data: Dictionary, _source_card, _card_owner: String, context: Dictionary):
	var bm = $"../BattleManager"
	var target = context.get("monster")  # Cambiado de "target" a "monster" para coincidir con el contexto
	
	print(">>> Ejecutando Trap Hole - destruyendo objetivo")
	print(">>> Target recibido: ", target.card_name if target else "null")
	
	if is_instance_valid(target) and not _is_immune_to(target, "traps"):
		var target_owner = bm._owner_of(target)
		print(">>> Destruyendo objetivo: ", target.card_name)
		bm.destroy_card(target, target_owner)
	else:
		print(">>> Target no válido o inmune")

func _handle_destroy_lowest_atk(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var _bm = $"../BattleManager"
	var enemy_list = _bm.opponent_cards_on_battlefield if _card_owner == "Player" else _bm.player_cards_on_battlefield
	
	if enemy_list.is_empty():
		return
	
	# Encontrar monstruo con menor ATK
	var lowest_atk_card = enemy_list[0]
	for card in enemy_list:
		if is_instance_valid(card) and card.Atk < lowest_atk_card.Atk:
			lowest_atk_card = card
	
	if is_instance_valid(lowest_atk_card):
		var target__card_owner = "Opponent" if _card_owner == "Player" else "Player"
		_bm.destroy_card(lowest_atk_card, target__card_owner)

func _handle_destroy_spell_trap(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var _bm = $"../BattleManager"
	# Esto requiere lógica específica para identificar cartas de hechizo/trampa
	# Por ahora, asumimos que se destruye una carta aleatoria del campo oponente
	var enemy_field = _bm.opponent_cards_on_battlefield if _card_owner == "Player" else _bm.player_cards_on_battlefield
	
	if not enemy_field.is_empty():
		var random_card = enemy_field[randi() % enemy_field.size()]
		if is_instance_valid(random_card):
			var target__card_owner = "Opponent" if _card_owner == "Player" else "Player"
			_bm.destroy_card(random_card, target__card_owner)

func _handle_destroy_all_spell_trap(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var _bm = $"../BattleManager"
	# Similar al anterior pero para todas las cartas de hechizo/trampa
	var enemy_field = _bm.opponent_cards_on_battlefield if _card_owner == "Player" else _bm.player_cards_on_battlefield
	
	for card in enemy_field.duplicate():
		if is_instance_valid(card) and (card.card_type == "Spell" or card.card_type == "Trap"):
			var target__card_owner = "Opponent" if _card_owner == "Player" else "Player"
			_bm.destroy_card(card, target__card_owner)

func _handle_destroy_attackers_in_attack_position(_effect_data: Dictionary, _source_card, _card_owner: String, context: Dictionary):
	var bm = $"../BattleManager"
	print(">>> Ejecutando Mirror Force - destruyendo atacantes en posición de ataque")
	
	var attacker = context.get("attacker")
	if attacker and is_instance_valid(attacker) and not attacker.in_defense:
		var attacker_owner = bm._owner_of(attacker)
		print(">>> Destruyendo atacante: ", attacker.card_name)
		bm.destroy_card(attacker, attacker_owner)
	
	var enemy_field = bm.opponent_cards_on_battlefield if _card_owner == "Player" else bm.player_cards_on_battlefield
	print(">>> Monstruos en campo enemigo: ", enemy_field.size())
	
	for card in enemy_field.duplicate():
		if is_instance_valid(card) and not card.in_defense and not _is_immune_to(card, "traps"):
			var target_owner = bm._owner_of(card)
			print(">>> Destruyendo monstruo en posición de ataque: ", card.card_name)
			bm.destroy_card(card, target_owner)
		elif is_instance_valid(card):
			print(">>> Saltando monstruo: ", card.card_name, 
				  " - En defensa: ", card.in_defense, 
				  " - Inmune: ", _is_immune_to(card, "traps"))

func _handle_inflict_damage(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var damage = _effect_data.get("amount", 0)
	var _bm = $"../BattleManager"
	
	if _effect_data.get("target") == "opponent":
		if _card_owner == "Player":
			_bm.opponent_hp = max(0, _bm.opponent_hp - damage)
		else:
			_bm.player_hp = max(0, _bm.player_hp - damage)
	else:
		if _card_owner == "Player":
			_bm.player_hp = max(0, _bm.player_hp - damage)
		else:
			_bm.opponent_hp = max(0, _bm.opponent_hp - damage)
	
	_bm._check_end_duel()
	$"../PlayerHP".text = str(_bm.player_hp)
	$"../OpponentHP".text = str(_bm.opponent_hp)

func _handle_recover_lp(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var amount = _effect_data.get("amount", 0)
	var _bm = $"../BattleManager"
	
	if _card_owner == "Player":
		_bm.player_hp += amount
	else:
		_bm.opponent_hp += amount
	
	$"../PlayerHP".text = str(_bm.player_hp)
	$"../OpponentHP".text = str(_bm.opponent_hp)

# Efectos de control
func _handle_take_control(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var _bm = $"../BattleManager"
	var target = _context.get("target")
	
	if is_instance_valid(target):
		# Remover de campo oponente
		if target in _bm.opponent_cards_on_battlefield:
			_bm.opponent_cards_on_battlefield.erase(target)
		elif target in _bm.player_cards_on_battlefield:
			_bm.player_cards_on_battlefield.erase(target)
		
		# Agregar a campo propio
		if _card_owner == "Player":
			_bm.player_cards_on_battlefield.append(target)
			target.card__card_owner = "Player"
		else:
			_bm.opponent_cards_on_battlefield.append(target)
			target.card__card_owner = "Opponent"
		
		# Re-aplicar capas de colisión
		target.apply__card_owner_collision_layers()

func _handle_prevent_attack(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var target = _context.get("target", _source_card)
	var turns = _effect_data.get("turns", 1)
	
	if is_instance_valid(target):
		target.set_meta("attack_prevented", true)
		target.set_meta("attack_prevented_turns", turns)

func _handle_change_position(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var target = _context.get("target", _source_card)
	var new_position = _effect_data.get("position", "attack")  # "attack" o "defense"
	
	if is_instance_valid(target) and target.has_method("set_defense_position"):
		if new_position == "defense":
			target.set_defense_position(true)
		else:
			target.set_defense_position(false)

func _handle_negate_attack(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var attacker = _context.get("attacker")
	
	if is_instance_valid(attacker):
		# Cancelar el ataque actual
		# modificar BattleManager para soportar cancelación
		print("Ataque negado para: ", attacker.card_name)

# Efectos de stats
func _handle_increase_atk_def(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var amount = _effect_data.get("amount", 500)
	var target = _context.get("target", _source_card)
	var stat = _effect_data.get("stat", "both")
	var condition = _effect_data.get("condition", "")
	var target_type = _effect_data.get("target", "self")
	
	# Aplicar a diferentes objetivos según target_type
	var targets = []
	match target_type:
		"self":
			targets = [_source_card]
		"earth_allies":
			targets = _get_earth_allies(_source_card, _card_owner)
		"water_allies":
			targets = _get_water_allies(_source_card, _card_owner)
		"wind_allies":
			targets = _get_wind_allies(_source_card, _card_owner)
		"hero_in_graveyard":
			# Para Shining Flare Wingman - bonus por héroes en cementerio
			if _has_heroes_in_graveyard(_card_owner):
				targets = [_source_card]
		_:
			targets = [_source_card]
	
	for card in targets:
		if is_instance_valid(card):
			match stat:
				"atk":
					card.Atk += amount
				"def":
					card.Def += amount
				"both":
					card.Atk += amount
					card.Def += amount
			
			if card.has_method("update_card_visuals"):
				card.update_card_visuals()

func _get_earth_allies(source_card, card_owner: String) -> Array:
	var bm = $"../BattleManager"
	var field = bm.player_cards_on_battlefield if card_owner == "Player" else bm.opponent_cards_on_battlefield
	var allies = []
	for card in field:
		if is_instance_valid(card) and card != source_card and card.attribute == "earth":
			allies.append(card)
	return allies

func _get_water_allies(source_card, card_owner: String) -> Array:
	var bm = $"../BattleManager"
	var field = bm.player_cards_on_battlefield if card_owner == "Player" else bm.opponent_cards_on_battlefield
	var allies = []
	for card in field:
		if is_instance_valid(card) and card != source_card and card.attribute == "water":
			allies.append(card)
	return allies

func _get_wind_allies(source_card, card_owner: String) -> Array:
	var bm = $"../BattleManager"
	var field = bm.player_cards_on_battlefield if card_owner == "Player" else bm.opponent_cards_on_battlefield
	var allies = []
	for card in field:
		if is_instance_valid(card) and card != source_card and card.attribute == "wind":
			allies.append(card)
	return allies

func _has_heroes_in_graveyard(card_owner: String) -> bool:
	var bm = $"../BattleManager"
	var grave = bm.player_graveyard if card_owner == "Player" else bm.opponent_graveyard
	for card in grave:
		if is_instance_valid(card) and "hero" in card.tags:
			return true
	return false

func _handle_decrease_atk_def(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var amount = _effect_data.get("amount", 500)
	var target = _context.get("target", _source_card)
	var stat = _effect_data.get("stat", "both")
	
	if is_instance_valid(target):
		match stat:
			"atk":
				target.Atk = max(0, target.Atk - amount)
			"def":
				target.Def = max(0, target.Def - amount)
			"both":
				target.Atk = max(0, target.Atk - amount)
				target.Def = max(0, target.Def - amount)
		
		if target.has_method("update_card_visuals"):
			target.update_card_visuals()

func _handle_invert_stats(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var target = _context.get("target", _source_card)
	
	if is_instance_valid(target):
		var temp_atk = target.Atk
		target.Atk = target.Def
		target.Def = temp_atk
		
		if target.has_method("update_card_visuals"):
			target.update_card_visuals()

# Efectos especiales
func _handle_summon_monster(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var _bm = $"../BattleManager"
	var monster_type = _effect_data.get("monster_type", "random")
	var level = _effect_data.get("level", 3)
	
	# lógica para buscar en el deck/cementerio
	# Por ahora es un placeholder
	# Probablemente solo cementerio
	print("Summon monster effect - Tipo: ", monster_type, " Nivel: ", level)

func _handle_reborn_from_grave(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var _bm = $"../BattleManager"
	var grave = _bm.player_graveyard if _card_owner == "Player" else _bm.opponent_graveyard
	
	if not grave.is_empty():
		# Revivir el primer monstruo del cementerio
		var reborn_card = grave[0]
		grave.erase(reborn_card)
		
		# Encontrar slot vacío
		var empty_slots = _bm.empty_monster_card_slots if _card_owner == "Player" else []
		# Nota: slots vacíos para el oponente también
		
		if not empty_slots.is_empty():
			var slot = empty_slots[0]
			empty_slots.erase(slot)
			
			# Colocar la carta en el campo
			reborn_card.card_slot_card_is_in = slot
			slot.card_in_slot = true
			reborn_card.set_facedown(false)
			reborn_card.defeated = false
			
			if _card_owner == "Player":
				_bm.player_cards_on_battlefield.append(reborn_card)
			else:
				_bm.opponent_cards_on_battlefield.append(reborn_card)

func _handle_multi_attack(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var _bm = $"../BattleManager"
	var mode = _effect_data.get("mode", "times")
	var value = _effect_data.get("value", 1)
	
	if mode == "times":
		_bm.multi_mode[_source_card] = "times"
		_bm.multi_remaining[_source_card] = value
	elif mode == "all_each":
		_bm.multi_mode[_source_card] = "all_each"
		var pool = _bm.opponent_cards_on_battlefield if _card_owner == "Player" else _bm.player_cards_on_battlefield
		_bm.multi_remaining[_source_card] = pool.size()
		_bm.multi_already_attacked[_source_card] = []

func _handle_kill_destroyer_next_ep(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var _bm = $"../BattleManager"
	var destroyer = _context.get("destroyer")
	
	if is_instance_valid(destroyer):
		destroyer.set_meta("scheduled_destruction", true)
		# Programar para el End Phase del siguiente turno
		if not _bm.is_connected("turn_ended", _on_turn_ended_check_destruction):
			_bm.connect("turn_ended", _on_turn_ended_check_destruction)

func _handle_only_direct_attack(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var phase = _context.get("phase", "")
	if phase == "declare":
		_source_card.set_meta("only_direct_attack", true)

func _handle_can_direct_attack(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var phase = _context.get("phase", "")
	if phase == "declare":
		_source_card.set_meta("can_direct_attack", true)

# FUNCIONES AUXILIARES

func _on_turn_ended_check_destruction(turn__card_owner: String):
	var _bm = $"../BattleManager"
	var field = _bm.player_cards_on_battlefield if turn__card_owner == "Opponent" else _bm.opponent_cards_on_battlefield
	
	for card in field.duplicate():
		if is_instance_valid(card) and card.get_meta("scheduled_destruction", false):
			_bm.destroy_card(card, turn__card_owner)
			card.set_meta("scheduled_destruction", false)

func _is_immune_to(card, effect_type: String) -> bool:
	if not is_instance_valid(card):
		return false
	# Verificar inmunidades en los efectos de la carta
	if card.effects is Array:
		for eff in card.effects:
			if eff is Dictionary and eff.get("type") == "immune" and eff.get("to") == effect_type:
				return true
	return false

func _send_to_graveyard(card, _card_owner: String):
	var _bm = $"../BattleManager"
	if _card_owner == "Player":
		_bm.player_graveyard.append(card)
	else:
		_bm.opponent_graveyard.append(card)
	
	if card.card_slot_card_is_in:
		card.card_slot_card_is_in.card_in_slot = false
	card.queue_free()

func _handle_piercing_damage(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var _bm = $"../BattleManager"
	var phase = _context.get("phase", "")
	if phase == "declare":
		_source_card.set_meta("piercing_damage", true)

func _handle_inflict_destroyed_atk(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var _bm = $"../BattleManager"
	var destroyed_card = _context.get("destroyed_card")
	
	if is_instance_valid(destroyed_card) and destroyed_card.Atk > 0:
		var damage = destroyed_card.Atk
		if _card_owner == "Player":
			_bm.opponent_hp = max(0, _bm.opponent_hp - damage)
		else:
			_bm.player_hp = max(0, _bm.player_hp - damage)
		
		_bm._check_end_duel()
		$"../PlayerHP".text = str(_bm.player_hp)
		$"../OpponentHP".text = str(_bm.opponent_hp)

func _handle_recover_hp_on_attack(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var _bm = $"../BattleManager"
	var amount = _effect_data.get("amount", 500)
	
	if _card_owner == "Player":
		_bm.player_hp += amount
	else:
		_bm.opponent_hp += amount
	
	$"../PlayerHP".text = str(_bm.player_hp)
	$"../OpponentHP".text = str(_bm.opponent_hp)

# Efecto de destruir monstruos en defensa (para E. HERO Rampart Blaster)
func _handle_destroy_defense_monsters(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	var _bm = $"../BattleManager"
	var enemy_list = _bm.opponent_cards_on_battlefield if _card_owner == "Player" else _bm.player_cards_on_battlefield
	
	for card in enemy_list.duplicate():
		if is_instance_valid(card) and card.in_defense:
			var target_owner = "Opponent" if _card_owner == "Player" else "Player"
			_bm.destroy_card(card, target_owner)

func _handle_immune(_effect_data: Dictionary, _source_card, _card_owner: String, _context: Dictionary):
	# Los efectos de inmunidad se manejan en _is_immune_to(), este handler es solo para registro
	pass

func test_trap_activation():
	print(">>> TEST: Forzando activación de trampas...")
	print(">>> Trampas activas: ", _active_traps.size())
	
	# Crear un contexto de prueba para Mirror Force
	var test_context = {
		"attacker_card_owner": "Opponent",
		"attacker": null,
		"defender": null
	}
	
	check_trap_triggers(TriggerCondition.OPPONENT_ATTACK_DECLARED, test_context)

func check_for_trap_activations_directly():
	print(">>> BUSCANDO ACTIVACIONES DE TRAMPAS DIRECTAMENTE")
	print(">>> Trampas activas: ", _active_traps.size())
	
	for trap in _active_traps:
		print(">>> Trampa: ", trap.card.card_name, " - Condición: ", trap.condition)
		
		if trap.condition == TriggerCondition.OPPONENT_ATTACK_DECLARED:
			print(">>> Mirror Force detectada - verificando si debería activarse")
