extends Node
class_name DuelFieldSpellService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null
var card_db_service: DuelCardDbService = null
var card_play_service: DuelCardPlayService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service
	card_db_service = bm.card_db_service
	card_play_service = bm.card_play_service

func activate_field_spell_from_db(
	field_id: String = "",
	field_name: String = "",
	controller: String = "Player",
	ctx: Dictionary = {}
) -> bool:
	controller = card_runtime_service._norm_owner(controller)

	field_id = str(field_id).strip_edges()
	field_name = str(field_name).strip_edges()

	var card_def := {}

	if field_id != "":
		card_def = card_db_service._get_db_card_by_id(field_id)

	if card_def.is_empty() and field_name != "":
		card_def = card_db_service._get_db_field_spell_by_name(field_name)

	if card_def.is_empty():
		push_warning("BattleManager: no se encontró Field Spell en DB. id=%s name=%s" % [field_id, field_name])
		return false

	if str(card_def.get("kind", "")).to_upper() != "SPELL":
		push_warning("BattleManager: la carta encontrada no es SPELL: %s" % str(card_def.get("cardname", "")))
		return false

	if str(card_def.get("race", "")).to_upper() != "FIELD":
		push_warning("BattleManager: la carta encontrada no es FIELD: %s" % str(card_def.get("cardname", "")))
		return false

	var field_card := card_db_service._spawn_card_from_db_entry(card_def, controller)

	if not is_instance_valid(field_card):
		return false

	var activation_ctx := ctx.duplicate(true)
	activation_ctx["activated_from_db"] = true
	activation_ctx["activated_by_effect"] = true

	_activate_field_spell(field_card, controller, activation_ctx)

	return true

func _set_field_spell_name_ui(value: String) -> void:
	if not is_instance_valid(bm._ui_field_spell_name):
		bm._ui_field_spell_name = get_node_or_null("../../FieldSpellName") as RichTextLabel
		if not is_instance_valid(bm._ui_field_spell_name):
			var root := get_tree().current_scene
			if is_instance_valid(root):
				bm._ui_field_spell_name = root.get_node_or_null("FieldSpellName") as RichTextLabel
		if not is_instance_valid(bm._ui_field_spell_name):
			return

	bm._ui_field_spell_name.text = value

func _update_field_spell_name_ui() -> void:
	if not is_instance_valid(bm._ui_field_spell_name):
		return

	if is_instance_valid(bm.active_field_spell) and ("cardname" in bm.active_field_spell):
		bm._ui_field_spell_name.text = str(bm.active_field_spell.cardname)
	else:
		bm._ui_field_spell_name.text = "--"

func _activate_field_spell(spell_card: Node, controller: String, ctx: Dictionary = {}) -> void:
	if not is_instance_valid(spell_card):
		return

	controller = card_runtime_service._norm_owner(controller)

	var prev_field = bm.active_field_spell
	var prev_controller = card_runtime_service._norm_owner(bm.active_field_spell_controller)

	var slot = zone_service._card_slot(spell_card)
	if is_instance_valid(slot):
		slot.card_in_slot = false
		if "card_ref" in slot:
			slot.set_meta("card_ref", null)
		var slot_shape = slot.get_node_or_null("Area2D/CollisionShape2D")
		if slot_shape:
			slot_shape.disabled = false
		zone_service._clear_card_slot(spell_card)

	var ph := get_node_or_null("../../PlayerHand")
	var oh := get_node_or_null("../../OpponentHand")
	if ph and ph.has_method("has_card") and ph.has_card(spell_card):
		ph.remove_card_from_hand(spell_card)
	elif oh and oh.has_method("has_card") and oh.has_card(spell_card):
		oh.remove_card_from_hand(spell_card)

	if spell_card in bm.player_cards_on_battlefield:
		bm.player_cards_on_battlefield.erase(spell_card)
	if spell_card in bm.opponent_cards_on_battlefield:
		bm.opponent_cards_on_battlefield.erase(spell_card)

	card_runtime_service._set_card_face_down(spell_card, false)
	if spell_card.has_method("set_show_back_only"):
		spell_card.set_show_back_only(false)

	if is_instance_valid(prev_field):
		prev_field.set_meta("ethereal_field_spell", false)
		event_service._unregister_card_with_effect_engine(prev_field)
		if prev_controller == "":
			prev_controller = "Player"
		card_play_service._send_spell_to_graveyard(prev_field, prev_controller)

	bm.active_field_spell = spell_card
	bm.active_field_spell_controller = controller

	spell_card.set_meta("ethereal_field_spell", true)
	if spell_card.has_method("move_to_zone"):
		spell_card.move_to_zone("FIELD")
	else:
		if "current_zone" in spell_card:
			spell_card.current_zone = "FIELD"

	var area := spell_card.get_node_or_null("Area2D") as Area2D
	if area:
		area.monitoring = false
		area.input_pickable = false

	if spell_card is Node2D:
		(spell_card as Node2D).global_position = Vector2(-100000, -100000)

	_update_field_spell_name_ui()

	event_service._register_card_with_effect_engine(spell_card, controller)

	var payload := {
		"battle_manager": bm,
		"source": spell_card,
		"controller": controller,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
		"turn_index": bm.turn_index
	}
	if ctx.has("replaced_field_spell"):
		payload["replaced_field_spell"] = ctx["replaced_field_spell"]

	event_service._emit_duel_event("ON_FIELD_SPELL_ACTIVATE", payload)
	event_service._emit_duel_event("ON_ACTIVATE", payload)

func _is_field_spell(card: Node) -> bool:
	if not is_instance_valid(card):
		return false
	if str(card_runtime_service._card_kind(card)).to_upper() != "SPELL":
		return false
	return str(card.race).to_upper() == "FIELD"
