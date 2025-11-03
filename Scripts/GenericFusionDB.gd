extends Node

const GENERIC_FUSIONS = {
	"celtic_guardian": {
		"result": "000008",
		"required_tags": [["elf"], ["warrior"]],
		"result_atk": 1400,
		"priority": 1.0
	},
	"gokibore":{
		"result": "000014",
		"required_tags": [["insect"],["ball"]],
		"result_atk": 1200,
		"priority": 1.1
	},
	"ancient_elf":{
		"result": "000016",
		"required_tags": [["elf"],["spellcaster"]],
		"result_atk": 1450,
		"priority": 1.2
	},
	"gruesome_goo":{
		"result": "000023",
		"required_tags":[["slime"],["slime","water"]],
		"result_atk": 1300,
		"priority": 1.3
	}
}

func find_fusion(card1, card2):
	# REGLA: Ningún material puede tener ATK >= al resultado
	var possible_fusions = []
	
	for fusion_id in GENERIC_FUSIONS:
		var fusion = GENERIC_FUSIONS[fusion_id]
		
		if card1.Atk >= fusion.result_atk or card2.Atk >= fusion.result_atk:
			continue
			
		if _tags_match_distributed(card1.tags, card2.tags, fusion.required_tags):
			possible_fusions.append({
				"fusion_id": fusion_id,
				"result_card_id": fusion.result,
				"result_atk": fusion.result_atk,
				"priority": fusion.priority
			})
	
	possible_fusions.sort_custom(_sort_fusions)
	
	if possible_fusions.size() > 0:
		return _create_card_from_fusion_data(possible_fusions[0])
	else:
		return card2

func _create_card_from_fusion_data(fusion_data):
	var card_scene = preload("res://Scenes/Card.tscn")
	if not card_scene:
		return null
	var new_card = card_scene.instantiate()
	if not new_card:
		return null

	var card_db = preload("res://Scripts/CardDB.gd")
	if not card_db:
		new_card.queue_free()
		return null
	var card_data = card_db.CARDS.get(fusion_data.result_card_id)
	if not card_data:
		new_card.queue_free()
		return null

	new_card.apply_db(card_data)
	new_card.fusion_result = true
	return new_card


func _tags_match_distributed(tags1: Array, tags2: Array, required_groups: Array) -> bool:
	if required_groups.size() != 2:
		return false
		
	var options1 = required_groups[0]
	var options2 = required_groups[1]
	
	var case1 = _has_any_tag(tags1, options1) and _has_any_tag(tags2, options2)
	var case2 = _has_any_tag(tags1, options2) and _has_any_tag(tags2, options1)
	
	return case1 or case2

func _has_any_tag(card_tags: Array, required_options: Array) -> bool:
	for tag in required_options:
		if card_tags.has(tag):
			return true
	return false

func _sort_fusions(a, b):
	if a.result_atk != b.result_atk:
		return a.result_atk < b.result_atk
	else:
		return a.priority > b.priority
