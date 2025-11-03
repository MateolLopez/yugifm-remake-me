extends Node

# Categorías de efectos
const EFFECT_CATEGORIES = {
	"on_attack": "_handle_on_attack",
	"on_play": "_handle_on_play", 
	"on_field": "_handle_on_field",
	"destroy_card": "_handle_destroy"
}

func execute(effect_list: Array, who: String, ctx: Dictionary = {}) -> void:
	if effect_list.is_empty():
		return

	var verb = effect_list[0]
	
	# Deshabilitar inputs solo si es turno del jugador
	if $"../BattleManager".is_opponent_turn == false:
		$"../InputManager".inputs_disabled = true
		$"../BattleManager".enable_end_turn_button(false)
	
	# Ejecutar efecto según categoría
	if EFFECT_CATEGORIES.has(verb):
		var handler = EFFECT_CATEGORIES[verb]
		await call(handler, effect_list, who, ctx)
	else:
		print("Efecto no soportado:", effect_list)

	await $"../BattleManager".action_waiter()
	
	# Rehabilitar inputs solo si es turno del jugador
	if $"../BattleManager".is_opponent_turn == false:
		$"../BattleManager".enable_end_turn_button(true)
		$"../InputManager".inputs_disabled = false

# Efectos de destrucción
func _handle_destroy(effect_list: Array, who: String, ctx: Dictionary) -> void:
	var target = effect_list[1] if effect_list.size() > 1 else ""
	var bm = $"../BattleManager"

	match target:
		"enemy_monsters":
			var enemy_list = bm.opponent_cards_on_battlefield if who == "Player" else bm.player_cards_on_battlefield
			for c in enemy_list.duplicate():
				if not is_instance_valid(c) or _is_immune_to(c, "spells"):
					continue
				var card_owner = "Opponent" if who == "Player" else "Player"
				bm.destroy_card(c, card_owner)
		"all_monsters":
			var lists = [bm.player_cards_on_battlefield.duplicate(), bm.opponent_cards_on_battlefield.duplicate()]
			var card_owners = ["Player", "Opponent"]
			for i in range(lists.size()):
				for c in lists[i]:
					if not is_instance_valid(c) or _is_immune_to(c, "spells"):
						continue
					bm.destroy_card(c, card_owners[i])
		"target_enemy_monster":
			var targets: Array = ctx.get("targets", [])
			for c in targets:
				if not is_instance_valid(c) or _is_immune_to(c, "spells"):
					continue
				var card_owner = "Opponent" if who == "Player" else "Player"
				bm.destroy_card(c, card_owner)
		_:
			print("Target destroy no soportado:", target)

# Efectos al atacar
func _handle_on_attack(effect_list: Array, who: String, ctx: Dictionary) -> void:
	if not ctx.has("attacker"):
		return
		
	var attacker_card = ctx["attacker"]
	if not is_instance_valid(attacker_card):
		return
	
	if effect_list.size() < 2:
		return
		
	var sub_effect = effect_list[1]
	match sub_effect:
		"multi_attack":
			_do_multi_attack(effect_list, who, attacker_card)
		"only_direct":
			_handle_only_direct(attacker_card, who, ctx)
		"can_direct":
			_handle_can_direct(attacker_card, who, ctx)
		"atk_up":
			_handle_atk_up(effect_list, attacker_card, ctx)
		_:
			print("Efecto on_attack no soportado:", sub_effect)

# Efectos al jugar la carta
func _handle_on_play(effect_list: Array, who: String, ctx: Dictionary) -> void:
	if effect_list.size() < 2:
		return
		
	var sub_effect = effect_list[1]
	match sub_effect:
		#"destroy_on_play":
			#_handle_destroy_on_play(effect_list, who, ctx)
		_:
			print("Efecto on_play no soportado:", sub_effect)

# Efectos constantes en el campo
func _handle_on_field(effect_list: Array, who: String, ctx: Dictionary) -> void:
	if effect_list.size() < 2:
		return
		
	var sub_effect = effect_list[1]
	match sub_effect:
		"atk_aura":
			_handle_atk_aura(effect_list, who, ctx)
		# Agregar más efectos constantes acá
		_:
			print("Efecto on_field no soportado:", sub_effect)

# --- IMPLEMENTACIONES ESPECÍFICAS ---

# Multi-ataque
func _do_multi_attack(effect_list: Array, who: String, attacker_card) -> void:
	var bm = $"../BattleManager"
	if not is_instance_valid(attacker_card): 
		return
		
	var in_field = (attacker_card in bm.player_cards_on_battlefield) or (attacker_card in bm.opponent_cards_on_battlefield)
	if not in_field: 
		return

	var mode := "times"
	var times := 1
	
	if effect_list.size() >= 3:
		mode = str(effect_list[2])
		
	if mode == "times":
		if effect_list.size() >= 4 and typeof(effect_list[3]) == TYPE_INT:
			times = max(1, effect_list[3])
		bm.multi_mode[attacker_card] = "times"
		bm.multi_remaining[attacker_card] = times
		bm.multi_already_attacked.erase(attacker_card)
		
	elif mode == "all_each":
		bm.multi_mode[attacker_card] = "all_each"
		var pool := []
		if who == "Player":
			for d in bm.opponent_cards_on_battlefield:
				if is_instance_valid(d): 
					pool.append(d)
		else:
			for d in bm.player_cards_on_battlefield:
				if is_instance_valid(d): 
					pool.append(d)
		bm.multi_remaining[attacker_card] = pool.size()
		bm.multi_already_attacked[attacker_card] = []

# Solo ataque directo
func _handle_only_direct(attacker_card, who: String, ctx: Dictionary) -> void:
	var bm = $"../BattleManager"
	var phase = ctx.get("phase", "")
	
	if phase == "declare":
		# Marcar que este monstruo solo puede atacar directamente
		attacker_card.set_meta("only_direct_attack", true)

# Puede atacar directamente
func _handle_can_direct(attacker_card, who: String, ctx: Dictionary) -> void:
	var bm = $"../BattleManager"
	var phase = ctx.get("phase", "")
	
	if phase == "declare":
		# Marcar que este monstruo puede elegir ataque directo
		attacker_card.set_meta("can_direct_attack", true)

# Aumento de ATK temporal
func _handle_atk_up(effect_list: Array, attacker_card, ctx: Dictionary) -> void:
	if effect_list.size() < 4:
		return
		
	var duration = effect_list[2]
	var amount = effect_list[3]
	var phase = ctx.get("phase", "")
	
	if phase == "declare":
		attacker_card.Atk += amount
		# agregar sistema temporal

# Aura de ATK
func _handle_atk_aura(effect_list: Array, who: String, ctx: Dictionary) -> void:
	var amount = effect_list[2] if effect_list.size() > 2 else 500
	var bm = $"../BattleManager"
	
	# Aplicar bonus a monstruos aliados
	var field = bm.player_cards_on_battlefield if who == "Player" else bm.opponent_cards_on_battlefield
	for card in field:
		if is_instance_valid(card) and card != ctx.get("source"):
			card.Atk += amount

# --- FUNCIONES AUXILIARES ---

func _is_immune_to(card, effect_type: String) -> bool:
	if not is_instance_valid(card):
		return false
	# Verificar inmunidades en los efectos de la carta
	if card.effect is Array and card.effect.has("immune_to_%s" % effect_type):
		return true
	return false
