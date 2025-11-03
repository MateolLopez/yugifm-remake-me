extends Node

var generic_db
var specific_db

var generic_materials: Array = []
var specific_materials: Array = []

var fusion_performed_this_turn: bool = false
var pending_fusion_card = null
var fusion_in_progress: bool = false

# Señales
signal fusion_performed(result)
signal materials_updated(generic_count, specific_count)
signal fusion_error(message)
signal fusion_card_ready(card)

func _ready() -> void:
	# Cargar las bases de datos
	generic_db = preload("res://Scripts/GenericFusionDB.gd").new()
	specific_db = preload("res://Scripts/SpecificFusionDB.gd").new()
	add_child(generic_db)
	add_child(specific_db)

# === GESTIÓN DE MATERIALES ===
func add_material(card, fusion_type: String) -> bool:
	if fusion_performed_this_turn or fusion_in_progress:
		emit_signal("fusion_error", "Ya realizaste una fusión este turno")
		return false
	
	if fusion_type == "generic" and specific_materials.size() > 0:
		emit_signal("fusion_error", "Ya tienes materiales para fusión específica seleccionados")
		return false
	elif fusion_type == "specific" and generic_materials.size() > 0:
		emit_signal("fusion_error", "Ya tienes materiales para fusión genérica seleccionados")
		return false
	
	var target_array = generic_materials if fusion_type == "generic" else specific_materials
	
	if target_array.has(card):
		return false
	
	target_array.append(card)
	_update_card_visual(card, true, fusion_type)
	materials_updated.emit(generic_materials.size(), specific_materials.size())
	return true

func remove_material(card):
	if generic_materials.has(card):
		generic_materials.erase(card)
		_update_card_visual(card, false, "generic")
	elif specific_materials.has(card):
		specific_materials.erase(card)
		_update_card_visual(card, false, "specific")
	
	materials_updated.emit(generic_materials.size(), specific_materials.size())

func clear_materials():
	for card in generic_materials:
		_update_card_visual(card, false, "generic")
	for card in specific_materials:
		_update_card_visual(card, false, "specific")
	
	generic_materials.clear()
	specific_materials.clear()
	materials_updated.emit(0, 0)

func _update_card_visual(card, selected: bool, _fusion_type: String):
	if selected:
		card.modulate = Color(1.2, 1.2, 1.2)
	else:
		card.modulate = Color(1, 1, 1)

func try_fusion(fusion_owner: String) -> Dictionary:
	if fusion_performed_this_turn or fusion_in_progress:
		return {"success": false, "message": "Ya se realizó una fusión este turno"}
	
	if pending_fusion_card:
		return {"success": false, "message": "Fusión pendiente a colocar"}
	
	if generic_materials.size() >= 2 and specific_materials.size() == 0:
		return _execute_generic_fusion(fusion_owner)
	elif specific_materials.size() >= 2 and generic_materials.size() == 0:
		return _execute_specific_fusion(fusion_owner)
	else:
		return {"success": false, "message": "Faltan materiales o mezclaste tipos de fusión"}

func _execute_generic_fusion(fusion_owner: String) -> Dictionary:
	if generic_materials.size() < 2:
		return {"success": false, "message": "No hay suficientes materiales para fusión genérica"}
	
	fusion_in_progress = true
	
	var result = _execute_generic_fusion_chain(generic_materials.duplicate())
	
	var last_original_card = generic_materials[generic_materials.size() - 1]
	var is_fusion_result = result.final_card != last_original_card
	
	if is_fusion_result and result.any_success:
		_process_fusion_materials("generic", fusion_owner)
		pending_fusion_card = result.final_card
		_setup_pending_fusion_card(pending_fusion_card, fusion_owner)
		
		fusion_performed_this_turn = true
		fusion_in_progress = false
		clear_materials()
		
		emit_signal("fusion_card_ready", pending_fusion_card)
		return {"success": true, "message": "Fusión exitosa. Coloca la carta resultante en el campo"}
	else:
		# FUSIÓN FALLIDA
		if result.has("created_fusion_cards"):
			for fusion_card in result.created_fusion_cards:
				if is_instance_valid(fusion_card):
					fusion_card.queue_free()
		
		var last_card = last_original_card
		
		for card in generic_materials:
			if card != last_card:
				_destroy_card_for_fusion(card, fusion_owner)
		
		pending_fusion_card = last_card
		
		if not pending_fusion_card:
			fusion_in_progress = false
			clear_materials()
			return {"success": false, "message": "Error en fusión genérica fallida"}
		
		_setup_pending_fusion_card(pending_fusion_card, fusion_owner)
		
		fusion_performed_this_turn = true
		fusion_in_progress = false
		clear_materials()
		
		emit_signal("fusion_card_ready", pending_fusion_card)
		return {"success": false, "message": "Fusión genérica fallida. Coloca la última carta en el campo"}

