extends Node

var generic_db
var specific_db

var generic_materials: Array = []
var specific_materials: Array = []

var fusion_performed_this_turn: bool = false
var pending_fusion_card = null
var fusion_in_progress: bool = false

var current_fusion_chain: Array = []
var current_fusion_step: int = 0
var is_animating_fusion: bool = false
var fusion_result_so_far = null

signal materials_updated(generic_count, specific_count)
signal fusion_error(message)
signal fusion_card_ready(card)
signal fusion_animation_started()
signal fusion_animation_finished()

func _ready() -> void:
	generic_db = preload("res://Scripts/GenericFusionDB.gd").new()
	specific_db = preload("res://Scripts/SpecificFusionDB.gd").new()
	add_child(generic_db)
	add_child(specific_db)
	materials_updated.connect(_on_materials_updated)

func _position_mouse_at_fusion_point():
	var fusion_point = get_node_or_null("../FusionPoint")
	if fusion_point:
		var card_manager = get_node_or_null("../CardManager")
		if card_manager and pending_fusion_card:
			var anchor = pending_fusion_card.get_node_or_null("AnchorCenter") as Node2D
			if anchor:
				var anchor_local_pos = anchor.position
				var anchor_global_offset = pending_fusion_card.to_global(anchor_local_pos) - pending_fusion_card.global_position
				pending_fusion_card.global_position = fusion_point.global_position - anchor_global_offset
			else:
				pending_fusion_card.global_position = fusion_point.global_position

func _refresh_hands_layout():
	var ph = get_node_or_null("../PlayerHand")
	if ph and ph.has_method("update_hand_positions"):
		ph.update_hand_positions(0.2)
	var oh = get_node_or_null("../OpponentHand")
	if oh and oh.has_method("update_hand_positions"):
		oh.update_hand_positions(0.2)

func _execute_generic_fusion_with_animation(fusion_owner: String) -> Dictionary:
	if generic_materials.size() < 2:
		return {"success": false, "message": "No hay suficientes materiales para fusión genérica"}
	
	fusion_in_progress = true
	is_animating_fusion = true
	
	var hand_node = get_node_or_null("../PlayerHand") if fusion_owner == "Player" else get_node_or_null("../OpponentHand")
	if hand_node and hand_node.has_method("remove_card_from_hand"):
		for card in generic_materials:
			if is_instance_valid(card):
				hand_node.remove_card_from_hand(card)
	
	var input_manager = get_node_or_null("../InputManager")
	if input_manager:
		input_manager.inputs_disabled = true
		input_manager.is_animating = true
	
	var fusion_point = get_node_or_null("../FusionPoint")
	if fusion_point:
		fusion_point.visible = true
	
	emit_signal("fusion_animation_started")
	
	var original_materials = generic_materials.duplicate()
	current_fusion_chain = _prepare_fusion_chain(generic_materials.duplicate())
	current_fusion_step = 0
	fusion_result_so_far = null
	
	await _execute_next_fusion_step(fusion_owner)
	
	var final_result = fusion_result_so_far
	var is_fusion_result = false
	
	for material in original_materials:
		if final_result != material:
			is_fusion_result = true
			break
	
	if is_fusion_result:
		pending_fusion_card = final_result
		_setup_pending_fusion_card(pending_fusion_card, fusion_owner)
		fusion_performed_this_turn = true
		emit_signal("fusion_card_ready", pending_fusion_card)
		_position_mouse_at_fusion_point()
	else:
		var last_card = original_materials[original_materials.size() - 1]
		var last_live_card = null
		for i in range(original_materials.size() - 1, -1, -1):
			var card = original_materials[i]
			if is_instance_valid(card):
				last_live_card = card
				break
		
		if last_live_card:
			pending_fusion_card = last_live_card
			if is_instance_valid(last_live_card):
				last_live_card.set_fusion_marker(last_live_card.FusionMarker.NONE)
			_setup_pending_fusion_card(pending_fusion_card, fusion_owner)
		else:
			pending_fusion_card = last_card
			_setup_pending_fusion_card(pending_fusion_card, fusion_owner)
	
	_finalize_fusion_animation(fusion_point, input_manager)
	return {"success": is_fusion_result, "message": "Fusión completada"}

func _prepare_fusion_chain(cards_array: Array) -> Array:
	var chain = []
	for i in range(0, cards_array.size() - 1):
		var material1 = cards_array[i]
		var material2 = cards_array[i + 1]
		chain.append({
			"material1": material1,
			"material2": material2,
			"step": i + 1,
			"total_steps": cards_array.size() - 1
		})
	return chain

