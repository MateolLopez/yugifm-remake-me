extends Node2D

const CARD_WIDTH  = 160
const HAND_Y_POSITION = 950
const DEFAULT_CARD_MOVE_SPEED = 0.2

var player_hand: Array = []
var center_screen_x: float

func _ready() -> void:
	center_screen_x = get_viewport().size.x / 2

func add_card_to_hand(card: Node2D, speed: float) -> void:
	if card not in player_hand:
		card.card_owner = "Player"
		card.is_facedown = false
		card.apply_owner_collision_layers()
		_disable_card_interaction_in_hand(card, false)
		var mgr := $"../CardManager"
		card.scale = Vector2(mgr.HAND_SCALE, mgr.HAND_SCALE)
		player_hand.insert(0, card)
		update_hand_positions(speed)
	else:
		animate_card_to_position(card, card.starting_position, DEFAULT_CARD_MOVE_SPEED)

func update_hand_positions(speed: float) -> void:
	player_hand = player_hand.filter(func(card): return is_instance_valid(card))
	
	for i in range(player_hand.size()):
		var card: Node2D = player_hand[i]
		if not is_instance_valid(card):
			continue
		var new_position = Vector2(calculate_card_position(i), HAND_Y_POSITION)
		card.starting_position = new_position
		animate_card_to_position(card, new_position, speed)

func calculate_card_position(index: int) -> float:
	var total_width = (player_hand.size() - 1) * CARD_WIDTH
	var x_offset = center_screen_x + index * CARD_WIDTH - total_width / 2.0
	return x_offset

func animate_card_to_position(card: Node2D, new_position: Vector2, speed: float) -> void:
	var tween = get_tree().create_tween()
	tween.tween_property(card, "global_position", new_position, speed)

func remove_card_from_hand(card: Node2D) -> void:
	if card in player_hand:
		player_hand.erase(card)
		update_hand_positions(DEFAULT_CARD_MOVE_SPEED)

func _disable_card_interaction_in_hand(card: Node2D, on: bool) -> void:
	var area := card.get_node("Area2D") as Area2D
	if area:
		area.monitoring = not on
		area.input_pickable = not on
