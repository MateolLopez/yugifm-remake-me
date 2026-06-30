extends Node
class_name DuelTurnService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var rule_service: DuelRuleService = null
var event_service: DuelEventService = null
var animation_service: DuelAnimationService = null
var destruction_service: DuelDestructionService = null
var kw_service: DuelKeywordService = null
var atk_state_service: DuelAttackStateService = null
var ui_service: DuelUiService = null
var graveyard_service: DuelGraveyardService = null
var draw_service: DuelDrawService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	rule_service = bm.rule_service
	event_service = bm.event_service
	animation_service = bm.animation_service
	destruction_service = bm.destruction_service
	kw_service = bm.kw_service
	atk_state_service = bm.atk_state_service
	ui_service = bm.ui_service
	graveyard_service = bm.graveyard_service
	draw_service = bm.draw_service


func _on_end_turn_button_pressed() -> void:
	if animation_service.is_duel_animating():
		return

	event_service._emit_duel_event("TURN_END", {
		"turn_owner": "Player",
		"controller": "Player",
		"battle_manager": bm
	})

	kw_service._process_timed_keywords_on_turn_end("Player")
	destruction_service._process_scheduled_destruction_on_turn_end("Player")

	for k in bm.multi_mode.keys():
		if is_instance_valid(k) and (k in bm.player_cards_on_battlefield):
			atk_state_service._clear_multi_for(k)

	atk_state_service._cleanup_multi_garbage()

	bm.is_opponent_turn = true
	var cm := get_node_or_null("../../CardManager")
	if cm != null and cm.has_method("cancel_drag_and_restore"):
		cm.cancel_drag_and_restore()

	$"../../CardManager".unselect_selected_monster()
	var fusion_manager := get_node_or_null("../../FusionManager")
	if fusion_manager and fusion_manager.has_method("reset_turn"):
		fusion_manager.reset_turn("Player")

	bm.player_cards_that_attacked_this_turn = []
	bm.opponent_cards_that_attacked_this_turn = []
	bm.multi_attack_targets_this_turn.clear()
	bm.attack_count_this_turn.clear()

	ui_service._refresh_card_usage_overlays()

	graveyard_service._process_pending_end_turn_self_revives("Player")

	$"../../CardManager".reset_played_cards()

	opponent_turn()

func opponent_turn():
	bm.turn_index += 1

	event_service._emit_duel_event("TURN_START", {
		"turn_owner":"Opponent",
		"controller":"Opponent",
		"battle_manager": bm
	})

	if bm.duel_finished:
		return

	$"../../EndTurnButton".disabled = true
	$"../../EndTurnButton".visible = false

	print("OPPONENT TURN: refill start")
	animation_service._begin_duel_animation_lock()
	await draw_service.yield_to_refill_opponent_hand()
	animation_service._end_duel_animation_lock()
	print("OPPONENT TURN: refill end")

	await animation_service.wait_until_duel_idle()
	await action_waiter()

	var opponent_ia = $"../../OpponentIA"
	if opponent_ia:
		print("OPPONENT TURN: IA start")
		await animation_service.wait_until_duel_idle()
		await opponent_ia.make_turn_decisions()
		print("OPPONENT TURN: IA end")
		await animation_service.wait_until_duel_idle()
		await action_waiter()

	print("OPPONENT TURN: calling end_opponent_turn")
	await end_opponent_turn()
	print("OPPONENT TURN: end_opponent_turn finished")

func end_opponent_turn():
	event_service._emit_duel_event("TURN_END", {
		"turn_owner": "Opponent",
		"controller": "Opponent",
		"turn_index": bm.turn_index,
		"battle_manager": bm
	})

	kw_service._process_timed_keywords_on_turn_end("Opponent")
	destruction_service._process_scheduled_destruction_on_turn_end("Opponent")
	graveyard_service._process_pending_end_turn_self_revives("Opponent")

	var player_deck = $"../../Deck"
	var player_hand_node = $"../../PlayerHand"
	var card_manager = $"../../CardManager"

	animation_service._begin_duel_animation_lock()

	card_manager.reset_played_cards()

	for k in bm.multi_mode.keys():
		if is_instance_valid(k) and (k in bm.opponent_cards_on_battlefield):
			atk_state_service._clear_multi_for(k)

	atk_state_service._cleanup_multi_garbage()

	bm.player_cards_that_attacked_this_turn = []
	bm.opponent_cards_that_attacked_this_turn = []
	bm.multi_attack_targets_this_turn.clear()
	bm.attack_count_this_turn.clear()
	
	var fusion_manager := get_node_or_null("../../FusionManager")
	if fusion_manager and fusion_manager.has_method("reset_turn"):
		fusion_manager.reset_turn("Opponent")
	
	while player_deck.player_deck.size() > 0 and player_hand_node.player_hand.size() < rule_service._max_hand_size():
		animation_service._play_duel_sfx("draw")
		player_deck.draw_card()
		card_manager.reset_played_cards()
		await draw_service._wait_draw_step()

	animation_service._end_duel_animation_lock()

	bm.turn_index += 1
	bm.is_opponent_turn = false

	event_service._emit_duel_event("TURN_START", {
		"turn_owner": "Player",
		"controller": "Player",
		"turn_index": bm.turn_index,
		"battle_manager": bm
	})

	ui_service._refresh_card_usage_overlays()

	var im := get_node_or_null("../../InputManager")
	if im != null:
		if "inputs_disabled" in im:
			im.inputs_disabled = false
		if "is_animating" in im:
			im.is_animating = false

	$"../../CardManager".unselect_selected_monster()

	$"../../EndTurnButton".disabled = false
	$"../../EndTurnButton".visible = true

func action_waiter():
	bm.battle_timer.start()
	await bm.battle_timer.timeout
