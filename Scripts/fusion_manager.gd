extends Node

@export_file("*.json") var cards_db_path: String = "res://Scripts/JSON/CardsDB.json"
@export_file("*.json") var generic_fusions_path: String = "res://Scripts/JSON/generic_fusions.json"
@export_file("*.json") var specific_fusions_path: String = "res://Scripts/JSON/specific_fusions.json"
@export var card_scene: PackedScene = preload("res://Scenes/Card.tscn")
@export var fusion_reveal_hold_duration: float = 0.8


var repo: FusionRepository
var fusion: FusionService

var generic_materials: Array = []
var specific_materials: Array = []

var fusion_performed_this_turn_by_owner := {
	"Player": false,
	"Opponent": false
}
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
	repo = FusionRepository.new()
	add_child(repo)
	repo.load_all(cards_db_path, generic_fusions_path, specific_fusions_path)
	fusion = FusionService.new(repo, card_scene)
	add_child(fusion)
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

func _norm_owner(owner_value) -> String:
	var s := str(owner_value).strip_edges().to_upper()

	if s == "PLAYER":
		return "Player"

	if s == "OPPONENT":
		return "Opponent"

	return "Player" if s == "" else str(owner_value)

func _opponent_ia():
	return get_node_or_null("../OpponentIA")


func _fusion_performed_by_owner(owner: String) -> bool:
	owner = _norm_owner(owner)
	return bool(fusion_performed_this_turn_by_owner.get(owner, false))


func _set_fusion_performed_by_owner(owner: String, value: bool) -> void:
	owner = _norm_owner(owner)
	fusion_performed_this_turn_by_owner[owner] = value


func _monster_play_consumed_this_turn(owner: String) -> bool:
	owner = _norm_owner(owner)

	if _fusion_performed_by_owner(owner):
		return true

	if owner == "Player":
		var cm = _card_manager()
		if cm != null and "played_monster_card_this_turn" in cm:
			return bool(cm.played_monster_card_this_turn)

	elif owner == "Opponent":
		var ia = _opponent_ia()
		if ia != null and "played_monster_card_this_turn" in ia:
			return bool(ia.played_monster_card_this_turn)

	return false


func _consume_monster_play_for_turn(owner: String) -> void:
	owner = _norm_owner(owner)

	_set_fusion_performed_by_owner(owner, true)

	if owner == "Player":
		var cm = _card_manager()
		if cm != null and "played_monster_card_this_turn" in cm:
			cm.played_monster_card_this_turn = true

	elif owner == "Opponent":
		var ia = _opponent_ia()
		if ia != null and "played_monster_card_this_turn" in ia:
			ia.played_monster_card_this_turn = true


func _reveal_fusion_cards(cards: Array) -> void:
	for card in cards:
		if not is_instance_valid(card):
			continue

		_force_card_faceup_attack(card)


func _force_card_faceup_attack(card) -> void:
	if not is_instance_valid(card):
		return

	if card.has_method("set_show_back_only"):
		card.set_show_back_only(false)

	if card.has_method("set_face_down"):
		card.set_face_down(false)
	elif card.has_method("set_facedown"):
		card.set_facedown(false)
	elif "face_down" in card:
		card.face_down = false
	elif "is_facedown" in card:
		card.is_facedown = false

	if card.has_method("set_defense_position"):
		card.set_defense_position(false)
	elif "in_defense" in card:
		card.in_defense = false

	if card.has_method("_update_visuals"):
		card._update_visuals()

func _get_card_current_slot(card: Node) -> Node:
	if not is_instance_valid(card):
		return null

	if "current_slot" in card and card.current_slot != null:
		return card.current_slot

	if "card_slot_card_is_in" in card and card.card_slot_card_is_in != null:
		return card.card_slot_card_is_in

	return null


