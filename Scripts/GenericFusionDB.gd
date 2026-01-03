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
	},
	"trent":{
		"result": "000006",
		"required_tags":[["tree","wood"],["sage","immortal"]],
		"result_atk": 1500,
		"priority": 1.4
	},
	"bolt_escargot":{
		"result": "000025",
		"required_tags": [["thunder"],["snail"]],
		"result_atk": 1400,
		"priority": 1.5
	},
	"air_eater":{
		"result": "000026",
		"required_tags": [["air","wind"],["fiend"]],
		"result_atk": 2100,
		"priority": 1.6
	},
	"big_eye":{
		"result": "000031",
		"required_tags": [["eye"],["fiend"]],
		"result_atk": 1200,
		"priority": 1.7
	},
	"the_judgement_hand":{
		"result": "000034",
		"required_tags":[["hand"],["warrior"]],
		"result_atk": 1400,
		"priority": 0.6
	},
	"gearfried_iron_knight":{
		"result": "000041",
		"required_tags":[["armor"],["warrior"]],
		"result_atk": 1800,
		"priority": 1.9
	},
	"fire_reaper":{
		"result": "000043",
		"required_tags":[["fire","pyro"],["zombie"]],
		"result_atk": 700,
		"priority": 2.0
	},
	"dokuroizo":{
		"result": "000044",
		"required_tags":[["skull"],["zombie"]],
		"result_atk": 900,
		"priority": 2.1
	},
	"rhaimundos_redsword":{
		"result": "000045",
		"required_tags":[["warrior"],["fire"]],
		"result_atk": 1200,
		"priority": 2.2
	},
	"akihiron":{
		"result":"000046",
		"required_tags":[["insect"],["water","aqua"]],
		"result_atk": 1700,
		"priority": 2.3
	},
	"toad_master":{
		"result":"000054",
		"required_tags":[["toad"],["spellcaster"]],
		"result_atk":1000,
		"priority": 0.9
	},
	"dragon_statue":{
		"result":"000056",
		"required_tags":[["warrior"],["dragon"]],
		"result_atk":1100,
		"priority": 0.9
	},
	"octoberser":{
		"result":"000061",
		"required_tags":[["water","fish"],["tentacle"]],
		"result_atk":1600,
		"priority": 2.4
	},
	"lamoon":{
		"result":"000063",
		"required_tags":[["fairy","light"],["spellcaster"]],
		"result_atk":1200,
		"priority": 1.1
	},
	"ansatsu":{
		"result":"000064",
		"required_tags":[["ninja"],["warrior"]],
		"result_atk": 1700,
		"priority": 1.3
	},
	"faith_bird":{
		"result":"000065",
		"required_tags":[["light"],["winged-beast"]],
		"result_atk": 1700,
		"priority": 1.3
	},
	"crimson_sunbird":{
		"result":"000073",
		"required_tags":[["winged-beast","bird"],["fire","pyro"]],
		"result_atk": 2300,
		"priority": 2.3
	},
	"giant_flea":{
		"result":"000139",
		"required_tags":[["insect"],["earth","insect"]],
		"result_atk": 1500,
		"priority": 1.4
	},
	"kwagar_hercules":{
		"result":"000078",
		"required_tags":[["insect"],["earth","insect"]],
		"result_atk": 1900,
		"priority": 1.8
	},
	"gemini_elf":{
		"result":"000079",
		"required_tags":[["elf"],["elf"]],
		"result_atk": 1900,
		"priority": 1.7
	},
	"mystical_sand":{
		"result":"000080",
		"required_tags":[["rock"],["spellcaster"]],
		"result_atk": 2100,
		"priority": 2.1
	},
	"flame_cerebrus":{
		"result":"000082",
		"required_tags":[["fire","pyro"],["beast"]],
		"result_atk": 2100,
		"priority": 2.2
	},
	"spirit_mountain":{
		"result":"000085",
		"required_tags":[["earth"],["spellcaster"]],
		"result_atk": 1300,
		"priority": 1.3
	},
	"turtle_bird":{
		"result":"000089",
		"required_tags":[["turtle"],["winged-beast"]],
		"result_atk": 1900,
		"priority": 1.5
	},
	"fire_kraken":{
		"result":"000090",
		"required_tags":[["fire","pyro"],["tentacle"]],
		"result_atk": 1600,
		"priority": 1.2
	},
	"boulder_tortoise":{
		"result":"000091",
		"required_tags":[["rock"],["turtle"]],
		"result_atk": 1450,
		"priority": 1.45
	},
	"turtle_tiger":{
		"result":"000122",
		"required_tags":[["turtle"],["beast"]],
		"result_atk": 1000,
		"priority": 0.7
	},
	"violent_rain":{
		"result":"000136",
		"required_tags":[["aqua","cloud"],["thunder","cloud"]],
		"result_atk": 1550,
		"priority": 1.5
	},
	"water_magician":{
		"result":"000137",
		"required_tags":[["water","aqua"],["spellcaster"]],
		"result_atk": 1400,
		"priority": 1.0
	},
	"giant_red_ss":{
		"result":"000137",
		"required_tags":[["water","aqua"],["sea-serpent"]],
		"result_atk": 1800,
		"priority": 1.0
	},
	"roaring_ocean":{
		"result":"000145",
		"required_tags":[["water","aqua"],["sea-serpent"]],
		"result_atk": 2100,
		"priority": 2.0
	},
	"granadora":{
		"result":"000143",
		"required_tags":[["water","aqua"],["reptile"]],
		"result_atk": 1900,
		"priority": 1.8
	},
	"flying_peng":{
		"result":"000144",
		"required_tags":[["water","aqua"],["w-beast"]],
		"result_atk": 1200,
		"priority": 1.2
	},
	"kuwagata":{
		"result":"000146",
		"required_tags":[["b-warrior"],["insect"]],
		"result_atk": 1250,
		"priority": 1.2
	},
	"rude_kaiser":{
		"result":"000147",
		"required_tags":[["b-warrior"],["reptile"]],
		"result_atk": 1800,
		"priority": 1.8
	},
	"giga_tech_w":{
		"result":"000148",
		"required_tags":[["beast"],["machine"]],
		"result_atk": 1200,
		"priority": 1.2
	},
	"witty_phant":{
		"result":"000058",
		"required_tags":[["fiend"],["spellcaster"]],
		"result_atk": 1400,
		"priority": 1.4
	},
	"ocubeam":{
		"result":"000149",
		"required_tags":[["fairy"],["beast"]],
		"result_atk": 1550,
		"priority": 1.5
	},
	"uraby":{
		"result":"000150",
		"required_tags":[["dinosaur"],["dark","fiend"]],
		"result_atk": 1500,
		"priority": 1.3
	},
	"cyber_saurus":{
		"result":"000151",
		"required_tags":[["dinosaur"],["machine"]],
		"result_atk": 1800,
		"priority": 1.7
	},
	"thunder_dragon":{
		"result":"000152",
		"required_tags":[["thunder"],["dragon"]],
		"result_atk": 1600,
		"priority": 1.4
	},
	"bean_soldier":{
		"result":"000153",
		"required_tags":[["plant"],["warrior"]],
		"result_atk": 1400,
		"priority": 1.3
	},
	"mavelus":{
		"result":"000154",
		"required_tags":[["fire","pyro"],["w-beast"]],
		"result_atk": 1300,
		"priority": 1.2
	},
	"cockr_knight":{
		"result":"000155",
		"required_tags":[["insect"],["warrior"]],
		"result_atk": 800,
		"priority": 0.6
	},
	"spike_seadra":{
		"result":"000156",
		"required_tags":[["sea-serpent","dragon"],["sea-serpent"]],
		"result_atk": 1600,
		"priority": 1.6
	},
	"serpent_night_d":{
		"result":"000157",
		"required_tags":[["dragon"],["sea-serpent"]],
		"result_atk": 2350,
		"priority": 2.0
	},
	"tripwire_b":{
		"result":"000158",
		"required_tags":[["thunder"],["beast"]],
		"result_atk": 1200,
		"priority": 1.0
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
