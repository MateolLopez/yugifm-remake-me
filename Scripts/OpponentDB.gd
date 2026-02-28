extends Node


var OPPONENTS_DECKS := {
	"kaiba": ["04732017","99426834","99426834","99426834"],
	"joey":  ["04732017","99426834","99426834","99426834"],
}

func get_deck_for_opponent(opponent: String) -> Array:
	return OPPONENTS_DECKS.get(opponent, []).duplicate()
