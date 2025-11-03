# opponent_deck.gd
extends Node2D
const CARD_SCENE_PATH = "res://scenes/Card.tscn"
const CARD_DRAW_SPEED = 0.2
const STARTING_HAND_SIZE = 5
const MAX_HAND_SIZE = 5
@export var override_deck: Array = []
var opponent_deck = ["000005","000005","000005","000005","000005","000005","000005","000005","000005","000005","000005","000001","000001","000001"]
var card_db_reference


func _ready() -> void:
	if override_deck.size() > 0:
		opponent_deck = override_deck.duplicate()
	opponent_deck.shuffle()
	$RichTextLabel.text = str(opponent_deck.size())
	card_db_reference = preload("res://Scripts/CardDB.gd")
	for i in range(STARTING_HAND_SIZE):
		draw_card()

func draw_card():
	if opponent_deck.is_empty(): return
	var opponent_hand_node = $"../../OpponentHand"
	if opponent_hand_node.opponent_hand.size() >= MAX_HAND_SIZE: return

	var code = opponent_deck[0]
	opponent_deck.erase(code)
	$RichTextLabel.text = str(opponent_deck.size())

	var c = preload(CARD_SCENE_PATH).instantiate()
	var db = card_db_reference.CARDS[code]
	c.apply_db(db)

	c.card_owner = "Opponent"
	c.apply_owner_collision_layers()
	c.set_show_back_only(true)   
	c.set_facedown(true)    
	c.set_in_hand_mask(true)     

	var mgr := $"../../CardManager"
	c.scale = Vector2(mgr.HAND_SCALE, mgr.HAND_SCALE)
	$"../../CardManager".add_child(c)
	c.global_position = global_position
	opponent_hand_node.add_card_to_hand(c, CARD_DRAW_SPEED)
