extends Node


var OPPONENTS_DECKS := {
	"kaiba": ["97017120","97017120"],
	"joey":  ["97017120","97017120"],
}

func get_deck_for_opponent(opponent: String) -> Array:
	return OPPONENTS_DECKS.get(opponent, []).duplicate()
