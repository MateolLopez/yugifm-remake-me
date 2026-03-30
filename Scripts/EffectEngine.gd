extends Node
class_name EffectEngine

var effectref: Dictionary = {}
var templates: Dictionary = {}
var keywords: Dictionary = {}

var active_auras: Array = []
var active_protection_profiles: Array = []
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

	print("REGISTER FIELD CARD:", card.cardname if ("cardname" in card) else str(card), " controller=", controller)

	if not field_cards.has(card):
		field_cards.append(card)
	field_controller_by_id[str(card.get_instance_id())] = _norm_owner(controller)

	var effs: Array = card.get_effects()
	print("  EFFECTS COUNT=", effs.size(), " EFFECTS=", effs)

	for e in effs:
		if typeof(e) != TYPE_DICTIONARY:
			print("  SKIP NON-DICT EFFECT:", e)
			continue

		var trig := str(e.get("trigger", "")).to_upper()
		var tpl := str(e.get("template", ""))
		print("  EFFECT trig=", trig, " tpl=", tpl)

		if trig != "PASSIVE":
			continue

		if tpl == "aura_stat_buff_while_source_faceup":
			print("  REGISTER AURA:", card.cardname if ("cardname" in card) else str(card))
			_active_register_aura(card, _norm_owner(controller), e)
		elif tpl == "grant_protection_profile_while_faceup":
			print("  REGISTER PROTECTION:", card.cardname if ("cardname" in card) else str(card))
			_active_register_protection_profile(card, _norm_owner(controller), e)

	_refresh_aura_stat_buffs()
	print("  ACTIVE_PROTECTION_PROFILES=", active_protection_profiles.size())

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

	for i in range(active_protection_profiles.size() - 1, -1, -1):
		var p = active_protection_profiles[i]
		if p.get("card") == card:
			active_protection_profiles.remove_at(i)

	_refresh_aura_stat_buffs()

func _active_register_aura(card: Node, controller: String, effect_def: Dictionary) -> void:
	for a in active_auras:
		if a.get("card") == card and a.get("effect") == effect_def:
			return
	active_auras.append({"card": card, "controller": controller, "effect": effect_def})

func _on_event(event_name: String, payload: Dictionary) -> void:
	_resolve_triggered_effects(event_name, payload)
	_resolve_aura_reactions(event_name, payload)

	var ev := str(event_name).to_upper()
	if ev in ["ON_PLAY", "ON_FLIP", "ON_LEAVE_FIELD", "ON_DESTROY", "ON_SUMMON_BY_EFFECT", "ON_CHANGE_POSITION"]:
		_refresh_aura_stat_buffs()

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

	var non_trap_candidates: Array = []
	var trap_candidates: Array = []

	for card in candidates:
		if card == null or not is_instance_valid(card):
			continue

		if bool(payload.get("suppress_trap_reactions", false)):
			var ck0 := ""
			if "kind" in card:
				ck0 = str(card.kind).to_upper()
			if ck0 == "TRAP":
				continue

		var ck := ""
		if "kind" in card:
			ck = str(card.kind).to_upper()

		if ck == "TRAP":
			trap_candidates.append(card)
		else:
			non_trap_candidates.append(card)

	for card in non_trap_candidates:
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

	trap_candidates.sort_custom(func(a, b): return _card_set_order(a) < _card_set_order(b))

	for card in trap_candidates:
		if card == null or not is_instance_valid(card):
			continue
		if not card.has_method("get_effects"):
			continue

		var effs: Array = card.get_effects()
		var executed_trap := false

		for e in effs:
			if typeof(e) != TYPE_DICTIONARY:
				continue

			var trig := str(e.get("trigger", "")).to_upper()
			if trig != ev:
				continue

			if not _passes_controller_filter(card, trig, payload):
				continue

			_execute_effect(card, payload, e)
			executed_trap = true
			break

		if executed_trap:
			break

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
		"equip_spell_to_target": _tpl_equip_spell_to_target(source, ctx, params)
		"aura_stat_buff_while_source_faceup": _tpl_aura_stat_buff_while_source_faceup(source, ctx, params)
		"grant_protection_profile_while_faceup": _tpl_grant_protection_profile_while_faceup(source, ctx, params)
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

