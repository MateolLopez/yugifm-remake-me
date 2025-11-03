extends Node2D

const COLLISION_MASK_CARD = 1
const COLLISION_MASK_CARD_SLOT = 2
const DEFAULT_CARD_MOVE_SPEED = 0.2

@export var HAND_SCALE := 0.55
@export var FIELD_SCALE := 0.44
@export var HOVERED_SCALE := 0.60
@export var DRAG_SCALE := 0.60

var screen_size
var card_being_dragged
var is_hovering_on_card
var player_hand_reference
var played_monster_card_this_turn = false
var played_spellortrap_card_this_turn = false
var selected_monster
var drag_half := Vector2.ZERO

func _ready() -> void:
	screen_size = get_viewport_rect().size
	player_hand_reference = $"../PlayerHand"

func _process(_delta: float) -> void:
	if card_being_dragged:
		var mp := get_global_mouse_position()
		var anchor := card_being_dragged.get_node_or_null("AnchorCenter") as Node2D
		if anchor:
			var delta = anchor.to_global(Vector2.ZERO) - card_being_dragged.to_global(Vector2.ZERO)
			card_being_dragged.global_position = mp - delta
		else:
			var half = card_being_dragged.get_visual_half_size() * card_being_dragged.global_scale
			card_being_dragged.global_position = mp - half
		var fusion_manager = $"../FusionManager"
		if fusion_manager.has_pending_fusion():
			var pf = fusion_manager.pending_fusion_card
			if pf and pf.card_owner == "Player" and card_being_dragged == pf and not $"../BattleManager".is_opponent_turn:
				fusion_manager.update_pending_fusion_position(get_global_mouse_position())

func is_dragging() -> bool:
	return card_being_dragged != null

func click_to_drop() -> void:
	finish_drag()

func card_clicked(card):
	if card.card_slot_card_is_in:
		if $"../BattleManager".is_opponent_turn:
			return
		if card in $"../BattleManager".player_cards_that_attacked_this_turn:
			return
		if $"../BattleManager".spell_targeting:
			$"../BattleManager".receive_spell_target(card)
			return
		if card.card_type == "Spell":
			activate_spell(card)
			return

		# Ataque / selección de atacante
		if not $"../BattleManager".is_opponent_turn:
			if card.in_defense:
				return
			if card not in $"../BattleManager".player_cards_that_attacked_this_turn:
				if $"../BattleManager".opponent_cards_on_battlefield.size() == 0:
					await $"../BattleManager".direct_attack(card, "Player")
					$"../InputManager".inputs_disabled = false
					$"../BattleManager".enable_end_turn_button(true)
				else:
					select_card_for_battle(card)
	else:
		start_drag(card)

func activate_spell(card):
	if not card.card_slot_card_is_in:
		return
	$"../BattleManager".start_spell_activation(card, "Player")

func select_card_for_battle(card):
	if selected_monster:
		if selected_monster == card:
			card.position.y += 20
			selected_monster = null
		else:
			card.position.y += 20
			selected_monster = card
			card.position.y -= 20
	else:
		selected_monster = card
		card.position.y -= 20

func start_drag(card):
	if card.card_slot_card_is_in:
		return
	card_being_dragged = card
	card.z_index = 3
	card.scale = Vector2(DRAG_SCALE, DRAG_SCALE)

func _snap_card_to_slot_center(card: Node2D, slot: Node2D) -> void:
	var card_anchor := card.get_node_or_null("AnchorCenter") as Node2D
	var slot_anchor := slot.get_node_or_null("Anchor") as Node2D
	var target := slot_anchor if slot_anchor else slot
	var delta := card_anchor.to_global(Vector2.ZERO) - card.to_global(Vector2.ZERO)
	card.global_position = target.global_position - delta

func _place_card_in_slot(card: Node2D, slot: Node2D) -> void:
	card.card_slot_card_is_in = slot
	slot.card_in_slot = true
	card.set_show_back_only(false)
	card.set_facedown(true) # Cartas player y oponente entran boca abajo siempre
	if card.get("fusion_result"): #Excepto cuando son resultado de fusiones o rituales
		card.set_facedown(false)
	else:
		card.set_facedown(true)
	card.scale = Vector2(FIELD_SCALE, FIELD_SCALE)
	_snap_card_to_slot_center(card, slot)
	card.z_index = -4