func _execute_generic_fusion_chain(cards_array: Array) -> Dictionary:
	if cards_array.size() < 2:
		return {"success": false, "message": "No hay suficientes materiales"}
	
	var current_card = cards_array[0]
	var fusion_chain = []
	var any_success = false
	var created_fusion_cards = []
	
	for i in range(1, cards_array.size()):
		var next_card = cards_array[i]
		var result_card = generic_db.find_fusion(current_card, next_card)
		
		var success = (result_card != next_card)
		fusion_chain.append({
			"step": i,
			"from": current_card.card_name,
			"with": next_card.card_name,
			"result": result_card.card_name,
			"success": success
		})
		
		if success:
			any_success = true
			if current_card != cards_array[0] and current_card.fusion_result:
				if is_instance_valid(current_card):
					current_card.queue_free()
			
			created_fusion_cards.append(result_card)
			current_card = result_card
		else:
			if current_card != cards_array[0] and current_card.fusion_result:
				if is_instance_valid(current_card):
					current_card.queue_free()
			current_card = next_card
	
	return {
		"success": true,
		"final_card": current_card,
		"any_success": any_success,
		"chain_history": fusion_chain,
		"created_fusion_cards": created_fusion_cards,
		"type": "generic_chain"
	}

func _execute_specific_fusion(fusion_owner: String) -> Dictionary:
	if specific_materials.size() < 2:
		return {"success": false, "message": "No hay suficientes materiales para fusión específica"}
	
	fusion_in_progress = true
	
	var hand_node = get_node_or_null("../PlayerHand") if fusion_owner == "Player" else get_node_or_null("../OpponentHand")
	if hand_node:
		for card in specific_materials:
			if hand_node.has_method("remove_card_from_hand"):
				hand_node.remove_card_from_hand(card)
	
	var result_card = specific_db.find_fusion(specific_materials.duplicate())
	
	if not result_card:
		fusion_in_progress = false
		clear_materials()
		return {"success": false, "message": "Error en la fusión específica"}
	
	var last_card = specific_materials[specific_materials.size() - 1]
	var success = (result_card != last_card)
	
	if success:
		_process_fusion_materials("specific", fusion_owner)
		pending_fusion_card = result_card
		
		if not pending_fusion_card:
			fusion_in_progress = false
			clear_materials()
			return {"success": false, "message": "Error en fusión específica"}
		
		_setup_pending_fusion_card(pending_fusion_card, fusion_owner)
		
		var card_manager = get_node_or_null("../CardManager")
		if card_manager:
			if fusion_owner == "Player":
				pending_fusion_card.global_position = card_manager.get_global_mouse_position()
			else:
				pending_fusion_card.global_position = Vector2(640, 200)
		
		fusion_performed_this_turn = true
		fusion_in_progress = false
		clear_materials()
		
		emit_signal("fusion_card_ready", pending_fusion_card)
		return {"success": true, "message": "Fusión específica exitosa. Coloca la carta resultante en el campo"}
	else:
		for card in specific_materials:
			if card != last_card:
				_destroy_card_for_fusion(card, fusion_owner)
		
		pending_fusion_card = last_card
		
		if not pending_fusion_card:
			fusion_in_progress = false
			clear_materials()
			return {"success": false, "message": "Error en fusión fallida"}
		
		_setup_pending_fusion_card(pending_fusion_card, fusion_owner)
		
		var card_manager = get_node_or_null("../CardManager")
		if card_manager:
			if fusion_owner == "Player":
				pending_fusion_card.global_position = card_manager.get_global_mouse_position()
			else:
				pending_fusion_card.global_position = Vector2(640, 200)
		
		fusion_performed_this_turn = true
		fusion_in_progress = false
		clear_materials()
		
		emit_signal("fusion_card_ready", pending_fusion_card)
		return {"success": false, "message": "Fusión específica fallida. Coloca la última carta en el campo"}

func _process_fusion_materials(fusion_type: String, fusion_owner: String):
	var materials = generic_materials if fusion_type == "generic" else specific_materials
	
	for card in materials:
		_destroy_card_for_fusion(card, fusion_owner)

func _destroy_card_for_fusion(card, fusion_owner: String):
	var hand_node = get_node_or_null("../PlayerHand") if fusion_owner == "Player" else get_node_or_null("../OpponentHand")
	if hand_node and hand_node.has_method("remove_card_from_hand"):
		hand_node.remove_card_from_hand(card)
	
	var battle_manager = get_node_or_null("../BattleManager")
	if battle_manager:
		var player_battlefield = battle_manager.player_cards_on_battlefield
		var opponent_battlefield = battle_manager.opponent_cards_on_battlefield
		
		if card in player_battlefield:
			battle_manager.destroy_card(card, "Player")
		elif card in opponent_battlefield:
			battle_manager.destroy_card(card, "Opponent")
		else:
			card.queue_free()
	else:
		card.queue_free()