func _source_class_from_ctx(effect_ctx: Dictionary) -> String:
	if bool(effect_ctx.get("is_battle", false)):
		return "BATTLE"

	var source = effect_ctx.get("source", null)
	var activation_type := str(effect_ctx.get("activation_type", "")).to_upper()

	if activation_type == "SPELL":
		return "SPELL"
	if activation_type == "TRAP":
		return "TRAP"
	if activation_type == "MONSTER_EFFECT":
		return "MONSTER_EFFECT"

	if source != null and is_instance_valid(source):
		var k := ""
		if "kind" in source:
			k = str(source.kind).to_upper()

		if k == "SPELL":
			return "SPELL"
		if k == "TRAP":
			return "TRAP"
		if k == "MONSTER":
			return "MONSTER_EFFECT"

	return ""

func _source_faceup_and_active(card: Node) -> bool:
	if not is_instance_valid(card):
		return false
	if not field_cards.has(card):
		return false
	if "face_down" in card and bool(card.face_down):
		return false
	return true

func is_effect_application_blocked(target: Node, effect_ctx: Dictionary, outcome: String) -> bool:
	if not is_instance_valid(target):
		return false

	var source_class := _source_class_from_ctx(effect_ctx)
	var wanted_outcome := str(outcome).to_upper()

	print("CHECK PROTECTION target=", target.cardname if ("cardname" in target) else str(target), " source_class=", source_class, " outcome=", wanted_outcome, " profiles=", active_protection_profiles.size())

	for p in active_protection_profiles:
		var source_card = p.get("card", null)
		if not is_instance_valid(source_card):
			continue

		
		if not _source_faceup_and_active(source_card):
			continue
		if source_card != target:
			continue

		var effect_def: Dictionary = p.get("effect", {})
		var params: Dictionary = effect_def.get("params", {})
		var rules: Array = params.get("rules", [])

		for rule in rules:
			if typeof(rule) != TYPE_DICTIONARY:
				continue

			var mode := str(rule.get("mode", "")).to_upper()
			var sources: Array = rule.get("sources", [])

			var matches_source := false
			for s in sources:
				if str(s).to_upper() == source_class:
					matches_source = true
					break

			print("    RULE mode=", mode, " sources=", sources, " matches_source=", matches_source)

			if not matches_source:
				continue

			if mode == "UNAFFECTED_BY":
				if wanted_outcome in ["AFFECT", "DESTROY", "TARGET", "BANISH", "SEND_TO_GRAVE", "STAT_MOD", "POSITION_CHANGE"]:
					print("    BLOCKED BY UNAFFECTED_BY")
					return true

			elif mode == "CANNOT_BE_DESTROYED_BY":
				if wanted_outcome == "DESTROY":
					print("    BLOCKED BY CANNOT_BE_DESTROYED_BY")
					return true

	return false

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

	if source != null and source.has_method("is_on_field"):
		if not source.is_on_field():
			return

	if bool(params.get("only_if_attacker_is_opponent", false)):
		var attacker_controller := _norm_owner(ctx.get("controller", ""))
		var source_controller := _norm_owner(_controller_of_card(source))
		if attacker_controller == "" or source_controller == "":
			return
		if attacker_controller == source_controller:
			return

	var effect_ctx := {
		"source": source,
		"controller": _norm_owner(_controller_of_card(source)),
		"activation_type": ("TRAP" if is_instance_valid(source) and ("kind" in source) and str(source.kind).to_upper() == "TRAP" else ("SPELL" if is_instance_valid(source) and ("kind" in source) and str(source.kind).to_upper() == "SPELL" else "MONSTER_EFFECT"))
	}

	var eng = null
	if bm.has_method("_get_effect_engine"):
		eng = bm._get_effect_engine()

	if eng and eng.has_method("is_effect_application_blocked"):
		if eng.is_effect_application_blocked(attacker_card, effect_ctx, "AFFECT"):
			var source_owner0 := _norm_owner(bm._owner_of(source))
			if bm.has_method("_send_spell_to_graveyard"):
				bm._send_spell_to_graveyard(source, source_owner0)
			elif bm.has_method("send_spell_to_graveyard"):
				bm.send_spell_to_graveyard(source, source_owner0)
			else:
				bm.destroy_card(source, source_owner0, "DESTROY_EFFECT", effect_ctx)
			return

	ctx["prevent_attack"] = true
	ctx["attack_negated"] = true

	var destroy_mode := str(params.get("destroy_mode", "attacker")).to_lower()

	if destroy_mode == "attacker":
		var owner := _norm_owner(bm._owner_of(attacker_card))
		bm.destroy_card(attacker_card, owner, "DESTROY_EFFECT", effect_ctx)
	else:
		var owner2 := _norm_owner(bm._owner_of(attacker_card))
		bm.destroy_card(attacker_card, owner2, "DESTROY_EFFECT", effect_ctx)

	var source_owner := _norm_owner(bm._owner_of(source))
	if bm.has_method("_send_spell_to_graveyard"):
		bm._send_spell_to_graveyard(source, source_owner)
	elif bm.has_method("send_spell_to_graveyard"):
		bm.send_spell_to_graveyard(source, source_owner)
	else:
		bm.destroy_card(source, source_owner, "DESTROY_EFFECT", effect_ctx)

