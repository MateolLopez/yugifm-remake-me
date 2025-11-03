extends Node
@export var battle_scene: PackedScene

func _ready() -> void:
	if GameState.current_opponent_id == "" or GameState.current_opponent_id == null:
		GameState.current_opponent_id = "kaiba"

	if not battle_scene:
		push_error("Asigna Battle Scene en DuelLoader.tscn")
		return

	var player_deck: Array = GameState.resolve_player_deck()
	var opponent_deck: Array = GameState.resolve_opponent_deck()

	var battle = battle_scene.instantiate()
	if battle == null:
		push_error("No se pudo instanciar battle_scene")
		return

	var player_deck_node = battle.get_node_or_null("Deck") 
	if player_deck_node:
		player_deck_node.set("override_deck", player_deck)
	else:
		push_warning("No se encontró nodo 'Deck' en la BattleScene. Ajustá el path.")

	var opponent_deck_node = battle.get_node_or_null("DeckRival/Deck") # 
	if opponent_deck_node:
		opponent_deck_node.set("override_deck", opponent_deck)
	else:
		push_warning("No se encontró nodo 'DeckRival/Deck' en la BattleScene. Ajustá el path.")

	var tree := get_tree()
	var old_scene := tree.current_scene
	tree.root.add_child(battle)
	tree.current_scene = battle
	if is_instance_valid(old_scene):
		old_scene.queue_free()
