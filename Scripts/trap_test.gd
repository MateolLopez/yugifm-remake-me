extends Node

func _ready():
	await get_tree().create_timer(5.0).timeout
	_test_traps()

func _test_traps():
	print("\n=== INICIANDO TEST DE TRAMPAS ===")
	
	var effect_manager = get_node("/root/EffectManager")
	var battle_manager = $"../BattleManager"
	
	print(">>> Estado actual:")
	print(">>> - Trampas activas: ", effect_manager._active_traps.size())
	
	# Listar todas las trampas activas
	for i in range(effect_manager._active_traps.size()):
		var trap = effect_manager._active_traps[i]
		print(">>> - Trampa ", i, ": ", trap.card.card_name, " - Condición: ", trap.condition)
	
	# Simular un ataque del oponente
	print("\n>>> Simulando ataque del oponente...")
	if battle_manager.opponent_cards_on_battlefield.size() > 0:
		var attacker = battle_manager.opponent_cards_on_battlefield[0]
		print(">>> Atacante simulado: ", attacker.card_name)
		
		# Emitir señal manualmente
		battle_manager.emit_signal("attack_declared", attacker, null, "Opponent")
	else:
		print(">>> No hay monstruos del oponente para atacar")
