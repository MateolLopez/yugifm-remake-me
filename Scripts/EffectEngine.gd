extends Node
class_name EffectEngine

var effectref: Dictionary = {}
var templates: Dictionary = {}
var keywords: Dictionary = {}

var active_auras: Array = []
var field_cards: Array = []
var field_controller_by_id: Dictionary = {} 
var once_per_instance_used: Dictionary = {}

func _ready() -> void:
	_load_effectref()
	templates = effectref.get("templates", {})
	keywords = effectref.get("keywords", {})

	var bus := get_node_or_null("/root/DuelEventBus")
	if bus == null:
		bus = get_node_or_null("/root/EventBus")

	if bus == null:
		push_error("EffectEngine: No se encontró /root/DuelEventBus ni /root/EventBus. Revisa Autoload.")
		return

	var cb := Callable(self, "_on_event")
	if bus.has_signal("event"):
		if not bus.is_connected("event", cb):
			bus.connect("event", cb)
	else:
		push_error("EffectEngine: El bus no tiene la señal 'event'.")

func _norm_owner(v) -> String:
	var s := str(v).strip_edges().to_upper()
	if s == "PLAYER":
		return "Player"
	if s == "OPPONENT":
		return "Opponent"
	return s

func _load_effectref() -> void:
	var path := "res://Scripts/JSON/effectref.json"
	if not FileAccess.file_exists(path):
		push_error("EffectEngine: No se encontró effectref.json en: %s" % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("EffectEngine: No se pudo abrir effectref.json: %s" % path)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("EffectEngine: effectref.json debe ser un objeto JSON.")
		return
	effectref = parsed

func register_card_entered_field(card: Node, controller: String) -> void:
	if card == null:
		return
	if not card.has_method("get_effects"):
		return

	if not field_cards.has(card):
		field_cards.append(card)
	field_controller_by_id[str(card.get_instance_id())] = _norm_owner(controller)

	var effs: Array = card.get_effects()
	for e in effs:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if str(e.get("trigger", "")).to_upper() == "PASSIVE":
			_active_register_aura(card, _norm_owner(controller), e)

func register_card_left_field(card: Node) -> void:
	if card == null:
		return

	if field_cards.has(card):
		field_cards.erase(card)
	field_controller_by_id.erase(str(card.get_instance_id()))

	for i in range(active_auras.size() - 1, -1, -1):
		var a = active_auras[i]
		if a.get("card") == card:
			active_auras.remove_at(i)

func _active_register_aura(card: Node, controller: String, effect_def: Dictionary) -> void:
	active_auras.append({"card": card, "controller": controller, "effect": effect_def})

func _on_event(event_name: String, payload: Dictionary) -> void:
	_resolve_triggered_effects(event_name, payload)
	_resolve_aura_reactions(event_name, payload)
	

func _resolve_triggered_effects(event_name: String, payload: Dictionary) -> void:
	var ev := str(event_name).to_upper()

	var candidates: Array = []
	if _is_self_only_trigger(ev):
		var source = payload.get("source", null)
		if source != null:
			candidates = [source]
	else:
		candidates = field_cards.duplicate()
		var source2 = payload.get("source", null)
		if source2 != null and not candidates.has(source2):
			candidates.append(source2)

	for card in candidates:
		if card == null or not is_instance_valid(card):
			continue
		if not card.has_method("get_effects"):
			continue

		var effs: Array = card.get_effects()
		for e in effs:
			if typeof(e) != TYPE_DICTIONARY:
				continue

			var trig := str(e.get("trigger", "")).to_upper()
			if trig != ev:
				continue

			if not _passes_controller_filter(card, trig, payload):
				continue

			_execute_effect(card, payload, e)

func _resolve_aura_reactions(event_name: String, payload: Dictionary) -> void:
	for a in active_auras:
		var card = a.get("card")
		if card == null:
			continue
		var e: Dictionary = a.get("effect", {})
		var t := str(e.get("template", ""))
		if t == "apply_keyword_to_new_summons_while_source_faceup":
			if event_name in ["ON_PLAY", "ON_SUMMON_BY_EFFECT"]:
				_execute_effect(card, payload, e)

func _execute_effect(source: Node, ctx: Dictionary, effect_def: Dictionary) -> void:
	var template := str(effect_def.get("template", ""))
	var params: Dictionary = effect_def.get("params", {})
	var trigger := str(effect_def.get("trigger", ""))
	var limit := _get_limit_per_instance(params)
	if limit == 1:
		var k := "%s|%s|%s" % [str(source.get_instance_id()), trigger, template]
		if once_per_instance_used.get(k, false):
			return
		once_per_instance_used[k] = true
	match template:
		"destroy_target": _tpl_destroy_target(source, ctx, params)
		"reveal_set_cards": _tpl_reveal_set_cards(source, ctx, params)
		"guardian_star_bonus_multiplier": _tpl_guardian_star_bonus_multiplier(source, ctx, params)
		"change_self_position_when_attacked_end_of_battle": _tpl_change_self_position_when_attacked_end_of_battle(source, ctx, params)
		"apply_keyword_to_new_summons_while_source_faceup": _tpl_apply_keyword_to_new_summons_while_source_faceup(source, ctx, params)
		"summon_token_copy_source_stats_on_send_to_grave_by_effect": _tpl_summon_token_copy_source_stats_on_send_to_grave_by_effect(source, ctx, params)
		"inflict_effect_damage": _tpl_inflict_effect_damage(source, ctx, params)
		"summon_token_from_source_basestats": _tpl_summon_token_from_source_basestats(source, ctx, params)
		"negate_attack_and_destroy": _tpl_negate_attack_and_destroy(source, ctx, params)
		"destroy_by_effect": _tpl_destroy_by_effect(source, ctx, params)
		_:
			push_warning("EffectEngine: Template no implementado: %s" % template)

func _get_limit_per_instance(params: Dictionary) -> int:
	if params.has("limit_per_instance"):
		return int(params.get("limit_per_instance", 0))
	if params.has("limit") and typeof(params.get("limit")) == TYPE_DICTIONARY:
		return int(params["limit"].get("per_instance", 0))
	return 0

func _tpl_destroy_target(source: Node, ctx: Dictionary, params: Dictionary) -> void:
	var selector = params.get("target", null)
	var bm := _get_battle_manager(ctx)
	if bm == null:
		return
	bm.destroy_by_selector(source, selector, ctx)

func _tpl_reveal_set_cards(source: Node, ctx: Dictionary, params: Dictionary) -> void:
	var selector = params.get("target", null)
	var count = params.get("count", null)
	var reveal_to := str(params.get("reveal_to", "OWNER_ONLY"))
	var bm := _get_battle_manager(ctx)
	if bm == null:
		return
	bm.reveal_set_cards_by_selector(source, selector, count, reveal_to, ctx)

func _tpl_guardian_star_bonus_multiplier(source: Node, ctx: Dictionary, params: Dictionary) -> void:
	var mult := int(params.get("multiplier", 1))
	var affects := str(params.get("affects", "ATK_AND_DEF"))
	if source.has_method("set_guardian_star_multiplier"):
		source.set_guardian_star_multiplier(mult, affects)

func _tpl_change_self_position_when_attacked_end_of_battle(source: Node, ctx: Dictionary, params: Dictionary) -> void:
	var new_pos := str(params.get("new_position", "TOGGLE"))
	var bm := _get_battle_manager(ctx)
	if bm == null:
		return
	bm.schedule_change_position_end_of_battle(source, new_pos, ctx)

func _tpl_apply_keyword_to_new_summons_while_source_faceup(source: Node, ctx: Dictionary, params: Dictionary) -> void:
	var played = ctx.get("source", null)
	if played == null:
		return
	var target_side := str(params.get("target_side", "OPPONENT"))
	var kw := str(params.get("keyword", ""))
	if kw == "":
		return
	var bm := _get_battle_manager(ctx)
	if bm == null:
		return
	bm.apply_keyword_to_card_if_matches_side(source, played, target_side, kw, ctx)

func _tpl_summon_token_copy_source_stats_on_send_to_grave_by_effect(source: Node, ctx: Dictionary, params: Dictionary) -> void:
	var bm := _get_battle_manager(ctx)
	if bm == null:
		return
	bm.summon_token_from_source_basestats(source, params, ctx)

func _get_battle_manager(ctx: Dictionary) -> Node:
	if ctx.has("battle_manager") and ctx["battle_manager"] != null:
		return ctx["battle_manager"]
	var root := get_tree().current_scene
	if root != null:
		var bm_scene = root.get_node_or_null("BattleManager")
		if bm_scene != null:
			return bm_scene
	var bm := get_node_or_null("/root/Duel_scene/BattleManager")
	return bm
func _is_self_only_trigger(ev: String) -> bool:
	ev = ev.to_upper()
	return ev in [
		"ON_ACTIVATE",
		"ON_PLAY",
		"ON_SUMMON_BY_EFFECT",
		"ON_FLIP",
		"ON_DESTROY",
		"ON_DESTROY_BATTLE",
		"ON_DESTROY_EFFECT",
		"ON_LEAVE_FIELD",
		"ON_SEND_TO_GRAVE",
		"ON_SEND_TO_GRAVE_BY_EFFECT",
		"ON_SEND_TO_GRAVE_AS_COST",
		"ON_BANISH"
	]

func _controller_of_card(card: Node) -> String:
	if card == null:
		return ""
	return str(field_controller_by_id.get(str(card.get_instance_id()), ""))

func _passes_controller_filter(card: Node, trigger: String, payload: Dictionary) -> bool:
	trigger = trigger.to_upper()
	var ev_controller := _norm_owner(payload.get("controller", ""))
	if ev_controller == "":
		return true

	var card_controller := _controller_of_card(card)
	if card_controller == "":
		return true

	if trigger.begins_with("ON_OPPONENT_"):
		return card_controller != ev_controller

	if trigger == "ON_TRAP_ACTIVATE" or trigger == "ON_SPELL_ACTIVATE" or trigger == "ON_OPPONENT_NORMAL_SUMMON":
		if trigger == "ON_OPPONENT_NORMAL_SUMMON":
			return card_controller != ev_controller
		return card_controller == ev_controller

	return true

func _tpl_summon_token_from_source_basestats(source: Node, ctx: Dictionary, params: Dictionary) -> void:
	var bm := _get_battle_manager(ctx)
	if bm == null:
		return
	if bm.has_method("summon_token_from_source_basestats"):
		bm.summon_token_from_source_basestats(source, params, ctx)

func _tpl_inflict_effect_damage(source: Node, ctx: Dictionary, params: Dictionary) -> void:
	var bm := _get_battle_manager(ctx)
	if bm == null:
		return

	var amount := int(params.get("amount", 0))
	if amount <= 0:
		return

	var target := str(params.get("target", "OPPONENT")).to_upper()
	var only_on_controller_turn := bool(params.get("only_on_controller_turn", false))
	var once_per_turn := bool(params.get("once_per_turn", false))

	var source_controller := ""
	if source != null:
		if "owner_side" in source:
			source_controller = ("Player" if str(source.owner_side).to_upper() == "PLAYER" else "Opponent")
	source_controller = _norm_owner(source_controller)

	var turn_owner := _norm_owner(ctx.get("turn_owner", ctx.get("controller", "")))

	if only_on_controller_turn and source_controller != "" and turn_owner != source_controller:
		return

	if once_per_turn:
		var key := "once_per_turn_inflict_effect_damage"

		var stamp := int(ctx.get("turn_index", -1))

		if stamp < 0 and bm != null and ("turn_index" in bm):
			stamp = int(bm.turn_index)

		if stamp < 0:
			stamp = int(Time.get_ticks_msec() / 1000)

		var prev := -999999
		if source != null and source.has_meta(key):
			prev = int(source.get_meta(key))
		if prev == stamp:
			return
		if source != null:
			source.set_meta(key, stamp)

	# target
	var target_player := source_controller
	if target == "OPPONENT":
		target_player = ("Opponent" if source_controller == "Player" else "Player")
	elif target == "SELF":
		target_player = source_controller

	target_player = _norm_owner(target_player)

	bm._apply_effect_damage_to_side(target_player, amount, {"source": source})
func _tpl_negate_attack_and_destroy(source: Node, ctx: Dictionary, params: Dictionary) -> void:
	var bm := _get_battle_manager(ctx)
	if bm == null:
		return

	var attacker_card = ctx.get("attacker", null)
	if not is_instance_valid(attacker_card):
		return

	# Debe estar en campo
	if source != null and source.has_method("is_on_field"):
		if not source.is_on_field():
			return

	if bool(params.get("only_if_attacker_is_opponent", false)):
		var attacker_controller := _norm_owner(ctx.get("controller", "")) 
		var trap_controller := _norm_owner(_controller_of_card(source))    
		if attacker_controller == "" or trap_controller == "":
			return
		if attacker_controller == trap_controller:
			return

	ctx["prevent_attack"] = true
	ctx["attack_negated"] = true

	var destroy_mode := str(params.get("destroy_mode", "attacker")).to_lower()

	if destroy_mode == "attacker":
		var owner := _norm_owner(bm._owner_of(attacker_card))
		bm.destroy_card(attacker_card, owner, "DESTROY_EFFECT")
	else:
		# ahora mismo solo soporta sakuretsu (luego extender para mirror force, widespread, etc.)
		var owner2 := _norm_owner(bm._owner_of(attacker_card))
		bm.destroy_card(attacker_card, owner2, "DESTROY_EFFECT")

	var trap_owner := _norm_owner(bm._owner_of(source))
	if bm.has_method("_send_spell_to_graveyard"):
		bm._send_spell_to_graveyard(source, trap_owner)
	elif bm.has_method("send_spell_to_graveyard"):
		bm.send_spell_to_graveyard(source, trap_owner)
	else:
		bm.destroy_card(source, trap_owner, "DESTROY_EFFECT")

func _tpl_destroy_by_effect(source: Node, ctx: Dictionary, params: Dictionary) -> void:
	var bm := _get_battle_manager(ctx)
	if bm == null:
		return

	var controller := _norm_owner(ctx.get("controller", ""))
	if controller == "" and source != null and ("owner_side" in source):
		controller = ("Player" if str(source.owner_side).to_upper() == "PLAYER" else "Opponent")
	controller = _norm_owner(controller)

	var target_side := str(params.get("target_side", "OPPONENT")).to_upper()
	var faceup_only := bool(params.get("faceup_only", false))
	var facedown_only := bool(params.get("facedown_only", false))
	var choose := str(params.get("choose", "ALL")).to_upper()
	var count := int(params.get("count", 0))

	var candidates: Array = []

	var sides: Array[String] = []
	if target_side == "SELF":
		sides = ["PLAYER" if controller == "Player" else "OPPONENT"]
	elif target_side == "OPPONENT":
		sides = ["OPPONENT" if controller == "Player" else "PLAYER"]
	elif target_side == "BOTH":
		sides = ["PLAYER", "OPPONENT"]
	else:
		sides = ["OPPONENT" if controller == "Player" else "PLAYER"]

	for side in sides:
		var arr: Array = bm.player_cards_on_battlefield if side == "PLAYER" else bm.opponent_cards_on_battlefield
		for c in arr:
			if not is_instance_valid(c):
				continue
			if bm._card_kind(c) != "MONSTER":
				continue

			var is_facedown := bool(c.get("face_down")) if c.has_method("get") else false
			if faceup_only and is_facedown:
				continue
			if facedown_only and not is_facedown:
				continue

			candidates.append(c)

	if candidates.is_empty():
		return

	var to_destroy: Array = []

	if choose == "ALL" or count == 0:
		to_destroy = candidates
	else:
		match choose:
			"HIGHEST_ATK":
				candidates.sort_custom(func(a,b): return int(a.get("atk")) > int(b.get("atk")))
			"LOWEST_ATK":
				candidates.sort_custom(func(a,b): return int(a.get("atk")) < int(b.get("atk")))
			"HIGHEST_LEVEL":
				candidates.sort_custom(func(a,b): return int(a.get("level")) > int(b.get("level")))
			_:
				candidates.sort_custom(func(a,b): return int(a.get("atk")) > int(b.get("atk")))

		var n = max(1, count)
		for i in range(min(n, candidates.size())):
			to_destroy.append(candidates[i])

	# Destruir por efecto
	for m in to_destroy:
		if not is_instance_valid(m):
			continue
		var owner := _norm_owner(bm._owner_of(m))
		bm.destroy_card(m, owner, "DESTROY_EFFECT")