func _tpl_destroy_by_effect(source: Node, ctx: Dictionary, params: Dictionary) -> void:
	var bm := _get_battle_manager(ctx)
	if bm == null:
		return

	var controller := _norm_owner(ctx.get("controller", ""))
	if controller == "" and source != null and ("owner_side" in source):
		if str(source.owner_side).to_upper() == "PLAYER":
			controller = "Player"
		else:
			controller = "Opponent"
	controller = _norm_owner(controller)

	var activation_type := "MONSTER_EFFECT"
	if is_instance_valid(source) and ("kind" in source):
		var sk := str(source.kind).to_upper()
		if sk == "SPELL":
			activation_type = "SPELL"
		elif sk == "TRAP":
			activation_type = "TRAP"

	var target_side := str(params.get("target_side", "OPPONENT")).to_upper()
	var faceup_only := bool(params.get("faceup_only", false))
	var facedown_only := bool(params.get("facedown_only", false))
	var choose := str(params.get("choose", "ALL")).to_upper()
	var count := int(params.get("count", 0))

	var zones: Array = params.get("zones", ["MONSTER"])
	var kinds: Array = params.get("kinds", ["MONSTER"])

	var candidates: Array = []
	var sides: Array[String] = []

	if target_side == "SELF":
		if controller == "Player":
			sides = ["PLAYER"]
		else:
			sides = ["OPPONENT"]
	elif target_side == "OPPONENT":
		if controller == "Player":
			sides = ["OPPONENT"]
		else:
			sides = ["PLAYER"]
	elif target_side == "BOTH":
		sides = ["PLAYER", "OPPONENT"]
	else:
		if controller == "Player":
			sides = ["OPPONENT"]
		else:
			sides = ["PLAYER"]

	for side in sides:
		if zones.has("MONSTER"):
			var mons: Array = []
			if side == "PLAYER":
				mons = bm.player_cards_on_battlefield
			else:
				mons = bm.opponent_cards_on_battlefield

			for c in mons:
				if not is_instance_valid(c):
					continue
				if not kinds.has("MONSTER"):
					continue

				var is_facedown := false
				if "face_down" in c:
					is_facedown = bool(c.face_down)

				if faceup_only and is_facedown:
					continue
				if facedown_only and not is_facedown:
					continue

				candidates.append(c)

		if zones.has("SPELL_TRAP"):
			var slots_root = null
			if side == "PLAYER":
				slots_root = bm.get_node_or_null("../CardSlots")
			else:
				slots_root = bm.get_node_or_null("../CardSlotsRival")

			if is_instance_valid(slots_root):
				for s in slots_root.get_children():
					if not is_instance_valid(s):
						continue

					var slot_type := str(s.get("card_slot_type"))
					if slot_type != "SpellTrap" and slot_type != "Spell" and slot_type != "Trap":
						continue

					if not bool(s.get("card_in_slot")):
						continue

					var c = null
					if "card_ref" in s:
						c = s.card_ref
					if not is_instance_valid(c):
						continue

					var ck := ""
					if "kind" in c:
						ck = str(c.kind).to_upper()

					if not kinds.has(ck):
						continue

					var is_facedown2 := false
					if "face_down" in c:
						is_facedown2 = bool(c.face_down)

					if faceup_only and is_facedown2:
						continue
					if facedown_only and not is_facedown2:
						continue

					candidates.append(c)

		if zones.has("FIELD"):
			var fs = bm.active_field_spell
			if is_instance_valid(fs):
				var fs_controller := _norm_owner(bm.active_field_spell_controller)
				var belongs := false

				if side == "PLAYER" and fs_controller == "Player":
					belongs = true
				elif side == "OPPONENT" and fs_controller == "Opponent":
					belongs = true

				if belongs:
					var fs_kind := ""
					if "kind" in fs:
						fs_kind = str(fs.kind).to_upper()

					if kinds.has(fs_kind):
						var fs_facedown := false
						if "face_down" in fs:
							fs_facedown = bool(fs.face_down)

						if faceup_only and fs_facedown:
							pass
						elif facedown_only and not fs_facedown:
							pass
						else:
							candidates.append(fs)

	if candidates.is_empty():
		return

	var to_destroy: Array = []

	if choose == "ALL" or count == 0:
		to_destroy = candidates
	elif choose == "RANDOM":
		candidates.shuffle()
		var n1 = max(1, count)
		for i in range(min(n1, candidates.size())):
			to_destroy.append(candidates[i])
	else:
		match choose:
			"HIGHEST_ATK":
				candidates.sort_custom(func(a, b):
					var av := 0
					var bv := 0
					if "atk" in a:
						av = int(a.atk)
					if "atk" in b:
						bv = int(b.atk)
					return av > bv
				)
			"LOWEST_ATK":
				candidates.sort_custom(func(a, b):
					var av := 0
					var bv := 0
					if "atk" in a:
						av = int(a.atk)
					if "atk" in b:
						bv = int(b.atk)
					return av < bv
				)
			"HIGHEST_LEVEL":
				candidates.sort_custom(func(a, b):
					var av := 0
					var bv := 0
					if "level" in a:
						av = int(a.level)
					if "level" in b:
						bv = int(b.level)
					return av > bv
				)
			_:
				candidates.shuffle()

		var n2 = max(1, count)
		for i in range(min(n2, candidates.size())):
			to_destroy.append(candidates[i])

	for c in to_destroy:
		if not is_instance_valid(c):
			continue

		var effect_ctx := {
			"source": source,
			"controller": controller,
			"activation_type": activation_type
		}

		if c == bm.active_field_spell:
			var eng = bm._get_effect_engine()
			if eng and eng.has_method("is_effect_application_blocked"):
				if eng.is_effect_application_blocked(c, effect_ctx, "DESTROY"):
					continue

			c.set_meta("ethereal_field_spell", false)
			bm._unregister_card_with_effect_engine(c)
			var fs_owner := _norm_owner(bm.active_field_spell_controller)
			bm.active_field_spell = null
			bm.active_field_spell_controller = ""
			bm._update_field_spell_name_ui()
			bm._send_spell_to_graveyard(c, fs_owner)
			continue

		var ck2 := ""
		if "kind" in c:
			ck2 = str(c.kind).to_upper()

		if ck2 == "MONSTER":
			var owner := _norm_owner(bm._owner_of(c))
			bm.destroy_card(c, owner, "DESTROY_EFFECT", effect_ctx)
		elif ck2 == "SPELL" or ck2 == "TRAP":
			var eng2 = bm._get_effect_engine()
			if eng2 and eng2.has_method("is_effect_application_blocked"):
				if eng2.is_effect_application_blocked(c, effect_ctx, "DESTROY"):
					continue

			var owner2 := _norm_owner(bm._owner_of(c))
			bm._send_spell_to_graveyard(c, owner2)