func _first_field_material_slot(materials: Array, owner: String) -> Node:
	owner = _norm_owner(owner)

	for card in materials:
		if not is_instance_valid(card):
			continue

		var slot := _get_card_current_slot(card)
		if slot == null:
			continue

		var bm = _battle_manager()
		if bm != null and bm.zone_service.has_method("_owner_of"):
			var card_owner := _norm_owner(bm.zone_service._owner_of(card))
			if card_owner != "" and card_owner != owner:
				continue

		return slot

	return null

func _detach_fusion_materials_from_zones(materials: Array, owner: String, refresh_hand_layout: bool = false) -> void:
	owner = _norm_owner(owner)

	var hand_node = get_node_or_null("../PlayerHand") if owner == "Player" else get_node_or_null("../OpponentHand")
	var bm = _battle_manager()

	for card in materials:
		if not is_instance_valid(card):
			continue

		if hand_node and hand_node.has_method("remove_card_from_hand"):
			hand_node.remove_card_from_hand(card, refresh_hand_layout)

		var slot := _get_card_current_slot(card)
		if slot != null:
			slot.set("card_in_slot", false)
			slot.set_meta("card_ref", null)

			var shape := slot.get_node_or_null("Area2D/CollisionShape2D") as CollisionShape2D
			if shape:
				shape.disabled = false

		if bm != null:
			if card in bm.player_cards_on_battlefield:
				bm.player_cards_on_battlefield.erase(card)

			if card in bm.opponent_cards_on_battlefield:
				bm.opponent_cards_on_battlefield.erase(card)

			if bm.event_service.has_method("_unregister_card_with_effect_engine"):
				bm.event_service._unregister_card_with_effect_engine(card)

		if card.has_method("clear_field_slot"):
			card.clear_field_slot()
		else:
			if "current_slot" in card:
				card.current_slot = null
			if "card_slot_card_is_in" in card:
				card.card_slot_card_is_in = null

		if card.has_method("move_to_zone"):
			card.move_to_zone("NONE")
		elif "current_zone" in card:
			card.current_zone = "NONE"

func _find_free_player_monster_slot() -> Node:
	var slots_root := get_node_or_null("../CardSlots")
	if not is_instance_valid(slots_root):
		return null

	for slot in slots_root.get_children():
		if not is_instance_valid(slot):
			continue

		if str(slot.get("card_slot_type")) != "Monster":
			continue

		if bool(slot.get("card_in_slot")):
			continue

		return slot

	return null


func _find_free_opponent_monster_slot() -> Node:
	var bm = _battle_manager()
	if bm == null:
		return null

	if "empty_monster_card_slots" in bm:
		for slot in bm.empty_monster_card_slots:
			if not is_instance_valid(slot):
				continue

			if bool(slot.get("card_in_slot")):
				continue

			return slot

	return null


func _find_free_monster_slot(owner: String) -> Node:
	owner = _norm_owner(owner)

	if owner == "Player":
		return _find_free_player_monster_slot()

	return _find_free_opponent_monster_slot()

func _prepare_fusion_result_for_field(card: Node, owner: String) -> void:
	if not is_instance_valid(card):
		return

	owner = _norm_owner(owner)

	if not card.is_inside_tree():
		get_tree().current_scene.add_child(card)

	card.visible = true
	card.owner_side = owner.to_upper()

	_clear_fusion_presentation(card)
	_force_card_faceup_attack(card)

	if card.has_method("set_in_hand_mask"):
		card.set_in_hand_mask(false)

	if card.has_method("apply_owner_collision_layers"):
		card.apply_owner_collision_layers()

	if card.has_method("ensure_guardian_initialized"):
		card.ensure_guardian_initialized()

	var shape := card.get_node_or_null("Area2D/CollisionShape2D") as CollisionShape2D
	if shape:
		shape.disabled = false

