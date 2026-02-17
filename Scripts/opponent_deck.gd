extends Node2D
const CARD_SCENE_PATH = "res://scenes/Card.tscn"
const CARD_DRAW_SPEED = 0.2
const STARTING_HAND_SIZE = 5
const MAX_HAND_SIZE = 5
@export var override_deck: Array = []

var opponent_deck = ["97017120","97017120","97017120","97017120","97017120","97017120","97017120","97017120","97017120","97017120"]
var cards_by_id: Dictionary = {}

func _ready() -> void:
	_load_cards_db()
	if override_deck.size() > 0:
		opponent_deck = override_deck.duplicate()
	opponent_deck.shuffle()
	$RichTextLabel.text = str(opponent_deck.size())
	for i in range(STARTING_HAND_SIZE):
		draw_card()

func _load_cards_db() -> void:
	var path := "res://Scripts/JSON/CardsDB.json"
	if not FileAccess.file_exists(path):
		push_error("OpponentDeck: No se encontró CardsDB.json en: %s" % path)
		return

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("OpponentDeck: No se pudo abrir CardsDB.json: %s" % path)
		return

	var text := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		push_error("OpponentDeck: CardsDB.json debe ser un Array de cartas (objetos).")
		return

	for c in parsed:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var id := str(c.get("id", ""))
		if id == "":
			continue
		cards_by_id[id] = c

func draw_card():
	if opponent_deck.is_empty():
		return
	var opponent_hand_node = $"../../OpponentHand"
	if opponent_hand_node.opponent_hand.size() >= MAX_HAND_SIZE:
		return

	var code := str(opponent_deck[0])
	opponent_deck.remove_at(0)
	$RichTextLabel.text = str(opponent_deck.size())

	var db: Dictionary = cards_by_id.get(code, {})
	if db.is_empty():
		push_error("OpponentDeck: Card id no encontrado en CardsDB.json: %s" % code)
		return

	var c = preload(CARD_SCENE_PATH).instantiate()
	c.apply_db(db)

	c.owner_side = "OPPONENT"
	c.apply_owner_collision_layers()
	c.set_show_back_only(true)
	c.set_facedown(true)
	c.set_in_hand_mask(true)

	var mgr := $"../../CardManager"
	c.scale = Vector2(mgr.HAND_SCALE, mgr.HAND_SCALE)
	$"../../CardManager".add_child(c)
	c.global_position = global_position

	opponent_hand_node.add_card_to_hand(c, CARD_DRAW_SPEED)