func _tpl_equip_spell_to_target(source: Node, ctx: Dictionary, _params: Dictionary) -> void:
	var bm := _get_battle_manager(ctx)
	if bm == null:
		return

	var controller := _norm_owner(ctx.get("controller", ""))
	if controller == "":
		return

	if bm.has_method("start_equip_from_hand"):
		bm.start_equip_from_hand(source, controller)

func _tpl_aura_stat_buff_while_source_faceup(source: Node, ctx: Dictionary, params: Dictionary) -> void:
	_refresh_aura_stat_buffs()

func _refresh_aura_stat_buffs() -> void:
	var monsters: Array = []
	for c in field_cards:
		if not is_instance_valid(c):
			continue
		var k := str(c.kind).to_upper() if ("kind" in c) else ""
		if k != "MONSTER":
			continue
		if not c.has_method("is_on_field") or not c.is_on_field():
			continue
		monsters.append(c)

	var acc: Dictionary = {}  # key: target instance_id => { "atk":int, "def":int, "mods":Array }

	for a in active_auras:
		var src = a.get("card", null)
		if not is_instance_valid(src):
			continue
		if not src.has_method("is_on_field") or not src.is_on_field():
			continue

		var src_facedown := bool(src.face_down) if ("face_down" in src) else false
		if src_facedown:
			continue

		var effect_def: Dictionary = a.get("effect", {})
		if str(effect_def.get("template","")) != "aura_stat_buff_while_source_faceup":
			continue

		var params: Dictionary = effect_def.get("params", {})

		var target_side := str(params.get("target_side","SELF")).to_upper() # SELF / OPPONENT / BOTH
		var filter_attribute := str(params.get("filter_attribute","")).to_upper()
		var atk_delta := int(params.get("atk_delta", 0))
		var def_delta := int(params.get("def_delta", 0))

		var src_controller := _norm_owner(_controller_of_card(src))
		if src_controller == "":
			continue

		for t in monsters:
			if not is_instance_valid(t):
				continue

			var t_controller := _norm_owner(_controller_of_card(t))
			if t_controller == "":
				continue

			var ok_side := true
			if target_side == "SELF":
				ok_side = (t_controller == src_controller)
			elif target_side == "OPPONENT":
				ok_side = (t_controller != src_controller)
			elif target_side == "BOTH":
				ok_side = true
			if not ok_side:
				continue

			if filter_attribute != "":
				var a2 := str(t.attribute).to_upper() if ("attribute" in t) else ""
				if a2 != filter_attribute:
					continue

			var tid := str(t.get_instance_id())
			if not acc.has(tid):
				acc[tid] = {"atk": 0, "def": 0, "mods": []}

			acc[tid]["atk"] = int(acc[tid]["atk"]) + atk_delta
			acc[tid]["def"] = int(acc[tid]["def"]) + def_delta
			acc[tid]["mods"].append({
				"src_id": str(src.get_instance_id()),
				"atk": atk_delta,
				"def": def_delta
			})

	for t in monsters:
		if not is_instance_valid(t):
			continue
		var tid := str(t.get_instance_id())
		var mods: Array = []
		if acc.has(tid):
			mods = acc[tid]["mods"]

		if t.has_method("set_effect_modifiers"):
			t.set_effect_modifiers(mods)
		elif t.has_method("clear_effect_modifiers"):
			t.clear_effect_modifiers()

