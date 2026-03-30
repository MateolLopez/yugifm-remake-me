extends Node2D

const COLLISION_MASK_CARD = 1
const COLLISION_MASK_CARD_SLOT = 2
const DEFAULT_CARD_MOVE_SPEED = 0.2

@export var HAND_SCALE := 0.55
@export var FIELD_SCALE := 0.44
@export var HOVERED_SCALE := 0.60
@export var DRAG_SCALE := 0.60

var screen_size: Vector2
var card_being_dragged: Card = null
var is_hovering_on_card: bool = false
var player_hand_reference: Node = null
var played_monster_card_this_turn: bool = false
var played_spellortrap_card_this_turn: bool = false
var selected_monster: Card = null

func _ready() -> void:
	screen_size = get_viewport_rect().size
	player_hand_reference = get_node_or_null("../PlayerHand")

func _process(_delta: float) -> void:
	if card_being_dragged == null:
		return

	var mp := get_global_mouse_position()
	var anchor := card_being_dragged.get_node_or_null("AnchorCenter") as Node2D
	if anchor:
		var delta := anchor.to_global(Vector2.ZERO) - card_being_dragged.to_global(Vector2.ZERO)
		card_being_dragged.global_position = mp - delta
	else:
		var half = card_being_dragged.get_visual_half_size() * card_being_dragged.global_scale
		card_being_dragged.global_position = mp - half

	var fusion_manager := get_node_or_null("../FusionManager")
	if fusion_manager and fusion_manager.has_method("has_pending_fusion") and fusion_manager.has_pending_fusion():
		var pf = fusion_manager.get("pending_fusion_card")
		if pf and pf is Card and pf.owner_side == "PLAYER" and card_being_dragged == pf and not _battle_manager().is_opponent_turn:
			fusion_manager.call("update_pending_fusion_position", get_global_mouse_position())

func _battle_manager() -> Node:
	return $"../BattleManager"

func _input_manager() -> Node:
	return get_node_or_null("../InputManager")

func is_dragging() -> bool:
	return card_being_dragged != null

func click_to_drop() -> void:
	finish_drag()

func card_clicked(card: Card) -> void:
	if card == null:
		return

	var bm = _battle_manager()
	if card.is_on_field():
		if bm.is_opponent_turn:
			return
		if card in bm.player_cards_that_attacked_this_turn and not bm._has_kw(card, "MULTI_ATTACK_ALL"):
			return
		if bm.spell_targeting:
			bm.receive_spell_target(card)
			return
		if card.is_spell_like():
			activate_spell(card)
			return

		if card.in_defense:
			return
		if card not in bm.player_cards_that_attacked_this_turn:
			if bm.opponent_cards_on_battlefield.size() == 0:
				await bm.direct_attack(card, "Player")
				var im = _input_manager()
				if im:
					im.inputs_disabled = false
				bm.enable_end_turn_button(true)
			else:
				select_card_for_battle(card)
	else:
		start_drag(card)

func activate_spell(card: Card) -> void:
	if card == null or not card.is_on_field():
		return
	_battle_manager().start_spell_activation(card, "Player")

func select_card_for_battle(card: Card) -> void:
	if selected_monster:
		if selected_monster == card:
			card.position.y += 20
			selected_monster = null
		else:
			selected_monster.position.y += 20
			selected_monster = card
			card.position.y -= 20
	else:
		selected_monster = card
		card.position.y -= 20

func start_drag(card: Card) -> void:
	if card == null or card.is_on_field():
		return
	card_being_dragged = card
	card.z_index = 3
	card.scale = Vector2(DRAG_SCALE, DRAG_SCALE)

func _snap_card_to_slot_center(card: Card, slot: Node2D) -> void:
	var card_anchor := card.get_node_or_null("AnchorCenter") as Node2D
	var slot_anchor := slot.get_node_or_null("Anchor") as Node2D
	var target := slot_anchor if slot_anchor else slot
	if card_anchor:
		var delta := card_anchor.to_global(Vector2.ZERO) - card.to_global(Vector2.ZERO)
		card.global_position = target.global_position - delta
	else:
		card.global_position = target.global_position

func _place_card_in_slot(card: Card, slot: Node2D) -> void:
	if not is_instance_valid(card) or not is_instance_valid(slot):
		return

	slot.card_in_slot = true
	if "card_ref" in slot:
		slot.card_ref = card

	card.set_field_slot(slot)
	card.set_show_back_only(false)

	if card.has_method("apply_owner_collision_layers"):
		card.apply_owner_collision_layers()

	var area := card.get_node_or_null("Area2D") as Area2D
	if area:
		area.monitoring = true
		area.input_pickable = true

	if bool(card.get("fusion_result")):
		card.set_face_down(false)
	else:
		card.set_face_down(true)

	card.scale = Vector2(FIELD_SCALE, FIELD_SCALE)
	_snap_card_to_slot_center(card, slot)
	card.z_index = -4