func _setup_pending_fusion_card(card, fusion_owner: String):
	if not card:
		return

	# Asegurar que no quede en ninguna mano (ni árbol ni arrays)
	var player_hand = get_node_or_null("../PlayerHand")
	var opponent_hand = get_node_or_null("../OpponentHand")
	if player_hand and player_hand.has_method("remove_card_from_hand"):
		player_hand.remove_card_from_hand(card)
	if opponent_hand and opponent_hand.has_method("remove_card_from_hand"):
		opponent_hand.remove_card_from_hand(card)
	if card.get_parent() and (card.get_parent() == player_hand or card.get_parent() == opponent_hand):
		card.get_parent().remove_child(card)

	# Asegurar que esté en escena
	if not card.is_inside_tree():
		get_tree().current_scene.add_child(card)

	var card_manager = get_node_or_null("../CardManager")
	if card_manager:
		card.scale = Vector2(card_manager.DRAG_SCALE, card_manager.DRAG_SCALE)
		card.z_index = 10
		if fusion_owner == "Player":
			card_manager.card_being_dragged = card
		else:
			card.z_index = 2

		card.card_owner = fusion_owner

		if card.has_method("set_in_hand_mask"):
			card.set_in_hand_mask(false)
		if card.has_method("set_show_back_only"):
			card.set_show_back_only(false)

		if card.has_method("apply_owner_collision_layers"):
			card.apply_owner_collision_layers()
	else:
		push_error("FusionManager: No se encontró CardManager")

func place_fusion_card(slot) -> bool:
	if not pending_fusion_card:
		return false

	var card_manager = get_node_or_null("../CardManager")
	var battle_manager = get_node_or_null("../BattleManager")
	if not card_manager or not battle_manager:
		return false
	if slot.card_in_slot:
		return false
	if slot.card_slot_type != "Monster":
		return false

	var the_owner = "Player"
	if pending_fusion_card.has_method("get") and pending_fusion_card.get("card_owner"):
		the_owner = pending_fusion_card.card_owner

	card_manager._place_card_in_slot(pending_fusion_card, slot)

	pending_fusion_card.card_slot_card_is_in = slot
	slot.card_in_slot = true
	if "card_ref" in slot:
		slot.card_ref = pending_fusion_card

	if the_owner == "Player":
		if not battle_manager.player_cards_on_battlefield.has(pending_fusion_card):
			battle_manager.player_cards_on_battlefield.append(pending_fusion_card)
		card_manager.played_monster_card_this_turn = true
	else:
		if not battle_manager.opponent_cards_on_battlefield.has(pending_fusion_card):
			battle_manager.opponent_cards_on_battlefield.append(pending_fusion_card)
		var opponent_ia = get_node_or_null("../OpponentIA")
		if opponent_ia:
			opponent_ia.played_monster_card_this_turn = true

	if pending_fusion_card.has_method("apply_owner_collision_layers"):
		pending_fusion_card.apply_owner_collision_layers()

	var shape = pending_fusion_card.get_node_or_null("Area2D/CollisionShape2D") as CollisionShape2D
	if shape:
		shape.disabled = false 

	if pending_fusion_card.has_method("ensure_guardian_initialized"):
		pending_fusion_card.ensure_guardian_initialized()

	if pending_fusion_card.has_method("set_in_hand_mask"):
		pending_fusion_card.set_in_hand_mask(false)

	if the_owner == "Player" and pending_fusion_card in battle_manager.player_cards_that_attacked_this_turn:
		battle_manager.player_cards_that_attacked_this_turn.erase(pending_fusion_card)

	pending_fusion_card = null
	return true

func can_select_material(fusion_type: String) -> bool:
	if fusion_performed_this_turn or fusion_in_progress or pending_fusion_card:
		return false
	
	if fusion_type == "generic":
		return specific_materials.size() == 0
	else:
		return generic_materials.size() == 0

func has_materials_selected() -> bool:
	return generic_materials.size() > 0 or specific_materials.size() > 0

func has_pending_fusion() -> bool:
	return pending_fusion_card != null

func get_current_fusion_type() -> String:
	if generic_materials.size() > 0:
		return "generic"
	elif specific_materials.size() > 0:
		return "specific"
	return ""

# === ACTUALIZACIÓN DE POSICIÓN ===
func update_pending_fusion_position(mouse_global_position: Vector2):
	if pending_fusion_card:
		var anchor = pending_fusion_card.get_node_or_null("AnchorCenter") as Node2D
		if anchor:
			var delta = anchor.to_global(Vector2.ZERO) - pending_fusion_card.to_global(Vector2.ZERO)
			pending_fusion_card.global_position = mouse_global_position - delta
		else:
			var half = pending_fusion_card.get_visual_half_size() * pending_fusion_card.global_scale
			pending_fusion_card.global_position = mouse_global_position - half

# === RESET POR TURNO ===
func reset_turn():
	fusion_performed_this_turn = false
	fusion_in_progress = false
	
	if pending_fusion_card:
		var the_owner = pending_fusion_card.card_owner if pending_fusion_card.has_method("get") and pending_fusion_card.get("card_owner") else "Player"
		_destroy_card_for_fusion(pending_fusion_card, the_owner)
		pending_fusion_card = null
	clear_materials()
