
extends Node

const MAX_HAND_SIZE := 5
const STARTING_HP := 8000

signal duel_over(result: String)
signal attack_declared(attacker, defender, attacker_owner)
signal turn_started(turn_owner)
signal turn_ended(turn_owner)

var duel_finished := false
var is_opponent_turn := false

var player_cards_on_battlefield: Array = []
var opponent_cards_on_battlefield: Array = []
var player_graveyard: Array = []
var opponent_graveyard: Array = []
var player_cards_that_attacked_this_turn: Array = []

var player_hp := STARTING_HP
var opponent_hp := STARTING_HP

var _pending_position_changes_end_of_battle: Array = []
var _last_known_info: Dictionary = {}

func _ready() -> void:
	add_to_group("battle_manager")
	_sync_hp_labels()
	var end_btn := get_node_or_null("../EndTurnButton")
	if end_btn and not end_btn.is_connected("pressed", Callable(self, "_on_end_turn_button_pressed")):
		end_btn.pressed.connect(_on_end_turn_button_pressed)
	start_turn("Player")

func start_turn(turn_owner: String) -> void:
	if duel_finished:
		return
	is_opponent_turn = (turn_owner == "Opponent")
	if turn_owner == "Player":
		player_cards_that_attacked_this_turn.clear()
	_emit_duel_event("TURN_START", {"turn_owner": turn_owner, "battle_manager": self})
	emit_signal("turn_started", turn_owner)

func end_turn(turn_owner: String) -> void:
	if duel_finished:
		return
	_emit_duel_event("TURN_END", {"turn_owner": turn_owner, "battle_manager": self})
	emit_signal("turn_ended", turn_owner)

func _on_end_turn_button_pressed() -> void:
	if duel_finished:
		return
	end_turn("Player")
	opponent_turn()

func opponent_turn() -> void:
	if duel_finished:
		return
	start_turn("Opponent")
	await get_tree().process_frame
	end_opponent_turn()

func end_opponent_turn() -> void:
	end_turn("Opponent")
	start_turn("Player")
	_enable_player_input(true)

func attack(attacker_card, defender_card, attacker_owner: String) -> void:
	if duel_finished or not is_instance_valid(attacker_card):
		return
	if _get_card_kind(attacker_card) != "MONSTER":
		return

	_reveal_if_needed(attacker_card)
	if is_instance_valid(defender_card):
		_reveal_if_needed(defender_card)

	var battle_ctx := {
		"battle_manager": self,
		"source": attacker_card,
		"attacker": attacker_card,
		"defender": defender_card,
		"attacker_owner": attacker_owner,
		"defender_owner": _owner_of(defender_card),
		"turn_owner": ("Opponent" if is_opponent_turn else "Player")
	}
	emit_signal("attack_declared", attacker_card, defender_card, attacker_owner)
	_emit_duel_event("ON_ATTACK_DECLARATION", battle_ctx)

	if not is_instance_valid(defender_card):
		_resolve_direct_attack(attacker_card, attacker_owner)
		_resolve_scheduled_end_of_battle_changes()
		return

	var atk_value := _get_current_atk(attacker_card)
	var def_is_defense := _is_in_defense(defender_card)
	var def_atk_value := _get_current_atk(defender_card)
	var def_def_value := _get_current_def(defender_card)

	var destroyed: Array = []

	if def_is_defense:
		if atk_value > def_def_value:
			destroyed.append({"card": defender_card, "owner": _owner_of(defender_card), "cause": "DESTROY_BATTLE"})
			if _has_keyword(attacker_card, "PIERCING"):
				_inflict_battle_damage(_opponent_of(attacker_owner), atk_value - def_def_value, attacker_card, defender_card)
		elif atk_value < def_def_value:
			_inflict_battle_damage(attacker_owner, def_def_value - atk_value, defender_card, attacker_card)
	else:
		if atk_value > def_atk_value:
			_inflict_battle_damage(_opponent_of(attacker_owner), atk_value - def_atk_value, attacker_card, defender_card)
			destroyed.append({"card": defender_card, "owner": _owner_of(defender_card), "cause": "DESTROY_BATTLE"})
		elif atk_value < def_atk_value:
			_inflict_battle_damage(attacker_owner, def_atk_value - atk_value, defender_card, attacker_card)
			destroyed.append({"card": attacker_card, "owner": attacker_owner, "cause": "DESTROY_BATTLE"})
		else:
			destroyed.append({"card": attacker_card, "owner": attacker_owner, "cause": "DESTROY_BATTLE"})
			destroyed.append({"card": defender_card, "owner": _owner_of(defender_card), "cause": "DESTROY_BATTLE"})

	for item in destroyed:
		var target = item.get("card")
		if not is_instance_valid(target):
			continue
		if item.get("cause") == "DESTROY_BATTLE" and target != attacker_card and is_instance_valid(attacker_card):
			_emit_duel_event("ON_DESTROY_OPPONENT_MONSTER_BY_BATTLE", {
				"battle_manager": self,
				"source": attacker_card,
				"destroyed": target,
				"controller": attacker_owner
			})
			_emit_duel_event("ON_DESTROY_MONSTER_BY_BATTLE", {
				"battle_manager": self,
				"source": attacker_card,
				"destroyed": target,
				"controller": attacker_owner
			})
		destroy_card(target, str(item.get("owner", "")), str(item.get("cause", "DESTROY_EFFECT")), {
			"battle_manager": self,
			"attacker": attacker_card,
			"defender": defender_card,
			"attacker_owner": attacker_owner,
			"turn_owner": ("Opponent" if is_opponent_turn else "Player")
		})

	_resolve_scheduled_end_of_battle_changes()
	if attacker_owner == "Player" and is_instance_valid(attacker_card) and not player_cards_that_attacked_this_turn.has(attacker_card):
		player_cards_that_attacked_this_turn.append(attacker_card)

