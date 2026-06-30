extends Node
class_name DuelCardRuntimeService

var bm: Node = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager

func _norm_owner(owner_value) -> String:
	var s := str(owner_value).strip_edges().to_upper()
	if s == "PLAYER":
		return "Player"
	if s == "OPPONENT":
		return "Opponent"
	return "Player" if str(owner_value) == "" else str(owner_value)

func _opponent_of(owner: String) -> String:
	owner = _norm_owner(owner)

	if owner == "Player":
		return "Opponent"

	if owner == "Opponent":
		return "Player"

	return ""

func _card_kind(card) -> String:
	if not is_instance_valid(card):
		return ""
	var k := ""
	if "kind" in card:
		k = str(card.kind)
	elif "card_type" in card:
		k = str(card.card_type)
	elif "attribute" in card:
		var a := str(card.attribute).to_lower()
		if a == "spell":
			k = "SPELL"
		elif a == "trap":
			k = "TRAP"
	return k.to_upper()

func _card_name(card) -> String:
	if not is_instance_valid(card):
		return "<null>"
	if "cardname" in card and str(card.cardname) != "":
		return str(card.cardname)
	if "card_name" in card:
		return str(card.card_name)
	return str(card.name)

func _card_owner_side(card) -> String:
	if not is_instance_valid(card):
		return ""
	if "owner_side" in card:
		return _norm_owner(card.owner_side)
	if "card_owner" in card:
		return _norm_owner(card.card_owner)
	return ""

func _is_card_face_down(card) -> bool:
	if not is_instance_valid(card):
		return false
	if "face_down" in card:
		return bool(card.face_down)
	if "is_facedown" in card:
		return bool(card.is_facedown)
	return false

func _set_card_owner_side(card, cardowner: String) -> void:
	if not is_instance_valid(card):
		return
	var upper_owner := cardowner.to_upper()
	if "owner_side" in card:
		card.owner_side = upper_owner
	elif "card_owner" in card:
		card.card_owner = cardowner

func _set_card_face_down(card, value: bool) -> void:
	if not is_instance_valid(card):
		return
	if card.has_method("set_face_down"):
		card.set_face_down(value)
	elif card.has_method("set_facedown"):
		card.set_facedown(value)
	elif "face_down" in card:
		card.face_down = value
	elif "is_facedown" in card:
		card.is_facedown = value

func _is_card_alive(card) -> bool:
	return is_instance_valid(card) and (card in bm.player_cards_on_battlefield or card in bm.opponent_cards_on_battlefield)
