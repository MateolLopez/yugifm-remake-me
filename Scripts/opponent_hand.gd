extends Node2D

const CARD_WIDTH  = 160
const HAND_Y_POSITION = -100
const DEFAULT_CARD_MOVE_SPEED = 0.2

var opponent_hand: Array = []
var center_screen_x: float

func _ready() -> void:
	center_screen_x = get_viewport().size.x / 2

func add_card_to_hand(card: Node2D, speed: float) -> void:
	if card in opponent_hand:
		animate_card_to_position(card, card.starting_position, DEFAULT_CARD_MOVE_SPEED)
		return

	card.card_owner = "Opponent"
	card.apply_owner_collision_layers()
	card.set_in_hand_mask(true)           
	card.set_show_back_only(true)         
	card.set_facedown(true)               

	var mgr := $"../CardManager"
	card.scale = Vector2(mgr.HAND_SCALE, mgr.HAND_SCALE)

	opponent_hand.insert(0, card)
	update_hand_positions(speed)

func update_hand_positions(speed: float) -> void:
	opponent_hand = opponent_hand.filter(func(card): return is_instance_valid(card))
	for i in range(opponent_hand.size()):
		var card: Node2D = opponent_hand[i]
		var new_pos := Vector2(_calc_x(i), HAND_Y_POSITION)
		card.starting_position = new_pos
		animate_card_to_position(card, new_pos, speed)

func _calc_x(index: int) -> float:
	var total_width := (opponent_hand.size() - 1) * CARD_WIDTH
	return center_screen_x + index * CARD_WIDTH - total_width / 2.0

func animate_card_to_position(card: Node2D, new_position: Vector2, speed: float) -> void:
	var tw := get_tree().create_tween()
	tw.tween_property(card, "global_position", new_position, speed)

func remove_card_from_hand(card: Node2D) -> void:
	if card in opponent_hand:
		opponent_hand.erase(card)
		update_hand_positions(DEFAULT_CARD_MOVE_SPEED)
		card.set_in_hand_mask(false)      
