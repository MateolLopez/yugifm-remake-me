extends Node
class_name DuelCardDbService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var card_db_service: DuelCardDbService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	card_db_service = bm.card_db_service

func _get_cards_db() -> Array:
	var db_node = get_node_or_null("/root/CardDb")
	if db_node == null:
		db_node = get_node_or_null("../CardDB")
	if db_node == null and get_tree() != null and get_tree().current_scene != null:
		db_node = get_tree().current_scene.get_node_or_null("CardDB")

	if db_node != null:
		if "RAW_CARDS" in db_node:
			var db1: Array = db_node.RAW_CARDS
			print("_get_cards_db via RAW_CARDS size=", db1.size())
			return db1
		if "CARDS" in db_node:
			var dict_cards: Dictionary = db_node.CARDS
			var db2: Array = dict_cards.values()
			print("_get_cards_db via CARDS.values() size=", db2.size())
			return db2

	print("_get_cards_db FAIL: no DB source found")
	return []

func _db_card_has_tag(card_def: Dictionary, wanted_tag: String) -> bool:
	wanted_tag = str(wanted_tag).strip_edges().to_lower()
	if wanted_tag == "":
		return true

	var tags: Array = card_def.get("tags", [])
	for t in tags:
		if str(t).strip_edges().to_lower() == wanted_tag:
			return true
	return false

func _db_card_matches_filters(card_def: Dictionary, filters: Dictionary) -> bool:
	if typeof(card_def) != TYPE_DICTIONARY:
		return false

	if str(card_def.get("kind", "")).to_upper() != "MONSTER":
		return false

	var filter_id := str(filters.get("id", ""))
	var filter_tag := str(filters.get("tag", "")).strip_edges().to_lower()
	var filter_attribute := str(filters.get("attribute", "")).to_upper()
	var filter_race := str(filters.get("race", "")).to_upper()

	var min_level = filters.get("min_level", null)
	var max_level = filters.get("max_level", null)
	var min_atk = filters.get("min_atk", null)
	var max_atk = filters.get("max_atk", null)
	var min_def = filters.get("min_def", null)
	var max_def = filters.get("max_def", null)

	var card_id := str(card_def.get("id", ""))
	var card_attribute := str(card_def.get("attribute", "")).to_upper()
	var card_race := str(card_def.get("race", "")).to_upper()
	var card_level := int(card_def.get("level", 0) if card_def.get("level", 0) != null else 0)
	var card_atk := int(card_def.get("atk", 0) if card_def.get("atk", 0) != null else 0)
	var card_defense := int(card_def.get("def", 0) if card_def.get("def", 0) != null else 0)

	if filter_id != "" and card_id != filter_id:
		return false
	if filter_attribute != "" and card_attribute != filter_attribute:
		return false
	if filter_race != "" and card_race != filter_race:
		return false
	if filter_tag != "" and not _db_card_has_tag(card_def, filter_tag):
		return false

	if min_level != null and card_level < int(min_level):
		return false
	if max_level != null and card_level > int(max_level):
		return false

	if min_atk != null and card_atk < int(min_atk):
		return false
	if max_atk != null and card_atk > int(max_atk):
		return false

	if min_def != null and card_defense < int(min_def):
		return false
	if max_def != null and card_defense > int(max_def):
		return false

	return true

func _get_db_card_by_id(card_id: String) -> Dictionary:
	var db: Array = _get_cards_db()
	if db.is_empty():
		return {}

	for card_def in db:
		if typeof(card_def) != TYPE_DICTIONARY:
			continue

		if str(card_def.get("id", "")) == str(card_id):
			return card_def

	return {}

func _get_db_field_spell_by_name(field_name: String) -> Dictionary:
	field_name = str(field_name).strip_edges().to_lower()

	if field_name == "":
		return {}

	var db: Array = _get_cards_db()

	for card_def in db:
		if typeof(card_def) != TYPE_DICTIONARY:
			continue

		if str(card_def.get("kind", "")).to_upper() != "SPELL":
			continue

		if str(card_def.get("race", "")).to_upper() != "FIELD":
			continue

		if str(card_def.get("cardname", "")).strip_edges().to_lower() == field_name:
			return card_def

	return {}


func _spawn_card_from_db_entry(card_def: Dictionary, controller: String) -> Card:
	var card_scene: PackedScene = preload("res://Scenes/Card.tscn")
	var card: Card = card_scene.instantiate()
	if not is_instance_valid(card):
		return null

	get_tree().current_scene.add_child(card)
	card.apply_db(card_def)

	card.owner_side = ("PLAYER" if card_runtime_service._norm_owner(controller) == "Player" else "OPPONENT")
	if card.has_method("apply_owner_collision_layers"):
		card.apply_owner_collision_layers()
	if card.has_method("set_show_back_only"):
		card.set_show_back_only(false)

	return card

func _db_card_has_any_excluded_tag(card_def: Dictionary, exclude_tags: Array) -> bool:
	for tag in exclude_tags:
		if card_db_service._db_card_has_tag(card_def, str(tag)):
			return true

	return false


func _db_card_matches_spelltrap_filters(card_def: Dictionary, filters: Dictionary) -> bool:
	if typeof(card_def) != TYPE_DICTIONARY:
		return false

	var filter_id := str(filters.get("id", ""))
	var filter_tag := str(filters.get("tag", "")).strip_edges().to_lower()
	var filter_attribute := str(filters.get("attribute", "")).to_upper()
	var filter_race := str(filters.get("race", "")).to_upper()
	var filter_kind := str(filters.get("kind", "ANY")).to_upper()

	var card_kind := str(card_def.get("kind", "")).to_upper()
	var card_id := str(card_def.get("id", ""))
	var card_attribute := str(card_def.get("attribute", "")).to_upper()
	var card_race := str(card_def.get("race", "")).to_upper()

	if card_kind != "SPELL" and card_kind != "TRAP":
		return false

	if filter_kind != "ANY" and filter_kind != "" and card_kind != filter_kind:
		return false

	if filter_id != "" and card_id != filter_id:
		return false
	if filter_attribute != "" and card_attribute != filter_attribute:
		return false
	if filter_race != "" and card_race != filter_race:
		return false
	if filter_tag != "" and not card_db_service._db_card_has_tag(card_def, filter_tag):
		return false

	return true