func _resolve_direct_attack(attacker_card, attacker_owner: String) -> void:
	_inflict_battle_damage(_opponent_of(attacker_owner), _get_current_atk(attacker_card), attacker_card, null)
	if attacker_owner == "Player" and not player_cards_that_attacked_this_turn.has(attacker_card):
		player_cards_that_attacked_this_turn.append(attacker_card)

func register_card_played(card, controller: String, by_effect := false) -> void:
	if not is_instance_valid(card):
		return
	_register_card_on_field(card, controller)
	_emit_duel_event(("ON_SUMMON_BY_EFFECT" if by_effect else "ON_PLAY"), {
		"battle_manager": self,
		"source": card,
		"controller": controller,
		"turn_owner": ("Opponent" if is_opponent_turn else "Player")
	})
	_register_card_auras(card, controller)

func activate_card(card, controller: String) -> void:
	if not is_instance_valid(card):
		return
	_register_card_on_field(card, controller)
	_emit_duel_event("ON_ACTIVATE", {
		"battle_manager": self,
		"source": card,
		"controller": controller,
		"turn_owner": ("Opponent" if is_opponent_turn else "Player")
	})
	_register_card_auras(card, controller)

func register_card_flip(card, controller: String) -> void:
	if not is_instance_valid(card):
		return
	_reveal_if_needed(card)
	_emit_duel_event("ON_FLIP", {
		"battle_manager": self,
		"source": card,
		"controller": controller,
		"turn_owner": ("Opponent" if is_opponent_turn else "Player")
	})

func destroy_by_selector(source, selector, ctx: Dictionary = {}) -> void:
	for target in _resolve_selector_targets(source, selector):
		var target_owner: String = _owner_of(target)
		if target_owner == "":
			continue
		destroy_card(target, target_owner, "DESTROY_EFFECT", _merge_ctx(ctx, {
			"battle_manager": self,
			"effect_source": source
		}))

func reveal_set_cards_by_selector(source, selector, count = null, _reveal_to := "OWNER_ONLY", _ctx: Dictionary = {}) -> void:
	var targets := _resolve_selector_targets(source, selector)
	var limit: int = targets.size() if count == null else min(int(count), targets.size())
	for i in range(limit):
		_reveal_if_needed(targets[i])

