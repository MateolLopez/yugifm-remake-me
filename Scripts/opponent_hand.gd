extends Node2D

const CARD_WIDTH := 160
const HAND_Y_POSITION := -100
const DEFAULT_CARD_MOVE_SPEED := 0.2

var opponent_hand: Array = []
var center_screen_x: float

func _ready() -> void:
	center_screen_x = get_viewport().size.x / 2.0

func add_card_to_hand(card: Node2D, speed: float) -> void:
	if not is_instance_valid(card):
		return

	if card in opponent_hand:
		animate_card_to_position(card, card.starting_position, DEFAULT_CARD_MOVE_SPEED)
		return

	# Normalizado a Card.gd actual
	if card.get("owner_side") != null:
		card.owner_side = "OPPONENT"
	if card.has_method("apply_owner_collision_layers"):
		card.apply_owner_collision_layers()
	if card.has_method("set_in_hand_mask"):
		card.set_in_hand_mask(true)
	if card.has_method("set_show_back_only"):
		card.set_show_back_only(true)
	if card.has_method("set_face_down"):
		card.set_face_down(true)
	
	if card.has_method("move_to_zone"):
		card.move_to_zone("HAND")
	elif "current_zone" in card:
		card.current_zone = "HAND"

	if card.has_method("clear_field_slot"):
		card.clear_field_slot()
	elif "current_slot" in card:
		card.current_slot = null
	
	_set_card_interaction(card, false)

	var mgr := get_node_or_null("../CardManager")
	if mgr and mgr.get("HAND_SCALE") != null:
		card.scale = Vector2(mgr.HAND_SCALE, mgr.HAND_SCALE)

	opponent_hand.insert(0, card)
	update_hand_positions(speed)

func update_hand_positions(speed: float) -> void:
	opponent_hand = opponent_hand.filter(func(c): return is_instance_valid(c))
	for i in range(opponent_hand.size()):
		var card: Node2D = opponent_hand[i]
		var new_pos := Vector2(_calc_x(i), HAND_Y_POSITION)
		card.starting_position = new_pos
		animate_card_to_position(card, new_pos, speed)

func _calc_x(index: int) -> float:
	var total_width := float(max(opponent_hand.size() - 1, 0)) * CARD_WIDTH
	return center_screen_x + index * CARD_WIDTH - total_width / 2.0

func animate_card_to_position(card: Node2D, new_position: Vector2, speed: float) -> void:
	if not is_instance_valid(card):
		return
	var tw := get_tree().create_tween()
	tw.tween_property(card, "global_position", new_position, speed)

func remove_card_from_hand(card: Node2D) -> void:
	if card in opponent_hand:
		opponent_hand.erase(card)

	if is_instance_valid(card):
		if card.has_method("set_in_hand_mask"):
			card.set_in_hand_mask(false)

		if card.has_method("move_to_zone"):
			card.move_to_zone("NONE")
		elif "current_zone" in card:
			card.current_zone = "NONE"

	update_hand_positions(DEFAULT_CARD_MOVE_SPEED)

func cleanup_invalid_cards() -> void:
	opponent_hand = opponent_hand.filter(func(c): return is_instance_valid(c) and c.get_parent() != null)
	update_hand_positions(DEFAULT_CARD_MOVE_SPEED)

func has_card(card) -> bool:
	return opponent_hand.has(card)

func _set_card_interaction(card: Node2D, enabled: bool) -> void:
	var area := card.get_node_or_null("Area2D") as Area2D
	if area:
		area.monitoring = enabled
		area.input_pickable = enabled
