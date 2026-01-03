extends Node

const SPECIFIC_FUSIONS = { #TROLLIÉ DE ENTRADA, SE ASIGNAN LOS MATERIALES EN BASE A LOS PASSCODE, NO ID'S
	"blue_eyes_ultimate_dragon": {
		"result": "000007",
		"required_cards": ["89631139", "89631139", "89631139"],
		"result_atk": 4500,
		"exact_count": true
	},
	"karbonala_warrior": {
		"result": "000012",
		"required_cards": ["56342351", "92731455"],
		"result_atk": 1500,
		"exact_count": true
	},
	"skull_knight": {
		"result": "000037",
		"required_cards": ["28725004", "42431843"],
		"result_atk": 2650,
		"exact_count": true
	},
	"hero_flame_wingman": {
		"result": "000103",
		"required_cards": ["21844576", "58932615"],
		"result_atk": 2100,
		"exact_count": true
	},
	"hero_steam_healer": {
		"result": "000104",
		"required_cards": ["58932615", "79979666"],
		"result_atk": 1800,
		"exact_count": true
	},
	"hero_mariner": {
		"result": "000105",
		"required_cards": ["21844576", "79979666"],
		"result_atk": 1400,
		"exact_count": true
	},
	"hero_thunder_giant": {
		"result": "000106",
		"required_cards": ["20721928", "84327329"],
		"result_atk": 2400,
		"exact_count": true
	},
	"hero_necroid_shaman": {
		"result": "000107",
		"required_cards": ["89252153", "86188410"],
		"result_atk": 1900,
		"exact_count": true
	},
	"hero_wild_wingman": {
		"result": "000108",
		"required_cards": ["21844576", "86188410"],
		"result_atk": 1900,
		"exact_count": true
	},
	"hero_tempest": {
		"result": "000109",
		"required_cards": ["21844576", "79979666", "20721928"],
		"result_atk": 2800,
		"exact_count": true
	},
	"hero_wildedge": {
		"result": "000110",
		"required_cards": ["59793705", "86188410"],
		"result_atk": 2650,
		"exact_count": true
	},
	"hero_rampart_blaster": {
		"result": "000111",
		"required_cards": ["58932615", "84327329"],
		"result_atk": 2000,
		"exact_count": true
	},
	"hero_shining_flare_w": {
		"result": "000112",
		"required_cards": ["35809262", "20721928"],
		"result_atk": 2500,
		"exact_count": true
	},
	"hero_mudballman": {
		"result": "000113",
		"required_cards": ["79979666", "84327329"],
		"result_atk": 1900,
		"exact_count": true
	},
	"hero_darkbright": {
		"result": "000114",
		"required_cards": ["20721928", "89252153"],
		"result_atk": 2000,
		"exact_count": true
	},
}

func find_fusion(selected_cards: Array):
	for fusion_id in SPECIFIC_FUSIONS:
		var fusion = SPECIFIC_FUSIONS[fusion_id]

		if _matches_requirements(selected_cards, fusion.required_cards, fusion.exact_count):
			return _create_card_from_fusion_data(fusion)
		else:
			print("")
	
	# Fusión fallida - devolver la última carta
	if selected_cards.size() > 0:
		return selected_cards[selected_cards.size() - 1]
	else:
		return null

func _create_card_from_fusion_data(fusion_data):
	
	var card_scene = preload("res://Scenes/Card.tscn")
	if not card_scene:
		return null

	var new_card = card_scene.instantiate()
	if not new_card:
		return null
	
	get_tree().current_scene.add_child(new_card)
	
	var card_db = preload("res://Scripts/CardDB.gd")
	if not card_db:
		new_card.queue_free()
		return null
	
	var card_data = card_db.CARDS.get(fusion_data.result)
	if not card_data:
		new_card.queue_free()
		return null
	
	new_card.apply_db(card_data)
	new_card.fusion_result = true
	return new_card

func _matches_requirements(selected_cards: Array, required_card_ids: Array, exact_count: bool) -> bool:	
	# Verificar cantidad exacta si es necesario
	if exact_count and selected_cards.size() != required_card_ids.size():
		return false
	
	# Crear arrays de IDs para comparación
	var selected_ids = []
	for card in selected_cards:
		selected_ids.append(card.passcode)
	
	var selected_ids_copy = selected_ids.duplicate()
	
	# Verificar que cada ID requerido esté en las seleccionadas
	for required_id in required_card_ids:
		var found_index = selected_ids_copy.find(required_id)
		if found_index == -1:
			return false
		# Remover el ID encontrado para evitar duplicados
		selected_ids_copy.remove_at(found_index)
	
	return true
