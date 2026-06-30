extends Node
class_name DuelEventService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var card_activation_service: DuelCardActivationService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	card_activation_service = bm.card_activation_service

func _get_duel_bus():
	var bus = get_node_or_null("/root/DuelEventBus")
	if bus == null:
		bus = get_node_or_null("/root/EventBus")
	return bus

func _emit_duel_event(event_name: String, payload: Dictionary = {}) -> void:
	var bus = _get_duel_bus()
	if bus and bus.has_method("emit_event"):
		bus.emit_event(event_name, payload)

func _get_effect_engine():
	var eng = get_node_or_null("/root/DuelEffectEngine")
	if eng == null:
		eng = get_node_or_null("/root/EffectEngine")
	return eng

func _register_card_with_effect_engine(card, controller: String) -> void:
	var eng = _get_effect_engine()
	if eng and eng.has_method("register_card_entered_field"):
		eng.register_card_entered_field(card, controller)

func _unregister_card_with_effect_engine(card) -> void:
	var eng = _get_effect_engine()
	if eng and eng.has_method("register_card_left_field"):
		eng.register_card_left_field(card)

func _refresh_effect_engine_continuous_buffs() -> void:
	var eng = _get_effect_engine()
	if eng and eng.has_method("_refresh_aura_stat_buffs"):
		eng._refresh_aura_stat_buffs()

func _emit_activation_declaration_events(card, controller: String, ctx: Dictionary) -> void:
	var t = card_activation_service._activation_type_for_card(card)
	match t:
		"TRAP":
			_emit_duel_event("ON_TRAP_ACTIVATE", ctx)
			_emit_duel_event("ON_OPPONENT_TRAP_ACTIVATE", ctx)
		"SPELL":
			_emit_duel_event("ON_SPELL_ACTIVATE", ctx)
			_emit_duel_event("ON_OPPONENT_SPELL_ACTIVATE", ctx)
		_:
			_emit_duel_event("ON_MONSTER_EFFECT_ACTIVATE", ctx)
			_emit_duel_event("ON_OPPONENT_MONSTER_EFFECT_ACTIVATE", ctx)

func trigger_on_play_effects(card, who: String) -> void:
	if not is_instance_valid(card):
		return
	_trigger_on_play_effects(card, who)

func _trigger_on_play_effects(card, card_owner: String) -> void:
	if not is_instance_valid(card):
		return
	if card_runtime_service._is_card_face_down(card):
		return

	_register_card_with_effect_engine(card, card_owner)
	_emit_duel_event("ON_PLAY", {
		"battle_manager": bm,
		"source": card,
		"controller": card_owner,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player")
	})

func _trigger_on_attack(_card, _who: String, _ctx: Dictionary) -> void:
	return

func _has_on_attack(card) -> bool:
	if card == null: return false
	if card.effects == null: return false
	var eff_list = card.effects
	if typeof(eff_list) != TYPE_ARRAY: return false
	if eff_list.size() == 0: return false
	
	for effect in eff_list:
		if effect is Dictionary and effect.get("type") == "on_attack":
			return true
	
	return false

func _trigger_on_attack_effects(_card, _who: String, _ctx: Dictionary) -> void:
	return
