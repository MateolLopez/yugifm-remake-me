extends Node2D

const CARD_WIDTH := 160
const HAND_Y_POSITION := 920
const DEFAULT_CARD_MOVE_SPEED := 0.2

var player_hand: Array = []
var center_screen_x: float

func _ready() -> void:
	center_screen_x = get_viewport().size.x / 2.0

func add_card_to_hand(card: Node2D, speed: float) -> void:
	if not is_instance_valid(card):
		return

	if card in player_hand:
		animate_card_to_position(card, card.starting_position, DEFAULT_CARD_MOVE_SPEED)
		return

	# Normalizado a Card.gd actual
	if card.get("owner_side") != null:
		card.owner_side = "PLAYER"
	if card.has_method("apply_owner_collision_layers"):
		card.apply_owner_collision_layers()
	if card.has_method("set_in_hand_mask"):
		card.set_in_hand_mask(true)
	if card.has_method("set_show_back_only"):
		card.set_show_back_only(false)
	if card.has_method("set_face_down"):
		card.set_face_down(false)

	_set_card_interaction(card, true)

	var mgr := get_node_or_null("../CardManager")
	if mgr and mgr.get("HAND_SCALE") != null:
		card.scale = Vector2(mgr.HAND_SCALE, mgr.HAND_SCALE)

	player_hand.insert(0, card)
	update_hand_positions(speed)

func update_hand_positions(speed: float) -> void:
	player_hand = player_hand.filter(func(c): return is_instance_valid(c))
	for i in range(player_hand.size()):
		var card = player_hand[i] as Card
		if card == null:
			continue
		var new_pos: Vector2 = Vector2(calculate_card_position(i), HAND_Y_POSITION)
		card.starting_position = new_pos
		animate_card_to_position(card, new_pos, speed)

func calculate_card_position(index: int) -> float:
	var total_width := float(max(player_hand.size() - 1, 0)) * CARD_WIDTH
	return center_screen_x + index * CARD_WIDTH - total_width / 2.0

func animate_card_to_position(card: Node2D, new_position: Vector2, speed: float) -> void:
	if not is_instance_valid(card):
		return
	var tween := get_tree().create_tween()
	tween.tween_property(card, "global_position", new_position, speed)

func remove_card_from_hand(card: Node2D) -> void:
	if card in player_hand:
		player_hand.erase(card)
	if is_instance_valid(card):
		if card.has_method("set_in_hand_mask"):
			card.set_in_hand_mask(false)
		_set_card_interaction(card, false)
	update_hand_positions(DEFAULT_CARD_MOVE_SPEED)

func cleanup_invalid_cards() -> void:
	player_hand = player_hand.filter(func(c): return is_instance_valid(c))
	update_hand_positions(DEFAULT_CARD_MOVE_SPEED)

func has_card(card) -> bool:
	return player_hand.has(card)

func _set_card_interaction(card: Node2D, enabled: bool) -> void:
	var area := card.get_node_or_null("Area2D") as Area2D
	if area:
		area.monitoring = enabled
		area.input_pickable = enabled
