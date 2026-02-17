extends Node2D
const CARD_SCENE_PATH = "res://scenes/Card.tscn"
const CARD_DRAW_SPEED = 0.2
const STARTING_HAND_SIZE = 5
const MAX_HAND_SIZE = 5
@export var override_deck : Array = []

var player_deck = ["86988864","86988864","86988864","86988864","86988864","86988864"]
var cards_by_id: Dictionary = {}

func _ready() -> void:
	_load_cards_db()
	if override_deck.size() > 0:
		player_deck = override_deck.duplicate()
	player_deck.shuffle()
	$RichTextLabel.text = str(player_deck.size())
	for i in range(STARTING_HAND_SIZE):
		draw_card()

func _load_cards_db() -> void:
	var path := "res://Scripts/JSON/CardsDB.json"
	if not FileAccess.file_exists(path):
		push_error("Deck: No se encontró CardsDB.json en: %s" % path)
		return

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Deck: No se pudo abrir CardsDB.json: %s" % path)
		return

	var text := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		push_error("Deck: CardsDB.json debe ser un Array de cartas (objetos).")
		return

	for c in parsed:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var id := str(c.get("id", ""))
		if id == "":
			continue
		cards_by_id[id] = c

func draw_card():
	if player_deck.is_empty():
		return
	var player_hand_node = $"../PlayerHand"
	if player_hand_node.player_hand.size() >= MAX_HAND_SIZE:
		return

	var code := str(player_deck[0])
	player_deck.remove_at(0)
	$RichTextLabel.text = str(player_deck.size())

	var db: Dictionary = cards_by_id.get(code, {})
	if db.is_empty():
		push_error("Deck: Card id no encontrado en CardsDB.json: %s" % code)
		return

	var c = preload(CARD_SCENE_PATH).instantiate()
	c.apply_db(db)

	c.card_owner = "Player"
	c.apply_owner_collision_layers()
	c.set_facedown(false)
	c.set_show_back_only(false)

	c.scale = Vector2(0.68, 0.68)

	$"../CardManager".add_child(c)
	c.global_position = global_position
	player_hand_node.add_card_to_hand(c, CARD_DRAW_SPEED)