func schedule_change_position_end_of_battle(source, new_position: String, _ctx: Dictionary = {}) -> void:
	if is_instance_valid(source):
		_pending_position_changes_end_of_battle.append({"card": source, "new_position": new_position})

func apply_keyword_to_card_if_matches_side(source, played, target_side: String, keyword: String, _ctx: Dictionary = {}) -> void:
	if not is_instance_valid(source) or not is_instance_valid(played):
		return
	if _get_card_kind(played) != "MONSTER":
		return
	var source_owner := _owner_of(source)
	var played_owner := _owner_of(played)
	var ok := false
	match target_side:
		"OWNER": ok = played_owner == source_owner
		"OPPONENT": ok = played_owner != source_owner and played_owner != ""
		"BOTH": ok = true
		_: ok = false
	if not ok:
		return
	if played.has_method("add_keyword"):
		played.add_keyword(keyword)
	else:
		var kws = played.get("keywords")
		if kws is Array and not kws.has(keyword):
			kws.append(keyword)
			played.keywords = kws

func summon_token_from_source_lki(_source, _params: Dictionary, _ctx: Dictionary = {}) -> void:
	push_warning("battle_manager: summon_token_from_source_lki pendiente (falta factory/spawner del proyecto).")

func destroy_card(card, card_owner: String, cause := "DESTROY_EFFECT", ctx: Dictionary = {}) -> void:
	if not is_instance_valid(card):
		return

	_capture_lki(card)
	_unregister_card_from_field(card)
	_register_card_left_auras(card)

	var base_ctx := _merge_ctx(ctx, {
		"battle_manager": self,
		"source": card,
		"controller": card_owner,
		"cause": cause,
		"turn_owner": ("Opponent" if is_opponent_turn else "Player")
	})

	var specific_destroy := _destroy_cause_to_trigger(cause)
	if specific_destroy != "":
		_emit_duel_event(specific_destroy, base_ctx)
	_emit_duel_event("ON_DESTROY", base_ctx)
	_emit_duel_event("ON_LEAVE_FIELD", _merge_ctx(base_ctx, {"from_zone": "FIELD", "to_zone": "GRAVE"}))
	_emit_duel_event("ON_SEND_TO_GRAVE", base_ctx)
	if cause == "DESTROY_EFFECT":
		_emit_duel_event("ON_SEND_TO_GRAVE_BY_EFFECT", base_ctx)

	_move_card_to_grave(card, card_owner)
	_check_end_duel()

func _emit_duel_event(event_name: String, payload: Dictionary) -> void:
	var bus = get_node_or_null("/root/DuelEventBus")
	if bus == null:
		bus = get_node_or_null("/root/EventBus")
	if bus and bus.has_method("emit_event"):
		bus.emit_event(event_name, payload)

func _register_card_auras(card, controller: String) -> void:
	var engine = get_node_or_null("/root/DuelEffectEngine")
	if engine == null:
		engine = get_node_or_null("/root/EffectEngine")
	if engine and engine.has_method("register_card_entered_field"):
		engine.register_card_entered_field(card, controller)

func _register_card_left_auras(card) -> void:
	var engine = get_node_or_null("/root/DuelEffectEngine")
	if engine == null:
		engine = get_node_or_null("/root/EffectEngine")
	if engine and engine.has_method("register_card_left_field"):
		engine.register_card_left_field(card)

func _register_card_on_field(card, controller: String) -> void:
	if controller == "Player":
		if not player_cards_on_battlefield.has(card):
			player_cards_on_battlefield.append(card)
	else:
		if not opponent_cards_on_battlefield.has(card):
			opponent_cards_on_battlefield.append(card)

func _unregister_card_from_field(card) -> void:
	player_cards_on_battlefield.erase(card)
	opponent_cards_on_battlefield.erase(card)
	player_cards_that_attacked_this_turn.erase(card)

func _move_card_to_grave(card, controller: String) -> void:
	if controller == "Player":
		if not player_graveyard.has(card):
			player_graveyard.append(card)
	else:
		if not opponent_graveyard.has(card):
			opponent_graveyard.append(card)
	if card.has_method("queue_free"):
		card.queue_free()

