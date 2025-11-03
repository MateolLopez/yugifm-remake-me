extends Node2D
const CARD_SCENE_PATH = "res://scenes/Card.tscn"
const CARD_DRAW_SPEED = 0.2
const STARTING_HAND_SIZE = 5
const MAX_HAND_SIZE = 5
@export var override_deck : Array = []

var player_deck = ["000002","000002","000002","000002","000002","000002"]
var card_db_reference

func _ready() -> void:
	if override_deck.size() > 0:
		player_deck = override_deck.duplicate()
	player_deck.shuffle()
	$RichTextLabel.text = str(player_deck.size())
	card_db_reference = preload("res://Scripts/CardDB.gd")
	for i in range(STARTING_HAND_SIZE):
		draw_card()

func draw_card():
	if player_deck.is_empty(): return
	var player_hand_node = $"../PlayerHand"
	if player_hand_node.player_hand.size() >= MAX_HAND_SIZE: return

	var code = player_deck[0]
	player_deck.erase(code)
	$RichTextLabel.text = str(player_deck.size())

	var c = preload(CARD_SCENE_PATH).instantiate()
	var db = card_db_reference.CARDS[code]
	c.apply_db(db)

	c.card_owner = "Player"
	c.apply_owner_collision_layers()
	c.set_facedown(false)
	c.set_show_back_only(false)

	c.scale = Vector2(0.68, 0.68)

	$"../CardManager".add_child(c)
	c.global_position = global_position
	player_hand_node.add_card_to_hand(c, CARD_DRAW_SPEED)