func _resolve_fusion_result_slot(owner: String, preferred_slot: Node, result_card: Node, input_manager: Node) -> Node:
	owner = _norm_owner(owner)

	if is_instance_valid(preferred_slot) and not bool(preferred_slot.get("card_in_slot")):
		return preferred_slot

	var free_slot := _find_free_monster_slot(owner)
	if is_instance_valid(free_slot):
		return free_slot

	var bm = _battle_manager()
	if bm == null:
		return null

	# Campo lleno. Si es player, se habilita selección de reemplazo.
	if owner == "Player":
		if input_manager:
			input_manager.inputs_disabled = false
			input_manager.is_animating = false

		if bm.fusion_replacement_service.has_method("await_fusion_replacement_slot"):
			var chosen_slot = await bm.fusion_replacement_service.await_fusion_replacement_slot(owner, result_card)

			if input_manager:
				input_manager.inputs_disabled = true
				input_manager.is_animating = true

			return chosen_slot

		return null

	# IA: reemplazo automático.
	if bm.fusion_replacement_service.has_method("await_fusion_replacement_slot"):
		return await bm.fusion_replacement_service.await_fusion_replacement_slot(owner, result_card)

	return null

func _place_fusion_result_on_field(card: Node, owner: String, preferred_slot: Node, input_manager: Node) -> bool:
	if not is_instance_valid(card):
		return false

	var bm = _battle_manager()
	if bm == null:
		return false

	owner = _norm_owner(owner)

	_prepare_fusion_result_for_field(card, owner)

	await _fade_out_fusion_point_execution()

	var slot := await _resolve_fusion_result_slot(owner, preferred_slot, card, input_manager)
	if not is_instance_valid(slot):
		push_warning("FusionManager: no se pudo resolver slot para la fusión.")
		return false

	_force_card_faceup_attack(card)

	if bm.zone_service.has_method("_reserve_slot_for_card"):
		bm.zone_service._reserve_slot_for_card(card, slot)

	_play_duel_sfx("fusion_result")

	if bm.animation_service.has_method("_animate_card_to_slot_visual") and card is Node2D:
		await bm.animation_service._animate_card_to_slot_visual(card, slot, 0.28)

	if bm.zone_service.has_method("_place_card_in_slot"):
		bm.zone_service._place_card_in_slot(card, slot, "EFFECT", false)
	else:
		slot.set("card_in_slot", true)
		slot.set_meta("card_ref", card)

		if owner == "Player":
			if not bm.player_cards_on_battlefield.has(card):
				bm.player_cards_on_battlefield.append(card)
		else:
			if not bm.opponent_cards_on_battlefield.has(card):
				bm.opponent_cards_on_battlefield.append(card)

	await _play_duel_vfx_on_card("fusion_result_summoned", card)

	if bm.event_service.has_method("_emit_duel_event"):
		bm.event_service._emit_duel_event("ON_SUMMON_BY_EFFECT", {
			"battle_manager": bm,
			"source": card,
			"summoned": card,
			"controller": owner,
			"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
			"summon_type": "FUSION"
		})

	pending_fusion_card = null

	return true

func _play_duel_sfx(key: String) -> void:
	var fxm = get_node_or_null("../DuelFxManager")
	if fxm != null and fxm.has_method("play_sfx_key"):
		fxm.play_sfx_key(key)

func _play_duel_vfx_on_card(key: String, card: Node) -> void:
	if not is_instance_valid(card):
		return

	if not (card is Node2D):
		return

	var fxm = get_node_or_null("../DuelFxManager")
	if fxm != null and fxm.has_method("play_vfx_key_on_card"):
		await fxm.play_vfx_key_on_card(key, card)

func _get_fusion_point() -> Node:
	return get_node_or_null("../FusionPoint")


func _get_fusion_center_global() -> Vector2:
	var fusion_point = _get_fusion_point()

	if fusion_point != null and fusion_point.has_method("get_absorb_center_global"):
		return fusion_point.get_absorb_center_global()

	if fusion_point is Node2D:
		return (fusion_point as Node2D).global_position

	return Vector2.ZERO

