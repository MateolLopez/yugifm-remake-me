extends Node

const PATH := "res://Scripts/JSON/opponentdb.json"

var _opponent_decks: Dictionary = {}

func _ready() -> void:
	_load_opponent_db()

func _load_opponent_db() -> void:
	_opponent_decks.clear()

	if not FileAccess.file_exists(PATH):
		push_error("OpponentDB: No se encontró opponentdb.json en: %s" % PATH)
		return

	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("OpponentDB: No se pudo abrir opponentdb.json: %s" % PATH)
		return

	var parsed = JSON.parse_string(f.get_as_text())
	f.close()

	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("OpponentDB: opponentdb.json debe ser un objeto JSON.")
		return

	var opponents = parsed.get("opponents", null)
	if typeof(opponents) != TYPE_ARRAY:
		push_error("OpponentDB: opponentdb.json debe tener 'opponents' como Array.")
		return

	for o in opponents:
		if typeof(o) != TYPE_DICTIONARY:
			continue
		var id := str(o.get("id", "")).strip_edges()
		if id == "":
			continue
		var deck = o.get("deck", [])
		if typeof(deck) != TYPE_ARRAY:
			deck = []
		var deck_str: Array = []
		for c in deck:
			var s := str(c)
			if s != "":
				deck_str.append(s)
		_opponent_decks[id] = deck_str

func get_deck_for_opponent(opponent: String) -> Array:
	var key := str(opponent).strip_edges()
	var deck: Array = _opponent_decks.get(key, [])
	return deck.duplicate()

func reload() -> void:
	_load_opponent_db()
