extends Node
class_name CardDB

var _cards_by_id: Dictionary = {}
var _loaded := false

const CARDS_PATH := "res://Scripts/JSON/CardsDB.json"

func _ready() -> void:
	_load_cards_if_needed()

func _load_cards_if_needed() -> void:
	if _loaded:
		return
	_loaded = true

	var file := FileAccess.open(CARDS_PATH, FileAccess.READ)
	if file == null:
		push_error("CardDB: no se pudo abrir %s" % CARDS_PATH)
		return

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("CardDB: JSON inválido en %s" % CARDS_PATH)
		return

	_cards_by_id.clear()

	# Acepta dos formatos:
	# 1) Array de objetos: [{id: "...", ...}, ...]
	# 2) Objeto/dict: {"8963...": {...}, "2285...": {...}}
	if parsed is Array:
		for entry in parsed:
			if entry is Dictionary and entry.has("id"):
				_cards_by_id[str(entry["id"])] = entry
	elif parsed is Dictionary:
		for k in parsed.keys():
			var entry = parsed[k]
			if entry is Dictionary:
				if not entry.has("id"):
					entry = entry.duplicate(true)
					entry["id"] = str(k)
				_cards_by_id[str(entry["id"])] = entry
	else:
		push_error("CardDB: formato no soportado en %s" % CARDS_PATH)

func has_card(id: String) -> bool:
	_load_cards_if_needed()
	return _cards_by_id.has(id)

func get_card(id: String) -> Dictionary:
	_load_cards_if_needed()
	return _cards_by_id.get(id, {})

func get_all_cards() -> Array:
	_load_cards_if_needed()
	return _cards_by_id.values()