func _begin_fusion_point_execution(fusion_type: String) -> void:
	var fusion_point = _get_fusion_point()

	if fusion_point == null:
		return

	if fusion_point.has_method("begin_execution"):
		await fusion_point.begin_execution(fusion_type)
	else:
		fusion_point.visible = true


func _end_fusion_point_execution() -> void:
	var fusion_point = _get_fusion_point()

	if fusion_point == null:
		return

	if fusion_point.has_method("end_execution"):
		await fusion_point.end_execution()
	else:
		fusion_point.visible = false

func _force_hide_fusion_point() -> void:
	var fusion_point = _get_fusion_point()

	if fusion_point == null:
		return

	if fusion_point.has_method("force_hidden"):
		fusion_point.force_hidden()
	else:
		fusion_point.visible = false

func _fade_out_fusion_point_execution() -> void:
	var fusion_point = _get_fusion_point()

	if fusion_point == null:
		return

	if fusion_point.has_method("fade_out_execution"):
		await fusion_point.fade_out_execution()
	else:
		fusion_point.visible = false

func _get_card_fusion_number_label(card: Node) -> Label:
	if not is_instance_valid(card):
		return null

	var label := card.get_node_or_null("FusionNumberLabel") as Label

	if label == null:
		label = card.find_child("FusionNumberLabel", true, false) as Label

	return label


func _set_card_fusion_number(card: Node, number: int) -> void:
	var label := _get_card_fusion_number_label(card)

	if label == null:
		return

	if number <= 0:
		label.text = ""
		label.visible = false
		return

	label.text = str(number)
	label.visible = true


func _clear_card_fusion_number(card: Node) -> void:
	_set_card_fusion_number(card, 0)


func _refresh_fusion_numbers() -> void:
	var sequence: Array = []

	if generic_materials.size() > 0:
		sequence = generic_materials
	elif specific_materials.size() > 0:
		sequence = specific_materials

	for i in range(sequence.size()):
		var card = sequence[i]
		if is_instance_valid(card):
			_set_card_fusion_number(card, i + 1)


func _get_card_visual_center_global(card: Node2D) -> Vector2:
	if not is_instance_valid(card):
		return Vector2.ZERO

	var anchor := card.get_node_or_null("AnchorCenter") as Node2D
	if is_instance_valid(anchor):
		return anchor.global_position

	return card.global_position


func _set_card_scale_keeping_anchor_at(card: Node2D, new_scale: Vector2, target_anchor_global: Vector2) -> void:
	if not is_instance_valid(card):
		return

	card.scale = new_scale

	var anchor := card.get_node_or_null("AnchorCenter") as Node2D
	if is_instance_valid(anchor):
		card.global_position += target_anchor_global - anchor.global_position
	else:
		card.global_position = target_anchor_global


