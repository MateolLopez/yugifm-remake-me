extends Node

@export var battle_scene: PackedScene


func _ready() -> void:
	GameState.ensure_current_opponent_id()

	if not battle_scene:
		push_error("Asigna Battle Scene en DuelLoader.tscn")
		return

	var opponent_data := GameState.resolve_current_opponent_data()
	if opponent_data.is_empty():
		push_error("No se pudo resolver opponent_data para id=%s" % str(GameState.current_opponent_id))
		return

	var player_deck: Array = GameState.resolve_player_deck()
	var opponent_deck: Array = GameState.resolve_opponent_deck()

	var battle = battle_scene.instantiate()
	if battle == null:
		push_error("No se pudo instanciar battle_scene")
		return

	_inject_decks_into_battle(battle, player_deck, opponent_deck)

	var tree := get_tree()
	var old_scene := tree.current_scene

	tree.root.add_child(battle)
	tree.current_scene = battle

	_configure_battle_presentation(battle, opponent_data)
	_configure_battle_opponent_info(battle, opponent_data)

	if is_instance_valid(old_scene):
		old_scene.queue_free()


func _inject_decks_into_battle(battle: Node, player_deck: Array, opponent_deck: Array) -> void:
	var player_deck_node = battle.get_node_or_null("Deck")
	if player_deck_node:
		player_deck_node.set("override_deck", player_deck)
	else:
		push_warning("No se encontró nodo 'Deck' en la BattleScene. Ajustá el path.")

	var opponent_deck_node = battle.get_node_or_null("DeckRival/Deck")
	if opponent_deck_node:
		opponent_deck_node.set("override_deck", opponent_deck)
	else:
		push_warning("No se encontró nodo 'DeckRival/Deck' en la BattleScene. Ajustá el path.")


func _configure_battle_presentation(battle: Node, opponent_data: Dictionary) -> void:
	if not is_instance_valid(battle):
		return

	var fxm := battle.get_node_or_null("DuelFxManager")
	if fxm == null:
		push_warning("No se encontró DuelFxManager en la BattleScene.")
		return

	if fxm.has_method("configure_for_opponent"):
		fxm.configure_for_opponent(opponent_data)
	else:
		push_warning("DuelFxManager no tiene configure_for_opponent(opponent_data).")


func _configure_battle_opponent_info(battle: Node, opponent_data: Dictionary) -> void:
	var display_name := GameState.resolve_current_opponent_display_name()

	# Opcional. Solo funciona si existe un label con este nombre.
	var label = battle.get_node_or_null("OpponentName")
	if label != null and "text" in label:
		label.text = display_name

	# Opcional. Guardar metadata en la battle por si luego otros nodos la necesitan.
	battle.set_meta("opponent_id", str(opponent_data.get("id", "")))
	battle.set_meta("opponent_name", display_name)
	battle.set_meta("opponent_data", opponent_data.duplicate(true))