func _execute_next_fusion_step(fusion_owner: String):
	if current_fusion_step >= current_fusion_chain.size():
		return
	
	var step_data = current_fusion_chain[current_fusion_step]
	var material1 = step_data.material1
	var material2 = step_data.material2
	
	_reset_card_positions_for_animation([material1, material2])
	
	if is_instance_valid(material1):
		material1.visible = true
		material1.scale = Vector2(0.8, 0.8)
		material1.set_fusion_marker(material1.FusionMarker.NONE)
	
	if is_instance_valid(material2):
		material2.visible = true
		material2.scale = Vector2(0.8, 0.8)
		material2.set_fusion_marker(material2.FusionMarker.NONE)
	
	await _animate_materials_to_fusion_point([material1, material2])
	
	var result_card = generic_db.find_fusion(material1, material2)
	var success = (result_card != material2)
	
	await _show_fusion_result(result_card, success, fusion_owner)
	
	fusion_result_so_far = result_card
	current_fusion_step += 1
	
	if material1 != fusion_result_so_far and is_instance_valid(material1):
		material1.queue_free()
	
	if material2 != fusion_result_so_far and is_instance_valid(material2):
		material2.queue_free()
	
	if current_fusion_step < current_fusion_chain.size():
		if is_instance_valid(result_card):
			result_card.visible = true
			result_card.scale = Vector2(0.8, 0.8)
			result_card.set_fusion_marker(result_card.FusionMarker.NONE)
		
		await get_tree().create_timer(1.0).timeout
		current_fusion_chain[current_fusion_step].material1 = result_card
		await _execute_next_fusion_step(fusion_owner)

func _animate_materials_to_fusion_point(materials: Array):
	var fusion_point = get_node_or_null("../FusionPoint")
	if not fusion_point:
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	for material in materials:
		if is_instance_valid(material):
			var target_pos = fusion_point.global_position
			var initial_position = material.global_position
			var initial_scale = material.scale
			
			var anchor = material.get_node_or_null("AnchorCenter") as Node2D
			if anchor:
				var anchor_local_pos = anchor.position
				var anchor_global_offset = material.to_global(anchor_local_pos) - material.global_position
				target_pos -= anchor_global_offset
				
				var initial_anchor_world_pos = material.to_global(anchor.position)
				
				tween.tween_method(
					func(progress: float):
						var current_pos = initial_position.lerp(target_pos, progress)
						material.global_position = current_pos
						var current_scale = initial_scale * (1.0 - progress)
						material.scale = current_scale
						var current_anchor_world_pos = material.to_global(anchor.position)
						var desired_anchor_pos = initial_anchor_world_pos.lerp(fusion_point.global_position, progress)
						var adjustment = desired_anchor_pos - current_anchor_world_pos
						material.global_position += adjustment,
					0.0, 1.0, 0.5
				)
			else:
				tween.tween_property(material, "global_position", target_pos, 0.5)
				tween.tween_property(material, "scale", Vector2(0, 0), 0.5).set_ease(Tween.EASE_IN)
	
	await tween.finished
	
	for material in materials:
		if is_instance_valid(material):
			material.visible = false

func _show_fusion_result(result_card, _success: bool, _fusion_owner: String):
	var fusion_point = get_node_or_null("../FusionPoint")
	if not fusion_point:
		return
	
	if not result_card.is_inside_tree():
		get_tree().current_scene.add_child(result_card)
	
	result_card.global_position = fusion_point.global_position
	result_card.scale = Vector2(0, 0)
	result_card.visible = true
	
	var anchor = result_card.get_node_or_null("AnchorCenter") as Node2D
	var initial_position = result_card.global_position
	
	if anchor:
		var anchor_local_pos = anchor.position
		var anchor_global_offset = result_card.to_global(anchor_local_pos) - result_card.global_position
		result_card.global_position = fusion_point.global_position - anchor_global_offset
		initial_position = result_card.global_position
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	tween.tween_method(
		func(progress: float):
			var current_scale = Vector2.ONE * (1.1 * progress)
			result_card.scale = current_scale
			if anchor:
				var current_anchor_world_pos = result_card.to_global(anchor.position)
				var desired_anchor_pos = initial_position
				var adjustment = desired_anchor_pos - current_anchor_world_pos
				result_card.global_position += adjustment,
		0.0, 1.0, 0.3).set_ease(Tween.EASE_OUT)
	
	tween.tween_property(result_card, "rotation", 0, 0.3)
	await tween.finished
	
	var final_tween = create_tween()
	final_tween.tween_method(
		func(progress: float):
			var current_scale = Vector2.ONE * (1.1 - (0.3 * progress))
			result_card.scale = current_scale
			if anchor:
				var current_anchor_world_pos = result_card.to_global(anchor.position)
				var desired_anchor_pos = initial_position
				var adjustment = desired_anchor_pos - current_anchor_world_pos
				result_card.global_position += adjustment,
		0.0, 1.0, 0.15).set_ease(Tween.EASE_IN)
	
	await final_tween.finished
	await get_tree().create_timer(0.5).timeout

