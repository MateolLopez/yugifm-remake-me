extends Node

var DEFAULT_PLAYER_DECK := [
	"90219263",
	"90219263",
	"90219263","76812113","76812113","76812113","40619825","40619825","40619825"
]

func get_deck_by_key(key: String) -> Array:
	var ds = GameState.player_decks.get(key, [])
	if ds.size() > 0:
		return ds.duplicate()
	else:
		return DEFAULT_PLAYER_DECK.duplicate()