func _owner_of(card) -> String:
	if not is_instance_valid(card):
		return ""
	if player_cards_on_battlefield.has(card):
		return "Player"
	if opponent_cards_on_battlefield.has(card):
		return "Opponent"
	var owner_side = str(card.get("owner_side", ""))
	if owner_side == "OWNER":
		return "Player"
	if owner_side == "OPPONENT":
		return "Opponent"
	return ""

func _opponent_of(controller: String) -> String:
	return "Opponent" if controller == "Player" else "Player"

func _get_card_kind(card) -> String:
	return str(card.get("kind", "")) if is_instance_valid(card) else ""

func _get_current_atk(card) -> int:
	return int(card.get("atk", 0)) if is_instance_valid(card) else 0

func _get_current_def(card) -> int:
	return int(card.get("def", 0)) if is_instance_valid(card) else 0

func _is_in_defense(card) -> bool:
	if not is_instance_valid(card):
		return false
	if card.get("in_defense") != null:
		return bool(card.get("in_defense"))
	var pos = card.get("battle_position")
	if pos != null:
		return str(pos) in ["DEFENSE", "FACEUP_DEF", "FACEDOWN_DEF"]
	return false

func _set_position(card, new_position: String) -> void:
	if not is_instance_valid(card):
		return
	match new_position:
		"ATTACK":
			if card.get("battle_position") != null:
				card.battle_position = "ATTACK"
			if card.get("in_defense") != null:
				card.in_defense = false
		"DEFENSE":
			if card.get("battle_position") != null:
				card.battle_position = "DEFENSE"
			if card.get("in_defense") != null:
				card.in_defense = true
		"TOGGLE":
			_set_position(card, "ATTACK" if _is_in_defense(card) else "DEFENSE")
		_:
			pass

func _resolve_scheduled_end_of_battle_changes() -> void:
	for item in _pending_position_changes_end_of_battle:
		var c = item.get("card")
		if is_instance_valid(c):
			_set_position(c, str(item.get("new_position", "TOGGLE")))
	_pending_position_changes_end_of_battle.clear()

func _has_keyword(card, keyword: String) -> bool:
	if not is_instance_valid(card):
		return false
	var kws = card.get("keywords")
	return kws is Array and kws.has(keyword)

func _reveal_if_needed(card) -> void:
	if not is_instance_valid(card):
		return
	if card.has_method("set_face_down"):
		card.set_face_down(false)
	elif card.has_method("set_facedown"):
		card.set_facedown(false)

func _inflict_battle_damage(target_owner: String, amount: int, source_card, defender_card) -> void:
	if amount <= 0:
		return
	if target_owner == "Player":
		player_hp = max(0, player_hp - amount)
	else:
		opponent_hp = max(0, opponent_hp - amount)
	_sync_hp_labels()
	_emit_duel_event("ON_INFLICT_BATTLE_DAMAGE", {
		"battle_manager": self,
		"source": source_card,
		"target_player": target_owner,
		"amount": amount,
		"defender": defender_card,
		"turn_owner": ("Opponent" if is_opponent_turn else "Player")
	})
	_check_end_duel()

func _sync_hp_labels() -> void:
	var p = get_node_or_null("../PlayerHP")
	if p:
		p.text = str(player_hp)
	var o = get_node_or_null("../OpponentHP")
	if o:
		o.text = str(opponent_hp)

func _enable_player_input(enabled: bool) -> void:
	var im = get_node_or_null("../InputManager")
	if im and im.get("inputs_disabled") != null:
		im.inputs_disabled = not enabled
	var btn = get_node_or_null("../EndTurnButton")
	if btn:
		btn.disabled = not enabled
		btn.visible = true

func _check_end_duel() -> bool:
	if duel_finished:
		return true
	if player_hp <= 0 and opponent_hp <= 0:
		duel_finished = true
		emit_signal("duel_over", "draw")
	elif player_hp <= 0:
		duel_finished = true
		emit_signal("duel_over", "player_defeat")
	elif opponent_hp <= 0:
		duel_finished = true
		emit_signal("duel_over", "player_victory")
	return duel_finished

