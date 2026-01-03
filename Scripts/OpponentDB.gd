extends Node


var OPPONENTS_DECKS := {
	"kaiba": ["000000","000001"],
	"joey":  ["000000","000001"],
}

func get_deck_for_opponent(opponent: String) -> Array:
	return OPPONENTS_DECKS.get(opponent, []).duplicate()
