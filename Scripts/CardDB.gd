extends Node
class_name CardDB

@export_file("*.json") var cards_db_path: String = "res://Scripts/JSON/CardsDB.json"

var CARDS: Dictionary = {}

var RAW_CARDS: Array = []

func _ready() -> void:
	load_cards()

func load_cards() -> void:
	CARDS.clear()
	RAW_CARDS.clear()

	if cards_db_path == "" or not FileAccess.file_exists(cards_db_path):
		push_error("CardDB: No existe CardsDB.json en: %s" % cards_db_path)
		return

	var json_text: String = FileAccess.get_file_as_string(cards_db_path)
	var parsed = JSON.parse_string(json_text)

	if parsed == null:
		push_error("CardDB: JSON inválido en %s" % cards_db_path)
		return

	if typeof(parsed) == TYPE_ARRAY:
		RAW_CARDS = parsed
	elif typeof(parsed) == TYPE_DICTIONARY and parsed.has("cards") and typeof(parsed["cards"]) == TYPE_ARRAY:
		RAW_CARDS = parsed["cards"]
	else:
		push_error("CardDB: Formato de CardsDB.json no soportado. Se esperaba Array o {cards:[...]}")
		return

	for c in RAW_CARDS:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var id := str(c.get("id", ""))
		if id == "":
			id = str(c.get("passcode", ""))
		if id == "":
			continue
		CARDS[id] = c

	print("CardDB: cargadas %d cartas (indexadas: %d)" % [RAW_CARDS.size(), CARDS.size()])

func has_card(id: String) -> bool:
	return CARDS.has(id)

func get_card(id: String) -> Dictionary:
	return CARDS.get(id, {})

func get_random_card_id() -> String:
	if CARDS.is_empty():
		return ""
	var keys := CARDS.keys()
	return str(keys[randi_range(0, keys.size() - 1)])
