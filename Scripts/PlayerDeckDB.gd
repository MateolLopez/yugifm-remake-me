extends Node

var DEFAULT_PLAYER_DECK := ["000183","000183","000184","000184","000003"]
#var DEFAULT_PLAYER_DECK := ["000094","000094","000094","000095","000095","000095","000096","000096","000096","000097","000097","000097","000098","000098","000098","000099","000099","000099","000100","000100","000100","000101","000101","000101"]
#var DEFAULT_PLAYER_DECK := ["000010","000010","000010","000011","000011","000011","000009","000009","000009"]

func get_deck_by_key(key: String) -> Array:
	var ds = GameState.player_decks.get(key, [])
	if ds.size() > 0:
		return ds.duplicate()
	else:
		return DEFAULT_PLAYER_DECK.duplicate()
