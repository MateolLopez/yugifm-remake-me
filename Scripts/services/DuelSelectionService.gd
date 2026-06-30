extends Node
class_name DuelSelectionService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service

func _runtime_card_has_tag(card: Node, tag: String) -> bool:
	if not is_instance_valid(card):
		return false

	tag = str(tag).strip_edges().to_lower()

	if tag == "":
		return true

	if not ("tags" in card):
		return false

	if typeof(card.tags) != TYPE_ARRAY:
		return false

	for t in card.tags:
		if str(t).strip_edges().to_lower() == tag:
			return true

	return false

func _runtime_card_has_any_excluded_tag(card: Node, exclude_tags: Array) -> bool:
	for tag in exclude_tags:
		if _runtime_card_has_tag(card, str(tag)):
			return true

	return false

func _runtime_monster_matches_filters(card: Node, filters: Dictionary, exclude_tags: Array = []) -> bool:
	if not is_instance_valid(card):
		return false

	if card_runtime_service._card_kind(card) != "MONSTER":
		return false

	if _runtime_card_has_any_excluded_tag(card, exclude_tags):
		return false

	var filter_id := str(filters.get("id", "")).strip_edges()
	var filter_tag := str(filters.get("tag", "")).strip_edges().to_lower()
	var filter_attribute := str(filters.get("attribute", "")).strip_edges().to_upper()
	var filter_race := str(filters.get("race", "")).strip_edges().to_upper()

	var min_level = filters.get("min_level", null)
	var max_level = filters.get("max_level", null)
	var min_atk = filters.get("min_atk", null)
	var max_atk = filters.get("max_atk", null)
	var min_def = filters.get("min_def", null)
	var max_def = filters.get("max_def", null)

	if filter_id != "" and ("id" in card) and str(card.id) != filter_id:
		return false

	if filter_tag != "" and not _runtime_card_has_tag(card, filter_tag):
		return false

	if filter_attribute != "":
		var attr := ""
		if card.has_method("get_effective_attribute"):
			attr = str(card.get_effective_attribute()).to_upper()
		elif "attribute" in card:
			attr = str(card.attribute).to_upper()

		if attr != filter_attribute:
			return false

	if filter_race != "":
		var race := ""
		if card.has_method("get_effective_race"):
			race = str(card.get_effective_race()).to_upper()
		elif "race" in card:
			race = str(card.race).to_upper()

		if race != filter_race:
			return false

	var lv := 0
	if card.has_method("get_effective_level"):
		lv = int(card.get_effective_level())
	elif "level" in card:
		lv = int(card.level)

	var atk_value := 0
	if card.has_method("get_effective_atk"):
		atk_value = int(card.get_effective_atk())
	elif "atk" in card:
		atk_value = int(card.atk)

	var def_value := 0
	if card.has_method("get_effective_def"):
		def_value = int(card.get_effective_def())
	elif "def" in card:
		def_value = int(card.def)

	if min_level != null and lv < int(min_level):
		return false

	if max_level != null and lv > int(max_level):
		return false

	if min_atk != null and atk_value < int(min_atk):
		return false

	if max_atk != null and atk_value > int(max_atk):
		return false

	if min_def != null and def_value < int(min_def):
		return false

	if max_def != null and def_value > int(max_def):
		return false

	return true

func _find_first_controlled_monster(owner: String, filters: Dictionary, exclude_tags: Array = []) -> Node:
	owner = card_runtime_service._norm_owner(owner)

	var cards: Array = []

	if owner == "Player":
		cards = bm.player_cards_on_battlefield.duplicate()
	elif owner == "Opponent":
		cards = bm.opponent_cards_on_battlefield.duplicate()
	else:
		return null

	for card in cards:
		if _runtime_monster_matches_filters(card, filters, exclude_tags):
			return card

	return null