func try_fusion(fusion_owner: String) -> Dictionary:
	if fusion_performed_this_turn or fusion_in_progress:
		return {"success": false, "message": "Ya se realizó una fusión este turno"}
	
	if pending_fusion_card:
		return {"success": false, "message": "Fusión pendiente a colocar"}
	
	if generic_materials.size() >= 2 and specific_materials.size() == 0:
		return await _execute_generic_fusion_with_animation(fusion_owner)
	elif specific_materials.size() >= 2 and generic_materials.size() == 0:
		return await _execute_specific_fusion_with_animation(fusion_owner)
	else:
		return {"success": false, "message": "Faltan materiales o mezclaste tipos de fusión"}

func _execute_specific_fusion_with_animation(fusion_owner: String) -> Dictionary:
	if specific_materials.size() < 2:
		return {"success": false, "message": "No hay suficientes materiales para fusión específica"}
	
	fusion_in_progress = true
	is_animating_fusion = true
	
	var input_manager = get_node_or_null("../InputManager")
	if input_manager:
		input_manager.inputs_disabled = true
		input_manager.is_animating = true
	
	var fusion_point = get_node_or_null("../FusionPoint")
	if fusion_point:
		fusion_point.visible = true
	
	emit_signal("fusion_animation_started")
	
	var hand_node = get_node_or_null("../PlayerHand") if fusion_owner == "Player" else get_node_or_null("../OpponentHand")
	if hand_node:
		for card in specific_materials:
			if hand_node.has_method("remove_card_from_hand"):
				hand_node.remove_card_from_hand(card)
	
	for material in specific_materials:
		if is_instance_valid(material):
			material.visible = true
			material.scale = Vector2(0.8, 0.8)
			material.set_fusion_marker(material.FusionMarker.NONE)
	
	_reset_card_positions_for_animation(specific_materials.duplicate())
	await _animate_materials_to_fusion_point(specific_materials.duplicate())
	
	var result_card = specific_db.find_fusion(specific_materials.duplicate())
	var last_card = specific_materials[specific_materials.size() - 1]
	var success = (result_card != last_card)
	
	await _show_fusion_result(result_card, success, fusion_owner)
	
	if success:
		pending_fusion_card = result_card
		_setup_pending_fusion_card(pending_fusion_card, fusion_owner)
		fusion_performed_this_turn = true
		emit_signal("fusion_card_ready", pending_fusion_card)
		_position_mouse_at_fusion_point()
	else:
		for card in specific_materials:
			if card != last_card:
				_destroy_card_for_fusion(card, fusion_owner)
		
		pending_fusion_card = last_card
		if is_instance_valid(last_card):
			last_card.set_fusion_marker(last_card.FusionMarker.NONE)
		_setup_pending_fusion_card(pending_fusion_card, fusion_owner)
		fusion_performed_this_turn = true
		emit_signal("fusion_card_ready", pending_fusion_card)
	
	_finalize_fusion_animation(fusion_point, input_manager)
	return {"success": success, "message": "Fusión específica " + ("exitosa" if success else "fallida")}

func _finalize_fusion_animation(fusion_point, input_manager):
	clear_materials()
	var player_hand = get_node_or_null("../PlayerHand")
	var opponent_hand = get_node_or_null("../OpponentHand")
	if player_hand and player_hand.has_method("cleanup_invalid_cards"):
		player_hand.cleanup_invalid_cards()
	if opponent_hand and opponent_hand.has_method("cleanup_invalid_cards"):
		opponent_hand.cleanup_invalid_cards()
	
	fusion_in_progress = false
	is_animating_fusion = false
	_refresh_hands_layout()
	
	if not pending_fusion_card and fusion_point:
		fusion_point.visible = false
	
	if input_manager:
		input_manager.inputs_disabled = false
		input_manager.is_animating = false
	
	emit_signal("fusion_animation_finished")

func add_material(card, fusion_type: String) -> bool:
	if fusion_performed_this_turn or fusion_in_progress or is_animating_fusion:
		emit_signal("fusion_error", "Ya realizaste una fusión este turno o hay una fusión en progreso")
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

func _on_materials_updated(generic_count: int, specific_count: int) -> void:
	var fusion_point = get_node_or_null("../FusionPoint")
	if not fusion_point:
		return
	
	var has_materials = (generic_count > 0 or specific_count > 0)
	var fusion_type = ""
	
	if generic_count > 0:
		fusion_type = "generic"
	elif specific_count > 0:
		fusion_type = "specific"
	
	if fusion_point.has_method("update_fusion_display"):
		fusion_point.update_fusion_display(fusion_type, has_materials)

