extends Node

const SPECIFIC_FUSIONS = {
	"blue_eyes_ultimate_dragon": {
		"result": "000007",
		"required_cards": ["89631139", "89631139", "89631139"], #ACA VAN SIEMPRE LOS PASSCODE, NO EL ID
		"result_atk": 4500,
		"exact_count": true
	},
	"karbonala warrior": {
		"result": "000007",
		"required_cards": ["56342351", "92731455"],
		"result_atk": 1500,
		"exact_count": true
	}
}

func find_fusion(selected_cards: Array):	
	for fusion_id in SPECIFIC_FUSIONS:
		var fusion = SPECIFIC_FUSIONS[fusion_id]

		if _matches_requirements(selected_cards, fusion.required_cards, fusion.exact_count):
			return _create_card_from_fusion_data(fusion)
		else:
			print("No coincide con ", fusion_id)
	
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
