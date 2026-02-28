extends Node

var DEFAULT_PLAYER_DECK := ["26412047","66788016","79759861","53129443","04732017","69162969"]

func get_deck_by_key(key: String) -> Array:
	var ds = GameState.player_decks.get(key, [])
	if ds.size() > 0:
		return ds.duplicate()
	else:
		return DEFAULT_PLAYER_DECK.duplicate()