func _card_matches_slot(card: Card, slot: Node) -> bool:
	if card == null or slot == null:
		return false
	var slot_type := str(slot.get("card_slot_type"))
	if slot_type == "Monster":
		return card.is_monster()
	if slot_type == "Spell":
		return card.is_spell_like()
	return false

func finish_drag() -> void:
	if card_being_dragged == null:
		return

	var slot = raycast_check_for_card_slot()
	var card := card_being_dragged
	is_hovering_on_card = false

	var fusion_manager := get_node_or_null("../FusionManager")
	if fusion_manager and fusion_manager.has_method("has_pending_fusion") and fusion_manager.has_pending_fusion() and card == fusion_manager.get("pending_fusion_card"):
		if slot and not bool(slot.get("card_in_slot")):
			if fusion_manager.call("place_fusion_card", slot):
				card_being_dragged = null
				fusion_manager.set("pending_fusion_card", null)
				return
			else:
				return
		else:
			return

	if slot and not bool(slot.get("card_in_slot")) and _card_matches_slot(card, slot):
		if card.is_monster() and played_monster_card_this_turn:
			_restore_visual_and_return_to_hand()
			return
		if card.is_spell_like() and played_spellortrap_card_this_turn:
			_restore_visual_and_return_to_hand()
			return

		if player_hand_reference and player_hand_reference.has_method("remove_card_from_hand"):
			player_hand_reference.remove_card_from_hand(card)
		_place_card_in_slot(card, slot)

		var shape := slot.get_node_or_null("Area2D/CollisionShape2D") as CollisionShape2D
		if shape:
			shape.disabled = true

		var bm = _battle_manager()
		if card.is_monster():
			if not bm.player_cards_on_battlefield.has(card):
				bm.player_cards_on_battlefield.append(card)
			played_monster_card_this_turn = true
			if card.has_method("ensure_guardian_initialized"):
				card.ensure_guardian_initialized()
		else:
			played_spellortrap_card_this_turn = true

		if bm and bm.has_method("register_card_played"):
			bm.register_card_played(card, "Player")

		card_being_dragged = null
		return

	_restore_visual_and_return_to_hand()

func reset_played_cards() -> void:
	played_monster_card_this_turn = false
	played_spellortrap_card_this_turn = false
	var fusion_manager := get_node_or_null("../FusionManager")
	if fusion_manager:
		fusion_manager.set("fusion_performed_this_turn", false)

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

func unselect_selected_monster() -> void:
	if selected_monster:
		selected_monster.position.y += 20
		selected_monster = null

func connect_card_signals(card: Card) -> void:
	if card == null:
		return
	if not card.is_connected("hovered", Callable(self, "on_hovered_over_card")):
		card.connect("hovered", Callable(self, "on_hovered_over_card"))
	if not card.is_connected("hovered_off", Callable(self, "on_hovered_off_card")):
		card.connect("hovered_off", Callable(self, "on_hovered_off_card"))
	if not card.is_connected("clicked", Callable(self, "card_clicked")):
		card.connect("clicked", Callable(self, "card_clicked"))

func on_hovered_over_card(card: Card) -> void:
	if card == null or card.is_on_field():
		return
	if not is_hovering_on_card:
		is_hovering_on_card = true
		highlight_card(card, true)

func on_hovered_off_card(card: Card) -> void:
	if card == null:
		return
	if not card.defeated:
		if not card.is_on_field() and card_being_dragged == null:
			highlight_card(card, false)
			var new_card_hovered = raycast_check_for_card()
			if new_card_hovered:
				highlight_card(new_card_hovered, true)
			else:
				is_hovering_on_card = false

func highlight_card(card: Card, hovered: bool) -> void:
	if card == null or card.is_on_field():
		return
	if hovered:
		card.scale = Vector2(HOVERED_SCALE, HOVERED_SCALE)
		card.z_index = 2
	else:
		card.scale = Vector2(HAND_SCALE, HAND_SCALE)
		card.z_index = 1

func on_left_click_released() -> void:
	if card_being_dragged:
		finish_drag()

func _restore_visual_and_return_to_hand() -> void:
	if card_being_dragged == null:
		return
	card_being_dragged.scale = Vector2(HAND_SCALE, HAND_SCALE)
	card_being_dragged.z_index = 1
	if player_hand_reference and player_hand_reference.has_method("add_card_to_hand"):
		player_hand_reference.add_card_to_hand(card_being_dragged, DEFAULT_CARD_MOVE_SPEED)
	card_being_dragged = null

func reset_played_monster() -> void:
	played_monster_card_this_turn = false