func remove_material(card):
	if not is_instance_valid(card):
		if generic_materials.has(card):
			generic_materials.erase(card)
		elif specific_materials.has(card):
			specific_materials.erase(card)
		materials_updated.emit(generic_materials.size(), specific_materials.size())
		return

	if generic_materials.has(card):
		generic_materials.erase(card)
		_update_card_visual(card, false, "generic")
	elif specific_materials.has(card):
		specific_materials.erase(card)
		_update_card_visual(card, false, "specific")
	
	materials_updated.emit(generic_materials.size(), specific_materials.size())

func clear_materials():
	for card in generic_materials:
		if is_instance_valid(card) and card.visible:
			_update_card_visual(card, false, "generic")
	
	for card in specific_materials:
		if is_instance_valid(card) and card.visible:
			_update_card_visual(card, false, "specific")
	
	generic_materials.clear()
	specific_materials.clear()
	materials_updated.emit(0, 0)

	var fusion_point = get_node_or_null("../FusionPoint")
	if fusion_point and fusion_point.has_method("update_fusion_display"):
		fusion_point.update_fusion_display("", false)

func _update_card_visual(card, selected: bool, fusion_type: String):
	if not is_instance_valid(card):
		return

	if not selected:
		card.set_fusion_marker(card.FusionMarker.NONE)
		return
	
	match fusion_type.to_lower():
		"generic":
			card.set_fusion_marker(card.FusionMarker.GENERIC)
		"specific":
			card.set_fusion_marker(card.FusionMarker.SPECIFIC)
		_:
			card.set_fusion_marker(card.FusionMarker.GENERIC)

func _destroy_card_for_fusion(card, fusion_owner: String):
	if not is_instance_valid(card):
		return
	
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
	
	var player_hand = get_node_or_null("../PlayerHand")
	var opponent_hand = get_node_or_null("../OpponentHand")
	if player_hand and player_hand.has_method("remove_card_from_hand"):
		player_hand.remove_card_from_hand(card)
	if opponent_hand and opponent_hand.has_method("remove_card_from_hand"):
		opponent_hand.remove_card_from_hand(card)
	if card.get_parent() and (card.get_parent() == player_hand or card.get_parent() == opponent_hand):
		card.get_parent().remove_child(card)
	
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

func update_pending_fusion_position(mouse_global_position: Vector2):
	if pending_fusion_card:
		var anchor = pending_fusion_card.get_node_or_null("AnchorCenter") as Node2D
		if anchor:
			var delta = anchor.to_global(Vector2.ZERO) - pending_fusion_card.to_global(Vector2.ZERO)
			pending_fusion_card.global_position = mouse_global_position - delta
		else:
			var half = pending_fusion_card.get_visual_half_size() * pending_fusion_card.global_scale
			pending_fusion_card.global_position = mouse_global_position - half

func reset_turn():
	fusion_performed_this_turn = false
	fusion_in_progress = false
	
	if pending_fusion_card:
		var the_owner = pending_fusion_card.card_owner if pending_fusion_card.has_method("get") and pending_fusion_card.get("card_owner") else "Player"
		_destroy_card_for_fusion(pending_fusion_card, the_owner)
		pending_fusion_card = null
	clear_materials()

func _reset_card_positions_for_animation(materials: Array):
	var fusion_point = get_node_or_null("../FusionPoint")
	if not fusion_point:
		return
	
	var arrangement = _get_best_arrangement(materials.size())
	
	for i in range(materials.size()):
		var material = materials[i]
		if is_instance_valid(material):
			material.z_index = 5 
			material.rotation = 0
			
			var start_pos = fusion_point.global_position
			start_pos += _calculate_position(i, materials.size(), arrangement)
			
			var anchor = material.get_node_or_null("AnchorCenter") as Node2D
			if anchor:
				var anchor_local_pos = anchor.position
				var anchor_global_offset = material.to_global(anchor_local_pos) - material.global_position
				start_pos -= anchor_global_offset
			
			material.global_position = start_pos
			material.scale = Vector2(0.8, 0.8)

func _get_best_arrangement(count: int) -> String:
	match count:
		2:
			return "horizontal"
		3:
			return "triangle"  
		_:
			return "circle"

func _calculate_position(index: int, total: int, arrangement: String) -> Vector2:
	match arrangement:
		"horizontal":
			var spacing = 320.0
			var total_width = (total - 1) * spacing
			return Vector2((index * spacing) - (total_width / 2.0), -50)
		
		"triangle":
			match index:
				0: return Vector2(-120, 80)    
				1: return Vector2(120, 80)     
				2: return Vector2(0, -80)      
				_: return Vector2.ZERO
		
		"circle":
			var radius = 160.0
			var angle_step = TAU / total
			var angle = angle_step * index - (PI / 2) 
			return Vector2(cos(angle) * radius, sin(angle) * radius)
		
		_:
			return Vector2.ZERO
