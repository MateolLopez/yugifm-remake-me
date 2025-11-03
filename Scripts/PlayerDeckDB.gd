extends Node

var DEFAULT_PLAYER_DECK := ["000023","000010","000010","000009","000009","000000"]
#var DEFAULT_PLAYER_DECK := ["000000","000000","000000","000000","000000","000003","000005","000005"]

func get_deck_by_key(key: String) -> Array:
	var ds = GameState.player_decks.get(key, [])
	if ds.size() > 0:
		return ds.duplicate()
	else:
		return DEFAULT_PLAYER_DECK.duplicate()
