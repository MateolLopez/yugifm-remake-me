extends Node2D

const CARD_WIDTH := 160
const HAND_Y_POSITION := 920
const DEFAULT_CARD_MOVE_SPEED := 0.2

var player_hand: Array = []
var center_screen_x: float

func _ready() -> void:
	center_screen_x = get_viewport().size.x / 2.0

func add_card_to_hand(card: Node2D, speed: float) -> void:
	if not is_instance_valid(card):
		return

	if card in player_hand:
		animate_card_to_position(card, card.starting_position, DEFAULT_CARD_MOVE_SPEED)
		return
	if card.get("owner_side") != null:
		card.owner_side = "PLAYER"
	if card.has_method("apply_owner_collision_layers"):
		card.apply_owner_collision_layers()
	if card.has_method("set_in_hand_mask"):
		card.set_in_hand_mask(true)
	if card.has_method("set_show_back_only"):
		card.set_show_back_only(false)
	if card.has_method("set_face_down"):
		card.set_face_down(false)

	if card.has_method("move_to_zone"):
		card.move_to_zone("HAND")
	elif "current_zone" in card:
		card.current_zone = "HAND"

	if card.has_method("clear_field_slot"):
		card.clear_field_slot()
	elif "current_slot" in card:
		card.current_slot = null

	_set_card_interaction(card, true)

	var mgr := get_node_or_null("../CardManager")
	if mgr and mgr.get("HAND_SCALE") != null:
		card.scale = Vector2(mgr.HAND_SCALE, mgr.HAND_SCALE)

	player_hand.insert(0, card)
	update_hand_positions(speed)
	_request_exodia_check()

func _request_exodia_check() -> void:
	call_deferred("_check_exodia_deferred")


func _check_exodia_deferred() -> void:
	var bm := get_tree().get_first_node_in_group("battle_manager")

	if bm == null:
		print("EXODIA DEBUG | PlayerHand: no encontró BattleManager en grupo battle_manager.")
		return

	if not ("draw_service" in bm):
		print("EXODIA DEBUG | PlayerHand: BattleManager no tiene draw_service.")
		return

	if bm.draw_service == null:
		print("EXODIA DEBUG | PlayerHand: bm.draw_service es null.")
		return

	if not bm.draw_service.has_method("check_exodia_after_draw"):
		print("EXODIA DEBUG | PlayerHand: draw_service no tiene check_exodia_after_draw().")
		return

	await bm.draw_service.check_exodia_after_draw("Player")

func update_hand_positions(speed: float = DEFAULT_CARD_MOVE_SPEED) -> void:
	player_hand = player_hand.filter(func(c): return is_instance_valid(c))
	for i in range(player_hand.size()):
		var card = player_hand[i] as Card
		if card == null:
			continue
		var new_pos: Vector2 = Vector2(calculate_card_position(i), HAND_Y_POSITION)
		card.starting_position = new_pos
		animate_card_to_position(card, new_pos, speed)
	
	

func calculate_card_position(index: int) -> float:
	var total_width := float(max(player_hand.size() - 1, 0)) * CARD_WIDTH
	return center_screen_x + index * CARD_WIDTH - total_width / 2.0

func animate_card_to_position(card: Node2D, new_position: Vector2, speed: float) -> void:
	if not is_instance_valid(card):
		return
	var tween := get_tree().create_tween()
	tween.tween_property(card, "global_position", new_position, speed)

func remove_card_from_hand(card: Node2D, refresh_layout: bool = true) -> void:
	while card in player_hand:
		player_hand.erase(card)

	if is_instance_valid(card):
		if card.has_method("set_in_hand_mask"):
			card.set_in_hand_mask(false)

		_set_card_interaction(card, false)

		if card.has_method("move_to_zone"):
			card.move_to_zone("NONE")
		elif "current_zone" in card:
			card.current_zone = "NONE"

	if refresh_layout:
		update_hand_positions(DEFAULT_CARD_MOVE_SPEED)

func cleanup_invalid_cards() -> void:
	player_hand = player_hand.filter(func(c): return is_instance_valid(c))
	update_hand_positions(DEFAULT_CARD_MOVE_SPEED)

func has_card(card) -> bool:
	return player_hand.has(card)

func _set_card_interaction(card: Node2D, enabled: bool) -> void:
	var area := card.get_node_or_null("Area2D") as Area2D
	if area:
		area.monitoring = enabled
		area.input_pickable = enabled

func _play_duel_sfx(key: String) -> void:
	var fxm = get_node_or_null("../DuelFxManager")
	if fxm != null and fxm.has_method("play_sfx_key"):
		fxm.play_sfx_key(key)
