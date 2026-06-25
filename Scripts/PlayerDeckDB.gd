extends Node

var DEFAULT_PLAYER_DECK := ["91152256",
"89272878",
"89091579",
"88753985",
"86421986",
"88435542",
"86088138",
"85255550",
"84285623",
"82742611",
"77603950",
"77581312",
"76704943",
"75889523",
"75356564",
"70924884",
"68963107",
"63125616",
"62793020",
"61454890"]

func get_deck_by_key(key: String) -> Array:
	var ds = GameState.player_decks.get(key, [])
	if ds.size() > 0:
		return ds.duplicate()
	else:
		return DEFAULT_PLAYER_DECK.duplicate()
