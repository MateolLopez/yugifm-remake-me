extends Node

var DEFAULT_PLAYER_DECK := ["44095762","44095762","44095762","23995346","23995346","23995346"]

func get_deck_by_key(key: String) -> Array:
	var ds = GameState.player_decks.get(key, [])
	if ds.size() > 0:
		return ds.duplicate()
	else:
		return DEFAULT_PLAYER_DECK.duplicate()