# En finish_drag(), verificar el owner de la carta
func finish_drag():
	if card_being_dragged == null:
		return

	var slot = raycast_check_for_card_slot()
	var card = card_being_dragged
	is_hovering_on_card = false
	
	var fusion_manager = $"../FusionManager"
	if fusion_manager.has_pending_fusion() and card == fusion_manager.pending_fusion_card:
		if slot and not slot.card_in_slot:
			if fusion_manager.place_fusion_card(slot):
				card_being_dragged = null
				fusion_manager.pending_fusion_card = null
				return
			else:
				return
		else:
			return
	
	if slot and not slot.card_in_slot:
		if card.card_type == slot.card_slot_type:
			# VERIFICAR LÍMITES POR TURNO
			if card.card_type == "Monster" and played_monster_card_this_turn:
				_restore_visual_and_return_to_hand()
				return
			if (card.card_type == "Spell" or card.card_type == "Trap") and played_spellortrap_card_this_turn:
				_restore_visual_and_return_to_hand()
				return

			player_hand_reference.remove_card_from_hand(card)
			_place_card_in_slot(card, slot)

			var shape := slot.get_node("Area2D/CollisionShape2D") as CollisionShape2D
			if shape:
				shape.disabled = true

			if card.card_type == "Monster":
				$"../BattleManager".player_cards_on_battlefield.append(card)
				played_monster_card_this_turn = true  # Marcar que se jugó un monstruo
				if card.has_method("ensure_guardian_initialized"):
					card.ensure_guardian_initialized()
			elif card.card_type == "Spell" or card.card_type == "Trap":
				played_spellortrap_card_this_turn = true  # Marcar que se jugó un hechizo/trampa

			card_being_dragged = null
			return

	_restore_visual_and_return_to_hand()
	card_being_dragged = null

func reset_played_cards():
	played_monster_card_this_turn = false
	played_spellortrap_card_this_turn = false
	if has_node("../FusionManager"):
		get_node("../FusionManager").fusion_performed_this_turn = false

func raycast_check_for_card():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD
	var result = space_state.intersect_point(parameters)
	if result.size() > 0:
		return get_card_with_highest_z_index(result)
	return null

func raycast_check_for_card_slot():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD_SLOT
	var result = space_state.intersect_point(parameters)
	if result.size() > 0:
		return result[0].collider.get_parent()
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

func unselect_selected_monster():
	if selected_monster:
		selected_monster.position.y += 20
		selected_monster = null

func connect_card_signals(card):
	card.connect("hovered", on_hovered_over_card)
	card.connect("hovered_off", on_hovered_off_card)

func on_hovered_over_card(card):
	if card.card_slot_card_is_in:
		return
	if !is_hovering_on_card:
		is_hovering_on_card = true
		highlight_card(card, true)

func on_hovered_off_card(card):
	if !card.defeated:
		if !card.card_slot_card_is_in and !card_being_dragged:
			highlight_card(card, false)
			var new_card_hovered = raycast_check_for_card()
			if new_card_hovered:
				highlight_card(new_card_hovered, true)
			else:
				is_hovering_on_card = false

func highlight_card(card, hovered):
	if card.card_slot_card_is_in:
		return
	if hovered:
		card.scale = Vector2(HOVERED_SCALE, HOVERED_SCALE)
		card.z_index = 2
	else:
		card.scale = Vector2(HAND_SCALE, HAND_SCALE)
		card.z_index = 1

func on_left_click_released():
	if card_being_dragged:
		finish_drag()

func _restore_visual_and_return_to_hand():
	card_being_dragged.scale = Vector2(HAND_SCALE, HAND_SCALE)
	card_being_dragged.z_index = 1
	player_hand_reference.add_card_to_hand(card_being_dragged, DEFAULT_CARD_MOVE_SPEED)
	card_being_dragged = null

func reset_played_monster():
	played_monster_card_this_turn = false