func _absorb_card_to_fusion_point(card: Node) -> void:
	if not is_instance_valid(card):
		return

	if not (card is Node2D):
		return

	_clear_fusion_presentation(card)

	var card2d := card as Node2D

	_play_duel_sfx("material_absorb")

	card2d.visible = true
	card2d.z_index = 80

	var start_center := _get_card_visual_center_global(card2d)
	var target_center := _get_fusion_center_global()
	var start_scale := card2d.scale
	var start_rotation := card2d.rotation

	var tw := create_tween()

	tw.tween_method(
		func(progress: float):
			if not is_instance_valid(card2d):
				return

			var desired_center := start_center.lerp(target_center, progress)

			var squeeze_x := lerpf(start_scale.x, max(0.02, start_scale.x * 0.04), progress)

			var stretch_peak := sin(progress * PI)
			var collapse := progress * progress * progress
			var squeeze_y := lerpf(
				start_scale.y * (1.0 + stretch_peak * 0.85),
				max(0.03, start_scale.y * 0.08),
				collapse
			)

			var rot := lerpf(start_rotation, start_rotation + TAU * 0.35, progress)

			card2d.rotation = rot
			_set_card_scale_keeping_anchor_at(card2d, Vector2(squeeze_x, squeeze_y), desired_center),
		0.0,
		1.0,
		0.42
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await tw.finished

	if is_instance_valid(card2d):
		card2d.visible = false


func _animate_specific_materials_to_fusion_point(materials: Array) -> void:
	var valid_materials: Array = []

	for card in materials:
		if is_instance_valid(card) and card is Node2D:
			_clear_fusion_presentation(card)
			valid_materials.append(card)

	if valid_materials.is_empty():
		return

	_play_duel_sfx("material_absorb")

	var target_center := _get_fusion_center_global()
	var tw := create_tween()
	tw.set_parallel(true)

	for card in valid_materials:
		var card2d := card as Node2D
		card2d.visible = true
		card2d.z_index = 80

		var start_center := _get_card_visual_center_global(card2d)
		var start_scale := card2d.scale
		var start_rotation := card2d.rotation

		tw.tween_method(
			func(progress: float):
				if not is_instance_valid(card2d):
					return

				var desired_center := start_center.lerp(target_center, progress)

				var squeeze_x := lerpf(start_scale.x, max(0.02, start_scale.x * 0.04), progress)
				var stretch_peak := sin(progress * PI)
				var collapse := progress * progress * progress
				var squeeze_y := lerpf(
					start_scale.y * (1.0 + stretch_peak * 0.85),
					max(0.03, start_scale.y * 0.08),
					collapse
				)

				var rot := lerpf(start_rotation, start_rotation + TAU * 0.35, progress)

				card2d.rotation = rot
				_set_card_scale_keeping_anchor_at(card2d, Vector2(squeeze_x, squeeze_y), desired_center),
			0.0,
			1.0,
			0.48
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await tw.finished

	for card in valid_materials:
		if is_instance_valid(card):
			card.visible = false


func _dispose_fusion_material_if_not_result(card: Node, result_card: Node) -> void:
	if not is_instance_valid(card):
		return

	if card == result_card:
		return

	card.queue_free()

func _wait_fusion_reveal_hold() -> void:
	if fusion_reveal_hold_duration <= 0.0:
		return

	await get_tree().create_timer(fusion_reveal_hold_duration).timeout

func _execute_generic_fusion_with_animation(fusion_owner: String) -> Dictionary:
	if generic_materials.size() < 2:
		return {"success": false, "message": "No hay suficientes materiales para fusión genérica"}

	fusion_owner = _norm_owner(fusion_owner)

	fusion_in_progress = true
	is_animating_fusion = true

	var original_materials = generic_materials.duplicate()
	var preferred_slot := _first_field_material_slot(original_materials, fusion_owner)

	_reveal_fusion_cards(original_materials)

	_detach_fusion_materials_from_zones(original_materials, fusion_owner, false)

	var input_manager = get_node_or_null("../InputManager")
	if input_manager:
		input_manager.inputs_disabled = true
		input_manager.is_animating = true

	var fusion_point = get_node_or_null("../FusionPoint")
	await _begin_fusion_point_execution("generic")

	emit_signal("fusion_animation_started")

	await _wait_fusion_reveal_hold()
	var current_card = original_materials[0]
	var is_final_fusion_result := false

	for i in range(1, original_materials.size()):
		var next_card = original_materials[i]

		if not is_instance_valid(current_card):
			current_card = next_card
			continue

		if not is_instance_valid(next_card):
			continue

		await _absorb_card_to_fusion_point(current_card)
		await _absorb_card_to_fusion_point(next_card)

		var result_card = fusion.find_generic_fusion(current_card, next_card)
		var step_success = result_card != next_card

		await _show_fusion_result(result_card, step_success, fusion_owner)

		_dispose_fusion_material_if_not_result(current_card, result_card)
		_dispose_fusion_material_if_not_result(next_card, result_card)

		current_card = result_card
		is_final_fusion_result = not original_materials.has(current_card)

		if i < original_materials.size() - 1:
			await get_tree().create_timer(0.80).timeout

	var result_to_place = current_card

	if is_instance_valid(result_to_place):
		if result_to_place.has_method("set_fusion_marker"):
			result_to_place.set_fusion_marker(result_to_place.FusionMarker.NONE)

		_clear_card_fusion_number(result_to_place)

		await _end_fusion_point_execution()

		await _place_fusion_result_on_field(result_to_place, fusion_owner, preferred_slot, input_manager)

	_finalize_fusion_animation(fusion_point, input_manager)

	return {"success": is_final_fusion_result, "message": "Fusión completada"}

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
	
	var result_card = fusion.find_generic_fusion(material1, material2)
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

	if not is_instance_valid(result_card):
		return

	_clear_fusion_presentation(result_card)

	_play_duel_sfx("fusion_intent")

	if not result_card.is_inside_tree():
		get_tree().current_scene.add_child(result_card)

	_force_card_faceup_attack(result_card)

	result_card.visible = true
	result_card.z_index = 90
	result_card.rotation = 0.0
	result_card.scale = Vector2(0.0, 0.0)

	var target_center := _get_fusion_center_global()

	_set_card_scale_keeping_anchor_at(result_card, Vector2(0.0, 0.0), target_center)

	var tw := create_tween()
	tw.tween_method(
		func(progress: float):
			if not is_instance_valid(result_card):
				return

			var scale_value := lerpf(0.0, 1.10, progress)
			_set_card_scale_keeping_anchor_at(result_card, Vector2(scale_value, scale_value), target_center),
		0.0,
		1.0,
		0.25
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await tw.finished

	var settle := create_tween()
	settle.tween_method(
		func(progress: float):
			if not is_instance_valid(result_card):
				return

			var scale_value := lerpf(1.10, 0.80, progress)
			_set_card_scale_keeping_anchor_at(result_card, Vector2(scale_value, scale_value), target_center),
		0.0,
		1.0,
		0.15
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await settle.finished
	await get_tree().create_timer(0.25).timeout

func try_fusion(fusion_owner: String) -> Dictionary:
	fusion_owner = _norm_owner(fusion_owner)

	if _monster_play_consumed_this_turn(fusion_owner):
		return {"success": false, "message": "Ya invocaste o fusionaste este turno"}

	if fusion_in_progress:
		return {"success": false, "message": "Hay una fusión en progreso"}

	if pending_fusion_card:
		return {"success": false, "message": "Fusión pendiente a colocar"}

	var can_try_generic := generic_materials.size() >= 2 and specific_materials.size() == 0
	var can_try_specific := specific_materials.size() >= 2 and generic_materials.size() == 0

	if not can_try_generic and not can_try_specific:
		return {"success": false, "message": "Faltan materiales o mezclaste tipos de fusión"}

	# Intentar una fusión válida consume la jugada de monstruo,
	# aunque la fusión falle.
	_consume_monster_play_for_turn(fusion_owner)

	if can_try_generic:
		return await _execute_generic_fusion_with_animation(fusion_owner)

	return await _execute_specific_fusion_with_animation(fusion_owner)

func _execute_specific_fusion_with_animation(fusion_owner: String) -> Dictionary:
	if specific_materials.size() < 2:
		return {"success": false, "message": "No hay suficientes materiales para fusión específica"}

	fusion_owner = _norm_owner(fusion_owner)

	fusion_in_progress = true
	is_animating_fusion = true

	var original_materials = specific_materials.duplicate()
	var preferred_slot := _first_field_material_slot(original_materials, fusion_owner)

	_reveal_fusion_cards(original_materials)

	# Importante: no reordenar la mano todavía.
	_detach_fusion_materials_from_zones(original_materials, fusion_owner, false)

	var input_manager = get_node_or_null("../InputManager")
	if input_manager:
		input_manager.inputs_disabled = true
		input_manager.is_animating = true

	var fusion_point = get_node_or_null("../FusionPoint")
	await _begin_fusion_point_execution("specific")

	emit_signal("fusion_animation_started")
	await _wait_fusion_reveal_hold()
	await _animate_specific_materials_to_fusion_point(original_materials)

	var result_card = fusion.find_specific_fusion(original_materials.duplicate())
	var last_card = original_materials[original_materials.size() - 1]
	var success = (result_card != last_card)

	await _show_fusion_result(result_card, success, fusion_owner)

	var result_to_place = result_card if success else last_card

	if not success:
		for card in original_materials:
			if card != last_card:
				_destroy_card_for_fusion(card, fusion_owner)
	else:
		for card in original_materials:
			_dispose_fusion_material_if_not_result(card, result_card)

	if is_instance_valid(result_to_place):
		if result_to_place.has_method("set_fusion_marker"):
			result_to_place.set_fusion_marker(result_to_place.FusionMarker.NONE)

		_clear_card_fusion_number(result_to_place)

		await _end_fusion_point_execution()

		await _place_fusion_result_on_field(result_to_place, fusion_owner, preferred_slot, input_manager)

	_finalize_fusion_animation(fusion_point, input_manager)

	return {"success": success, "message": "Fusión específica " + ("exitosa" if success else "fallida")}

func _clear_fusion_presentation(card: Node) -> void:
	if not is_instance_valid(card):
		return

	if card.has_method("set_fusion_marker"):
		card.set_fusion_marker(card.FusionMarker.NONE)

	_clear_card_fusion_number(card)

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
	pending_fusion_card = null

	_refresh_hands_layout()

	_force_hide_fusion_point()

	if input_manager:
		input_manager.inputs_disabled = false
		input_manager.is_animating = false

	emit_signal("fusion_animation_finished")

func add_material(card, fusion_type: String, owner: String = "Player") -> bool:
	owner = _norm_owner(owner)

	if _monster_play_consumed_this_turn(owner):
		emit_signal("fusion_error", "Ya invocaste o fusionaste este turno")
		return false

	if fusion_in_progress or is_animating_fusion:
		emit_signal("fusion_error", "Hay una fusión en progreso")
		return false

	if not is_instance_valid(card):
		return false

	if pending_fusion_card:
		emit_signal("fusion_error", "Primero colocá la fusión pendiente")
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
	_refresh_fusion_numbers()

	materials_updated.emit(generic_materials.size(), specific_materials.size())

	return true

func place_fusion_card(slot) -> bool:
	if not is_instance_valid(pending_fusion_card):
		return false

	if not is_instance_valid(slot):
		return false

	if bool(slot.get("card_in_slot")):
		return false

	if str(slot.get("card_slot_type")) != "Monster":
		return false

	var battle_manager = get_node_or_null("../BattleManager")
	if battle_manager == null:
		return false

	var card = pending_fusion_card

	var owner := "Player"
	if card.get("owner_side") != null:
		owner = "Player" if str(card.owner_side).to_upper() == "PLAYER" else "Opponent"

	_force_card_faceup_attack(card)

	if card.has_method("set_field_slot"):
		card.set_field_slot(slot)
	elif "current_slot" in card:
		card.current_slot = slot
	elif "card_slot_card_is_in" in card:
		card.card_slot_card_is_in = slot

	slot.set("card_in_slot", true)
	slot.set_meta("card_ref", card)

	if battle_manager.has_method("register_card_played"):
		battle_manager.register_card_played(card, owner)
	else:
		if owner == "Player":
			if not battle_manager.player_cards_on_battlefield.has(card):
				battle_manager.player_cards_on_battlefield.append(card)
		else:
			if not battle_manager.opponent_cards_on_battlefield.has(card):
				battle_manager.opponent_cards_on_battlefield.append(card)

	if card.has_method("apply_owner_collision_layers"):
		card.apply_owner_collision_layers()

	if card.has_method("set_in_hand_mask"):
		card.set_in_hand_mask(false)

	var shape = card.get_node_or_null("Area2D/CollisionShape2D") as CollisionShape2D
	if shape:
		shape.disabled = false

	if card.has_method("ensure_guardian_initialized"):
		card.ensure_guardian_initialized()

	var card_manager = get_node_or_null("../CardManager")
	if card_manager != null:
		if "card_being_dragged" in card_manager and card_manager.card_being_dragged == card:
			card_manager.card_being_dragged = null

	var fusion_point = get_node_or_null("../FusionPoint")
	if fusion_point:
		fusion_point.visible = false

	pending_fusion_card = null

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

		_refresh_fusion_numbers()
		materials_updated.emit(generic_materials.size(), specific_materials.size())
		return

	if generic_materials.has(card):
		generic_materials.erase(card)
		_update_card_visual(card, false, "generic")

	elif specific_materials.has(card):
		specific_materials.erase(card)
		_update_card_visual(card, false, "specific")

	_refresh_fusion_numbers()
	materials_updated.emit(generic_materials.size(), specific_materials.size())

func clear_materials():
	for card in generic_materials:
		if is_instance_valid(card):
			_update_card_visual(card, false, "generic")
			_clear_card_fusion_number(card)

	for card in specific_materials:
		if is_instance_valid(card):
			_update_card_visual(card, false, "specific")
			_clear_card_fusion_number(card)

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
		if card.has_method("set_fusion_marker"):
			card.set_fusion_marker(card.FusionMarker.NONE)

		_clear_card_fusion_number(card)
		return

	match fusion_type.to_lower():
		"generic":
			if card.has_method("set_fusion_marker"):
				card.set_fusion_marker(card.FusionMarker.GENERIC)
		"specific":
			if card.has_method("set_fusion_marker"):
				card.set_fusion_marker(card.FusionMarker.SPECIFIC)
		_:
			if card.has_method("set_fusion_marker"):
				card.set_fusion_marker(card.FusionMarker.GENERIC)

	_refresh_fusion_numbers()

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
	if not is_instance_valid(card):
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

	_force_card_faceup_attack(card)

	var card_manager = get_node_or_null("../CardManager")
	if card_manager:
		card.scale = Vector2(card_manager.DRAG_SCALE, card_manager.DRAG_SCALE)
		card.z_index = 10

		if fusion_owner == "Player":
			card_manager.card_being_dragged = card
		else:
			card.z_index = 2

	card.owner_side = fusion_owner.to_upper()

	if card.has_method("set_in_hand_mask"):
		card.set_in_hand_mask(false)

	if card.has_method("apply_owner_collision_layers"):
		card.apply_owner_collision_layers()

func can_select_material(fusion_type: String, owner: String = "Player") -> bool:
	owner = _norm_owner(owner)

	if _monster_play_consumed_this_turn(owner):
		return false

	if fusion_in_progress or pending_fusion_card:
		return false

	if fusion_type == "generic":
		return specific_materials.size() == 0

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

func reset_turn(owner: String = "") -> void:
	var normalized_owner := str(owner).strip_edges()

	if normalized_owner == "":
		fusion_performed_this_turn_by_owner["Player"] = false
		fusion_performed_this_turn_by_owner["Opponent"] = false
	else:
		_set_fusion_performed_by_owner(normalized_owner, false)

	fusion_in_progress = false
	is_animating_fusion = false

	if pending_fusion_card:
		var the_owner = "Player"

		if pending_fusion_card.get("owner_side") != null:
			the_owner = "Player" if str(pending_fusion_card.owner_side).to_upper() == "PLAYER" else "Opponent"

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

func _battle_manager():
	return get_node_or_null("../BattleManager")


func _card_manager():
	return get_node_or_null("../CardManager")
