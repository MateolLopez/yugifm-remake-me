extends Node
class_name DuelDrawService

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

	bm.initial_hands_drawn = true

	animation_service._begin_duel_animation_lock()

	var player_deck = $"../../Deck"
	var player_hand_node = $"../../PlayerHand"

	var opponent_deck = $"../../DeckRival/Deck"
	var opponent_hand_node = $"../../OpponentHand"

	while true:
		var player_can_draw = player_deck.player_deck.size() > 0 and player_hand_node.player_hand.size() < rule_service._max_hand_size()
		var opponent_can_draw = opponent_deck.opponent_deck.size() > 0 and opponent_hand_node.opponent_hand.size() < rule_service._max_hand_size()

		if not player_can_draw and not opponent_can_draw:
			break

		animation_service._play_duel_sfx("draw")

		if player_can_draw:
			player_deck.draw_card()

		if opponent_can_draw:
			opponent_deck.draw_card()

		await _wait_draw_step()

	animation_service._end_duel_animation_lock()

func yield_to_refill_opponent_hand():
	var deck_rival = $"../../DeckRival/Deck"
	var opp_hand = $"../../OpponentHand"

	while deck_rival.opponent_deck.size() > 0 and opp_hand.opponent_hand.size() < rule_service._max_hand_size():
		animation_service._play_duel_sfx("draw")
		deck_rival.draw_card()
		await _wait_draw_step()

func _wait_draw_step() -> void:
	await get_tree().create_timer(bm.DRAW_STEP_DURATION).timeout