func _active_register_protection_profile(card: Node, controller: String, effect_def: Dictionary) -> void:
	for p in active_protection_profiles:
		if p.get("card") == card and p.get("effect") == effect_def:
			return
	active_protection_profiles.append({
		"card": card,
		"controller": controller,
		"effect": effect_def
	})
	print("REGISTER PROTECTION:", card.cardname, " profiles=", active_protection_profiles.size())

func _aura_instance_id(source: Node, effect_def: Dictionary) -> String:
	var params: Dictionary = effect_def.get("params", {})
	var aura_id := str(params.get("aura_id", ""))
	if aura_id == "":
		var sig := "%s|%s|%s|%s|%s|%s" % [
			str(params.get("target_side", "")),
			str(params.get("filter_attribute", "")),
			str(params.get("filter_race", "")),
			str(params.get("filter_tag", "")),
			str(params.get("atk_delta", 0)),
			str(params.get("def_delta", 0))
		]
		aura_id = sig

	return "aura|%s|%s" % [str(source.get_instance_id()), aura_id]

func _card_set_order(card: Node) -> int:
	if not is_instance_valid(card):
		return 999999999
	if card.has_meta("set_order"):
		return int(card.get_meta("set_order"))
	return 999999999

func _apply_aura_as_virtual_equip(target: Node, instance_id: String, source: Node, atk_delta: int, def_delta: int) -> void:
	var equips: Array = target.get("equipped_spells") if ("equipped_spells" in target) else []
	for e in equips:
		if typeof(e) == TYPE_DICTIONARY and str(e.get("instance_id", "")) == instance_id:
			return

	var equip_instance := {
		"instance_id": instance_id,
		"spell_id": "",
		"spell_name": "AURA",
		"mod": {"atk": atk_delta, "def": def_delta},
		"set": {},
		"grant_keywords": [],
		"meta": {
			"is_aura": true,
			"source_id": str(source.get_instance_id())
		}
	}

	target.add_equip_instance(equip_instance)

func _tpl_grant_protection_profile_while_faceup(_source: Node, _ctx: Dictionary, _params: Dictionary) -> void:
	return
