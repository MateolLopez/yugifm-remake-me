extends Node
class_name DuelDrawService

@export var exodia_win_enabled: bool = true
@export var debug_exodia_check: bool = true

@export var exodia_piece_ids: Array[String] = [
	"33396948", # Exodia the Forbidden One
	"70903634", # Right Arm of the Forbidden One
	"07902349", # Left Arm of the Forbidden One
	"08124921", # Right Leg of the Forbidden One
	"44519536"  # Left Leg of the Forbidden One
]

var _exodia_win_resolving: bool = false

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var event_service: DuelEventService = null
var animation_service: DuelAnimationService = null
var rule_service: DuelRuleService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	event_service = bm.event_service
	animation_service = bm.animation_service
	rule_service = bm.rule_service

func _run_initial_draw_sequence() -> void:
	if bm.initial_hands_drawn:
		return

	if bm.duel_finished:
		return

	bm.initial_hands_drawn = true

	animation_service._begin_duel_animation_lock()

	var player_deck = $"../../Deck"
	var player_hand_node = $"../../PlayerHand"

	var opponent_deck = $"../../DeckRival/Deck"
	var opponent_hand_node = $"../../OpponentHand"

	while true:
		if bm.duel_finished:
			break

		var player_can_draw = player_deck.player_deck.size() > 0 and player_hand_node.player_hand.size() < rule_service._max_hand_size()
		var opponent_can_draw = opponent_deck.opponent_deck.size() > 0 and opponent_hand_node.opponent_hand.size() < rule_service._max_hand_size()

		if not player_can_draw and not opponent_can_draw:
			break

		animation_service._play_duel_sfx("draw")

		var player_drew := false
		var opponent_drew := false

		if player_can_draw:
			player_deck.draw_card()
			player_drew = true

		if opponent_can_draw:
			opponent_deck.draw_card()
			opponent_drew = true

		await _wait_draw_step()

	animation_service._end_duel_animation_lock()

func yield_to_refill_opponent_hand():
	var deck_rival = $"../../DeckRival/Deck"
	var opp_hand = $"../../OpponentHand"

	while not bm.duel_finished \
	and deck_rival.opponent_deck.size() > 0 \
	and opp_hand.opponent_hand.size() < rule_service._max_hand_size():

		animation_service._play_duel_sfx("draw")
		deck_rival.draw_card()

		await _wait_draw_step()

		var opponent_exodia := await _check_exodia_after_draw("Opponent")

		if opponent_exodia:
			return

func _wait_draw_step() -> void:
	await get_tree().create_timer(bm.DRAW_STEP_DURATION).timeout
func check_exodia_after_draw(side: String) -> bool:
	return await _check_exodia_after_draw(side)


func _check_exodia_after_draw(side: String) -> bool:
	if bm == null:
		return false

	if bool(bm.duel_finished):
		return true

	if _exodia_win_resolving:
		return true

	if not exodia_win_enabled:
		return false

	side = _norm_side(side)

	if side == "":
		return false

	var report := _get_exodia_report_for_side(side)

	if not bool(report.get("complete", false)):
		return false

	_exodia_win_resolving = true

	if bm.has_method("finish_duel_by_exodia"):
		await bm.finish_duel_by_exodia(side)
	else:
		bm.duel_finished = true

	return true


func _get_exodia_report_for_side(side: String) -> Dictionary:
	var hand_entries := _hand_entries_for_side(side)
	var required := _required_exodia_id_set()

	var hand_ids: Array[String] = []
	var found := {}

	for entry in hand_entries:
		var card_id := _normalize_card_id(_card_id_from_hand_entry(entry))

		if card_id == "":
			continue

		hand_ids.append(card_id)

		if required.has(card_id):
			found[card_id] = true

	var required_ids: Array[String] = []
	for id in required.keys():
		required_ids.append(str(id))

	required_ids.sort()
	hand_ids.sort()

	var found_ids: Array[String] = []
	for id in found.keys():
		found_ids.append(str(id))

	found_ids.sort()

	var missing_ids: Array[String] = []

	for id in required_ids:
		if not found.has(id):
			missing_ids.append(id)

	return {
		"hand_ids": hand_ids,
		"required_ids": required_ids,
		"found_ids": found_ids,
		"missing_ids": missing_ids,
		"complete": missing_ids.is_empty()
	}


func _required_exodia_id_set() -> Dictionary:
	var result := {}

	for raw_id in exodia_piece_ids:
		var id := _normalize_card_id(str(raw_id))

		if id != "":
			result[id] = true

	return result


func _hand_entries_for_side(side: String) -> Array:
	side = _norm_side(side)

	var hand_node: Node = null

	if side == "Player":
		hand_node = get_node_or_null("../../PlayerHand")
	elif side == "Opponent":
		hand_node = get_node_or_null("../../OpponentHand")

	if hand_node == null:
		return []

	var property_name := "player_hand" if side == "Player" else "opponent_hand"

	var value = hand_node.get(property_name)

	if typeof(value) == TYPE_ARRAY:
		return value

	return []


func _card_id_from_hand_entry(entry) -> String:
	match typeof(entry):
		TYPE_STRING:
			return str(entry)

		TYPE_STRING_NAME:
			return str(entry)

		TYPE_INT:
			return str(entry)

		TYPE_FLOAT:
			return str(int(entry))

		TYPE_DICTIONARY:
			var d: Dictionary = entry

			if d.has("id"):
				return str(d.get("id", ""))

			if d.has("card_id"):
				return str(d.get("card_id", ""))

			if d.has("cardId"):
				return str(d.get("cardId", ""))

			if d.has("card"):
				return _card_id_from_hand_entry(d.get("card"))

			if d.has("data"):
				return _card_id_from_hand_entry(d.get("data"))

			if d.has("card_data"):
				return _card_id_from_hand_entry(d.get("card_data"))

			return ""

		TYPE_OBJECT:
			if entry == null:
				return ""

			var obj := entry as Object

			var direct_id = obj.get("id")
			if direct_id != null:
				return str(direct_id)

			var card_id = obj.get("card_id")
			if card_id != null:
				return str(card_id)

			var cardId = obj.get("cardId")
			if cardId != null:
				return str(cardId)

			var data = obj.get("data")
			if data != null:
				var data_id := _card_id_from_hand_entry(data)
				if data_id != "":
					return data_id

			var card_data = obj.get("card_data")
			if card_data != null:
				var card_data_id := _card_id_from_hand_entry(card_data)
				if card_data_id != "":
					return card_data_id

			if obj.has_method("get_card_data"):
				var method_data = obj.call("get_card_data")
				var method_id := _card_id_from_hand_entry(method_data)
				if method_id != "":
					return method_id

			if obj.has_meta("id"):
				return str(obj.get_meta("id"))

			if obj.has_meta("card_id"):
				return str(obj.get_meta("card_id"))

			return ""

		_:
			return ""


func _normalize_card_id(value: String) -> String:
	var id := str(value).strip_edges()

	if id == "":
		return ""

	while id.length() < 8:
		id = "0" + id

	return id


func _norm_side(side: String) -> String:
	var s := str(side).strip_edges().to_upper()

	if s == "PLAYER":
		return "Player"

	if s == "OPPONENT" or s == "RIVAL":
		return "Opponent"

	return ""