func _capture_lki(card) -> void:
	if not is_instance_valid(card):
		return
	_last_known_info[card.get_instance_id()] = {
		"id": str(card.get("id", "")),
		"cardname": str(card.get("cardname", "")),
		"atk": int(card.get("atk", 0)),
		"def": int(card.get("def", 0)),
		"keywords": (card.get("keywords", []) if card.get("keywords", []) is Array else []).duplicate(true),
		"owner": _owner_of(card)
	}

func _destroy_cause_to_trigger(cause: String) -> String:
	match cause:
		"DESTROY_BATTLE":
			return "ON_DESTROY_BATTLE"
		"DESTROY_EFFECT":
			return "ON_DESTROY_EFFECT"
		_:
			return ""

func _resolve_selector_targets(source, selector) -> Array:
	if selector is Dictionary:
		return _resolve_selector_object(source, selector)
	if selector is String:
		match String(selector):
			"SELF":
				return [source] if is_instance_valid(source) else []
			"OPPONENT_RANDOM_MONSTER":
				var opp = _field_for_side(_opponent_of(_owner_of(source)))
				opp = opp.filter(func(c): return is_instance_valid(c))
				return [] if opp.is_empty() else [opp[randi() % opp.size()]]
			"OPPONENT_LOWEST_ATK_MONSTER":
				return _pick_stat_monster(_field_for_side(_opponent_of(_owner_of(source))), "atk", true)
			"OPPONENT_HIGHEST_ATK_MONSTER":
				return _pick_stat_monster(_field_for_side(_opponent_of(_owner_of(source))), "atk", false)
			"OPPONENT_LOWEST_DEF_MONSTER":
				return _pick_stat_monster(_field_for_side(_opponent_of(_owner_of(source))), "def", true)
			"OPPONENT_HIGHEST_DEF_MONSTER":
				return _pick_stat_monster(_field_for_side(_opponent_of(_owner_of(source))), "def", false)
			_:
				return []
	return []

func _resolve_selector_object(source, selector: Dictionary) -> Array:
	var side := str(selector.get("side", "OPPONENT"))
	var zone := str(selector.get("zone", "MONSTER"))
	if zone != "MONSTER":
		return []
	var source_owner: String = _owner_of(source)
	var candidates: Array = []
	match side:
		"OWNER": candidates = _field_for_side(source_owner)
		"OPPONENT": candidates = _field_for_side(_opponent_of(source_owner))
		"BOTH": candidates = player_cards_on_battlefield + opponent_cards_on_battlefield
		_: candidates = []
	candidates = candidates.filter(func(c): return is_instance_valid(c))
	var pick := str(selector.get("pick", "RANDOM"))
	match pick:
		"SELF": return [source] if is_instance_valid(source) else []
		"HIGHEST_ATK": return _pick_stat_monster(candidates, "atk", false)
		"LOWEST_ATK": return _pick_stat_monster(candidates, "atk", true)
		"HIGHEST_DEF": return _pick_stat_monster(candidates, "def", false)
		"LOWEST_DEF": return _pick_stat_monster(candidates, "def", true)
		"RANDOM":
			return [] if candidates.is_empty() else [candidates[randi() % candidates.size()]]
		_:
			return [] if candidates.is_empty() else [candidates[0]]

func _field_for_side(side: String) -> Array:
	return player_cards_on_battlefield if side == "Player" else opponent_cards_on_battlefield

func _pick_stat_monster(candidates: Array, stat: String, asc: bool) -> Array:
	var live := candidates.filter(func(c): return is_instance_valid(c))
	if live.is_empty():
		return []
	live.sort_custom(func(a, b):
		var av = int(a.get(stat, 0))
		var bv = int(b.get(stat, 0))
		return av < bv if asc else av > bv
	)
	return [live[0]]

func _merge_ctx(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in extra.keys():
		out[k] = extra[k]
	return out
