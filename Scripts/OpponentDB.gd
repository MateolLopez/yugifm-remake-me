extends Node

const PATH := "res://Scripts/JSON/opponentdb.json"
const DEFAULT_OPPONENT_ID := "kaiba_01"

var _opponents_by_id: Dictionary = {}
var _opponent_ids: Array[String] = []


func _ready() -> void:
	_load_opponent_db()


func _load_opponent_db() -> void:
	_opponents_by_id.clear()
	_opponent_ids.clear()

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

	for raw_opp in opponents:
		if typeof(raw_opp) != TYPE_DICTIONARY:
			continue

		var opponent := _normalize_opponent_data(raw_opp)
		var id := str(opponent.get("id", "")).strip_edges()

		if id == "":
			continue

		_opponents_by_id[id] = opponent
		_opponent_ids.append(id)


func _normalize_opponent_data(raw_opp: Dictionary) -> Dictionary:
	var id := str(raw_opp.get("id", "")).strip_edges()

	var name_data = raw_opp.get("name", {})
	if typeof(name_data) != TYPE_DICTIONARY:
		var legacy_name := str(name_data).strip_edges()
		name_data = {
			"western": legacy_name,
			"eastern": legacy_name
		}

	var deck_raw = raw_opp.get("deck", [])
	var deck_str: Array[String] = []

	if typeof(deck_raw) == TYPE_ARRAY:
		for c in deck_raw:
			var s := str(c).strip_edges()
			if s != "":
				deck_str.append(s)

	var opponent := {
		"id": id,
		"name": {
			"western": str(name_data.get("western", id)).strip_edges(),
			"eastern": str(name_data.get("eastern", name_data.get("western", id))).strip_edges()
		},
		"deck": deck_str,
		"background": str(raw_opp.get("background", "")).strip_edges(),
		"music": str(raw_opp.get("music", "")).strip_edges()
	}

	return opponent


func has_opponent(opponent_id: String) -> bool:
	var key := _resolve_legacy_id(opponent_id)
	return _opponents_by_id.has(key)


func get_opponent_data(opponent_id: String, fallback_id: String = DEFAULT_OPPONENT_ID) -> Dictionary:
	var key := _resolve_legacy_id(opponent_id)

	if _opponents_by_id.has(key):
		return (_opponents_by_id[key] as Dictionary).duplicate(true)

	var fallback_key := _resolve_legacy_id(fallback_id)

	if _opponents_by_id.has(fallback_key):
		return (_opponents_by_id[fallback_key] as Dictionary).duplicate(true)

	return {}


func get_deck_for_opponent(opponent_id: String) -> Array:
	var data := get_opponent_data(opponent_id)

	if data.is_empty():
		return []

	var deck: Array = data.get("deck", [])
	return deck.duplicate()


func get_display_name_for_opponent(opponent_id: String, name_style: String = "western") -> String:
	var data := get_opponent_data(opponent_id)

	if data.is_empty():
		return "Unknown Duelist"

	var names = data.get("name", {})

	if typeof(names) == TYPE_DICTIONARY:
		var selected := str(names.get(name_style, "")).strip_edges()
		if selected != "":
			return selected

		var western := str(names.get("western", "")).strip_edges()
		if western != "":
			return western

		var eastern := str(names.get("eastern", "")).strip_edges()
		if eastern != "":
			return eastern

	return str(data.get("id", "Unknown Duelist"))


func get_all_opponent_ids() -> Array[String]:
	return _opponent_ids.duplicate()


func reload() -> void:
	_load_opponent_db()


func _resolve_legacy_id(opponent_id: String) -> String:
	var key := str(opponent_id).strip_edges()

	# Compatibilidad temporal con saves o código viejo.
	if key == "kaiba":
		return "kaiba_01"

	if key == "joey":
		return "joey_01"

	return key
