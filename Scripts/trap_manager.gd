extends Node

@onready var effect_manager = null
@onready var battle_manager = null

var _signals_connected = false

func _ready():
	await get_tree().process_frame
	_initialize()

func _initialize():
	battle_manager = get_tree().get_first_node_in_group("battle_manager")
	effect_manager = get_tree().get_first_node_in_group("effect_manager")
	
	if battle_manager and effect_manager:
		_connect_signals()
	else:
		await get_tree().create_timer(1.0).timeout
		_initialize()

func _connect_signals():
	if _signals_connected:
		return
	
	print(">>> Conectando señales del BattleManager...")
	
	# Desconectar primero para evitar duplicados
	if battle_manager.attack_declared.is_connected(_on_attack_declared):
		battle_manager.attack_declared.disconnect(_on_attack_declared)
	if battle_manager.monster_played.is_connected(_on_monster_played):
		battle_manager.monster_played.disconnect(_on_monster_played)
	if battle_manager.spell_activated.is_connected(_on_spell_activated):
		battle_manager.spell_activated.disconnect(_on_spell_activated)
	if battle_manager.turn_started.is_connected(_on_turn_started):
		battle_manager.turn_started.disconnect(_on_turn_started)
	if battle_manager.turn_ended.is_connected(_on_turn_ended):
		battle_manager.turn_ended.disconnect(_on_turn_ended)
	
	# Conectar señales
	battle_manager.attack_declared.connect(_on_attack_declared)
	battle_manager.monster_played.connect(_on_monster_played)
	battle_manager.spell_activated.connect(_on_spell_activated)
	battle_manager.turn_started.connect(_on_turn_started)
	battle_manager.turn_ended.connect(_on_turn_ended)
	
	_signals_connected = true
	
	print(">>> Señales conectadas exitosamente")
	print(">>> - attack_declared: ", battle_manager.attack_declared.is_connected(_on_attack_declared))
	print(">>> - monster_played: ", battle_manager.monster_played.is_connected(_on_monster_played))
	print(">>> - spell_activated: ", battle_manager.spell_activated.is_connected(_on_spell_activated))

# El resto de las funciones se mantienen igual...
func _on_attack_declared(attacker, defender, attacker_owner):
	print(">>> TRAP_MANAGER: Señal attack_declared recibida")
	print(">>>   Atacante: ", attacker.card_name if attacker else "null")
	print(">>>   Defensor: ", defender.card_name if defender else "null") 
	print(">>>   Owner atacante: ", attacker_owner)
	
	var context = {
		"attacker": attacker,
		"defender": defender,
		"attacker_card_owner": attacker_owner
	}
	
	effect_manager.check_trap_triggers(
		effect_manager.TriggerCondition.OPPONENT_ATTACK_DECLARED,
		context
	)

func _on_monster_played(monster, card_owner):
	print(">>> TRAP_MANAGER: Señal monster_played recibida")
	print(">>>   Monstruo: ", monster.card_name)
	print(">>>   ATK: ", monster.Atk)
	print(">>>   Owner: ", card_owner)
	
	var context = {
		"monster": monster,
		"monster_card_owner": card_owner,
		"atk": monster.Atk
	}
	
	effect_manager.check_trap_triggers(
		effect_manager.TriggerCondition.OPPONENT_MONSTER_PLAYED,
		context
	)

func _on_spell_activated(spell, card_owner):
	print(">>> TRAP_MANAGER: Señal spell_activated recibida")
	var context = {
		"spell": spell,
		"spell_card_owner": card_owner
	}
	effect_manager.check_trap_triggers(
		effect_manager.TriggerCondition.OPPONENT_SPELL_ACTIVATED,
		context
	)

func _on_turn_started(turn_owner):
	print(">>> TRAP_MANAGER: Señal turn_started recibida")
	var context = {
		"turn_card_owner": turn_owner
	}
	effect_manager.check_trap_triggers(
		effect_manager.TriggerCondition.TURN_START,
		context
	)

func _on_turn_ended(turn_owner):
	print(">>> TRAP_MANAGER: Señal turn_ended recibida")
	var context = {
		"turn_owner": turn_owner
	}
	effect_manager.check_trap_triggers(
		effect_manager.TriggerCondition.TURN_END,
		context
	)
