extends Node2D

signal left_mouse_button_clicked
signal left_mouse_button_released

const COLLISION_MASK_CARD := 1
const COLLISION_MASK_OPPONENT_CARD := 8

var card_manager_reference
var inputs_disabled := false
var is_animating:= false

func _ready() -> void:
	card_manager_reference = $"../CardManager"

func _input(event: InputEvent) -> void:
	if is_animating:
		return
	if Input.is_action_just_pressed("change_pos") and not inputs_disabled:
		if $"../BattleManager".is_opponent_turn:
			return
		if card_manager_reference and card_manager_reference.is_dragging():
			return

		var space_state := get_world_2d().direct_space_state
		var parameters := PhysicsPointQueryParameters2D.new()
		parameters.position = get_global_mouse_position()
		parameters.collide_with_areas = true
		parameters.collision_mask = COLLISION_MASK_CARD
		var result := space_state.intersect_point(parameters)

		if result.size() > 0:
			var picked = result[0].collider.get_parent()
			if result.size() > 1:
				var highest_card = picked
				var highest_z = picked.z_index
				for hit in result:
					var c = hit.collider.get_parent()
					if is_instance_valid(c) and c.z_index > highest_z:
						highest_card = c
						highest_z = c.z_index
				picked = highest_card

			if is_instance_valid(picked) and picked.card_type == "Monster" and picked.card_slot_card_is_in:
				var bm = $"../BattleManager"
				if bm and (picked in bm.player_cards_that_attacked_this_turn):
					return
				picked.toggle_defense_position()
		return 
	
	if Input.is_action_just_pressed("star_guardian_changer") and not inputs_disabled:
		if $"../BattleManager".is_opponent_turn:
			return

		var p := get_global_mouse_position()
		var space_state := get_world_2d().direct_space_state
		var query := PhysicsPointQueryParameters2D.new()
		query.position = p
		query.collide_with_areas = true
		query.collision_mask = COLLISION_MASK_CARD

		var result := space_state.intersect_point(query, 1)

		if result.size() > 0:
			var card = result[0].collider.get_parent()
			if card and card.card_type == "Monster" and card.card_slot_card_is_in:
				var bm := $"../BattleManager"
				if bm and (card in bm.player_cards_that_attacked_this_turn):
					return
				card.toggle_guardian_star()
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			emit_signal("left_mouse_button_clicked")
			if card_manager_reference and card_manager_reference.is_dragging():
				card_manager_reference.click_to_drop()
				return
			raycast_at_cursor()
		else:
			emit_signal("left_mouse_button_released")
	
	var can_fuse = !$"../CardManager".played_monster_card_this_turn
	
	if event.is_action_pressed("select_for_fusion_generic") and can_fuse:
		if $"../BattleManager".is_opponent_turn:
			return

		var hovered_card = _get_hovered_card()
		if hovered_card:
			var fusion_manager = $"../FusionManager"
			if fusion_manager and fusion_manager.is_animating_fusion:
				return
			if fusion_manager.can_select_material("generic"):
				fusion_manager.add_material(hovered_card, "generic")
				
	if event.is_action_pressed("select_for_fusion_specific") and can_fuse:
		if $"../BattleManager".is_opponent_turn:
			return
			
		var hovered_card = _get_hovered_card()
		if hovered_card:
			var fusion_manager = $"../FusionManager"
			if fusion_manager.can_select_material("specific"):
				fusion_manager.add_material(hovered_card, "specific")
	
	if event.is_action_pressed("try_to_fuse") and can_fuse:
		if $"../BattleManager".is_opponent_turn:
			return
			
		var fusion_manager = $"../FusionManager"
		var result = await fusion_manager.try_fusion("Player")
		
		if not result.success:
			print("Fusión: ", result.message)
			
	if event.is_action_pressed("cancel_fusion") and not inputs_disabled:
		$"../FusionManager".clear_materials()

func _get_hovered_card():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD
	var result = space_state.intersect_point(parameters)
	
	if result.size() > 0:
		return get_card_with_highest_z_index(result)
	return null

func get_card_with_highest_z_index(cards):
	var highest_z_card = cards[0].collider.get_parent()
	var highest_z_index = highest_z_card.z_index
	for i in range(1, cards.size()):
		var current_card = cards[i].collider.get_parent()
		if current_card.z_index > highest_z_index:
			highest_z_card = current_card
			highest_z_index = current_card.z_index
	return highest_z_card

func raycast_at_cursor() -> void:
	if inputs_disabled:
		return

	var space_state = get_world_2d().direct_space_state
	var p := PhysicsPointQueryParameters2D.new()
	p.position = get_global_mouse_position()
	p.collide_with_areas = true

	for hit in space_state.intersect_point(p):
		var area = hit.collider
		var layer = area.collision_layer

		if (layer & COLLISION_MASK_OPPONENT_CARD) != 0:
			var opp_card = area.get_parent()
			if $"../BattleManager".spell_targeting:
				$"../BattleManager".receive_spell_target(opp_card)
			else:
				$"../BattleManager".enemy_card_selected(opp_card)
			return

		elif (layer & COLLISION_MASK_CARD) != 0:
			var card_found = area.get_parent()
			if card_found:
				card_manager_reference.card_clicked(card_found)
			return
