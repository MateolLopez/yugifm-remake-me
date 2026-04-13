extends Node
class_name EventBus

signal event(event_name: String, payload: Dictionary)

signal turn_start(payload: Dictionary)
signal turn_end(payload: Dictionary)

signal card_played(payload: Dictionary)
signal card_summoned_by_effect(payload: Dictionary)
signal card_flipped(payload: Dictionary)

signal spell_activated(payload: Dictionary)
signal opponent_spell_activated(payload: Dictionary)
signal trap_activated(payload: Dictionary)
signal opponent_trap_activated(payload: Dictionary)

signal field_spell_activated(payload: Dictionary)
signal opponent_field_spell_activated(payload: Dictionary)

signal activation_declared(payload: Dictionary)
signal activation_resolved(payload: Dictionary)

signal attack_declared(payload: Dictionary)
signal battle_damage_inflicted(payload: Dictionary)
signal effect_damage_inflicted(payload: Dictionary)

signal monster_destroyed_by_battle(payload: Dictionary)

signal lp_recovered(payload: Dictionary)

signal card_destroyed(payload: Dictionary)
signal card_destroyed_by_battle(payload: Dictionary)
signal card_destroyed_by_effect(payload: Dictionary)

signal card_sent_to_grave(payload: Dictionary)
signal card_sent_to_grave_by_effect(payload: Dictionary)
signal card_sent_to_grave_as_cost(payload: Dictionary)

signal card_banished(payload: Dictionary)
signal card_left_field(payload: Dictionary)

signal level_loss(payload: Dictionary)

func emit_event(event_name: String, payload: Dictionary = {}) -> void:
	emit_signal("event", event_name, payload)
	#print("[BUS] ", event_name)

	match event_name:
		"TURN_START":
			emit_signal("turn_start", payload)
		"TURN_END":
			emit_signal("turn_end", payload)

		"ON_PLAY":
			emit_signal("card_played", payload)
		"ON_SUMMON_BY_EFFECT":
			emit_signal("card_summoned_by_effect", payload)
		"ON_FLIP":
			emit_signal("card_flipped", payload)

		"ON_SPELL_ACTIVATE":
			emit_signal("spell_activated", payload)
		"ON_OPPONENT_SPELL_ACTIVATE":
			emit_signal("opponent_spell_activated", payload)
		"ON_TRAP_ACTIVATE":
			emit_signal("trap_activated", payload)
		"ON_OPPONENT_TRAP_ACTIVATE":
			emit_signal("opponent_trap_activated", payload)
		
		"ON_FIELD_SPELL_ACTIVATE":
			emit_signal("field_spell_activated", payload)
		"ON_OPPONENT_FIELD_SPELL_ACTIVATE":
			emit_signal("opponent_field_spell_activated", payload)

		"ON_ACTIVATE":
			emit_signal("activation_declared", payload)
		"ON_ACTIVATION_RESOLVED":
			emit_signal("activation_resolved", payload)

		"ON_ATTACK_DECLARATION":
			emit_signal("attack_declared", payload)
		"ON_INFLICT_BATTLE_DAMAGE":
			emit_signal("battle_damage_inflicted", payload)
		"ON_INFLICT_EFFECT_DAMAGE":
			emit_signal("effect_damage_inflicted", payload)

		"ON_DESTROY_MONSTER_BY_BATTLE":
			emit_signal("monster_destroyed_by_battle", payload)

		"ON_RECOVER_LP":
			emit_signal("lp_recovered", payload)

		"ON_DESTROY":
			emit_signal("card_destroyed", payload)
		"ON_DESTROY_BATTLE":
			emit_signal("card_destroyed_by_battle", payload)
		"ON_DESTROY_EFFECT":
			emit_signal("card_destroyed_by_effect", payload)

		"ON_SEND_TO_GRAVE":
			emit_signal("card_sent_to_grave", payload)
		"ON_SEND_TO_GRAVE_BY_EFFECT":
			emit_signal("card_sent_to_grave_by_effect", payload)
		"ON_SEND_TO_GRAVE_AS_COST":
			emit_signal("card_sent_to_grave_as_cost", payload)

		"ON_BANISH":
			emit_signal("card_banished", payload)
		"ON_LEAVE_FIELD":
			emit_signal("card_left_field", payload)

		"ON_LEVEL_LOSS":
			emit_signal("level_loss", payload)

		_:
			pass
