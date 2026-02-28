extends Node
class_name FusionRepository

var cards_by_id: Dictionary = {}
var generic_fusions: Array = []
var specific_fusions: Array = []

func load_all(cards_db_path: String, generic_path: String, specific_path: String) -> void:
	cards_by_id = _load_cards(cards_db_path)
	generic_fusions = _load_array(generic_path)
	specific_fusions = _load_array(specific_path)

func get_card_def(id: String) -> Dictionary:
	return cards_by_id.get(id, {})

func has_card(id: String) -> bool:
	return cards_by_id.has(id)

func _load_cards(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("FusionRepository: no existe CardsDB: %s" % path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_ARRAY:
		var d: Dictionary = {}
		for c in parsed:
			if c is Dictionary and c.has("id"):
				d[str(c["id"])] = c
		return d
	if typeof(parsed) == TYPE_DICTIONARY:
		# permitir formato {"cards": [...]} o {id: {...}}
		if parsed.has("cards") and parsed["cards"] is Array:
			var d2: Dictionary = {}
			for c2 in parsed["cards"]:
				if c2 is Dictionary and c2.has("id"):
					d2[str(c2["id"])] = c2
			return d2
		return parsed
	push_error("FusionRepository: CardsDB.json formato no soportado")
	return {}

func _load_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("FusionRepository: no existe JSON: %s" % path)
		return []
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) == TYPE_ARRAY:
		return parsed
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("items") and parsed["items"] is Array:
		return parsed["items"]
	push_error("FusionRepository: JSON debe ser Array o {items:[...]}: %s" % path)
	return []
