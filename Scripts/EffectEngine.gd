extends Node
class_name EffectEngine

var effectref: Dictionary = {}
var templates: Dictionary = {}
var keywords: Dictionary = {}

var active_auras: Array = []
var once_per_instance_used: Dictionary = {}

func _ready() -> void:
	_load_effectref()
	templates = effectref.get("templates", {})
	keywords = effectref.get("keywords", {})
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.connect("event", Callable(self, "_on_event"))

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
	var effs: Array = card.get_effects()
	for e in effs:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if str(e.get("trigger", "")) == "PASSIVE":
			_active_register_aura(card, controller, e)

func register_card_left_field(card: Node) -> void:
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
	var source = payload.get("source", null)
	if source != null and source.has_method("get_effects"):
		var effs: Array = source.get_effects()
		for e in effs:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			if str(e.get("trigger", "")) != event_name:
				continue
			_execute_effect(source, payload, e)

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
	bm.summon_token_from_source_lki(source, params, ctx)

func _get_battle_manager(ctx: Dictionary) -> Node:
	if ctx.has("battle_manager") and ctx["battle_manager"] != null:
		return ctx["battle_manager"]
	var bm := get_node_or_null("/root/Duel_scene/BattleManager")
	return bm
