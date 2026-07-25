extends Node

var DEFAULT_PLAYER_DECK := [
	"62403074",
	"56120475",
	"37043180"
]

func get_deck_by_key(key: String) -> Array:
	var ds = GameState.player_decks.get(key, [])
	if ds.size() > 0:
		return ds.duplicate()
	else:
		return DEFAULT_PLAYER_DECK.duplicate()
