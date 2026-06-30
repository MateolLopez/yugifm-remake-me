extends Node
class_name DuelUiService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null
var kw_service: DuelKeywordService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service
	kw_service = bm.kw_service

func enable_end_turn_button(is_enabled):
	if is_enabled:
		$"../../EndTurnButton".disabled = false
		$"../../EndTurnButton".visible = true
	else:
		$"../../EndTurnButton".disabled = true
		$"../../EndTurnButton".visible = false

func _enable_player_input():
	$"../../InputManager".inputs_disabled = false
	enable_end_turn_button(true)

func _set_card_usage_dimmed(card: Node, dimmed: bool, reason: String = "") -> void:
	if not is_instance_valid(card):
		return

	if card.has_method("set_usage_dimmed"):
		card.set_usage_dimmed(dimmed, reason)

func _refresh_card_usage_overlays() -> void:
	var all_cards: Array = []
	all_cards.append_array(bm.player_cards_on_battlefield)
	all_cards.append_array(bm.opponent_cards_on_battlefield)

	for card in all_cards:
		if not is_instance_valid(card):
			continue

		var kind := card_runtime_service._card_kind(card)
		var owner := card_runtime_service._norm_owner(zone_service._owner_of(card))

		var dimmed := false
		var reason := ""

		if kind == "TRAP":
			dimmed = true
			reason = "TRAP_REACTIVE_ONLY"

		elif owner == "Player" and card in bm.player_cards_that_attacked_this_turn:
			dimmed = true
			reason = "ALREADY_ATTACKED_THIS_TURN"

		elif owner == "Opponent" and card in bm.opponent_cards_that_attacked_this_turn:
			dimmed = true
			reason = "ALREADY_ATTACKED_THIS_TURN"

		elif kind == "MONSTER" and kw_service._has_kw(card, "PARALYZED"):
			dimmed = true
			reason = "PARALYZED"

		_set_card_usage_dimmed(card, dimmed, reason)
