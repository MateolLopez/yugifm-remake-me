extends Node
class_name DuelAnimationService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service

func _begin_duel_animation_lock() -> void:
	bm.duel_animation_lock_count += 1
	_set_duel_input_blocked(true)

func _end_duel_animation_lock() -> void:
	bm.duel_animation_lock_count = max(0, bm.duel_animation_lock_count - 1)

	if bm.duel_animation_lock_count == 0:
		_set_duel_input_blocked(false)

func is_duel_animating() -> bool:
	return bm.duel_animation_lock_count > 0

func _set_duel_input_blocked(blocked: bool) -> void:
	var blocker := get_node_or_null("../../UI/InputBlocker") as Control
	if blocker:
		blocker.visible = blocked
		blocker.mouse_filter = Control.MOUSE_FILTER_STOP if blocked else Control.MOUSE_FILTER_IGNORE

	var im := get_node_or_null("../../InputManager")
	if im != null:
		if "is_animating" in im:
			im.is_animating = blocked
		if not blocked and "inputs_disabled" in im:
			im.inputs_disabled = false

func wait_until_duel_idle() -> void:
	while is_duel_animating():
		await get_tree().process_frame

func _play_monster_reborn_fx_on_card(card: Node2D) -> void:
	if not is_instance_valid(card):
		return

	if bm.monster_reborn_fx_scene == null:
		return

	_begin_duel_animation_lock()

	_play_duel_sfx("summon_by_effect")

	var fx = bm.monster_reborn_fx_scene.instantiate()
	if not is_instance_valid(fx):
		_end_duel_animation_lock()
		return

	var parent_node := get_tree().current_scene
	if parent_node == null:
		parent_node = card.get_parent()

	parent_node.add_child(fx)

	if fx.has_method("setup_from_card"):
		fx.setup_from_card(card)
	else:
		if fx is Node2D:
			var fx2d := fx as Node2D
			fx2d.global_position = _get_card_visual_center_global(card)
			fx2d.global_rotation = card.global_rotation
			fx2d.scale = card.scale
			fx2d.z_index = card.z_index + 120

	if fx.has_method("play"):
		fx.play()

	if fx.has_signal("finished"):
		await fx.finished
	else:
		await get_tree().create_timer(2.0).timeout

	if is_instance_valid(fx):
		fx.queue_free()

	_end_duel_animation_lock()

func _play_card_destroy_animation_and_free(card: Node2D) -> void:
	if not is_instance_valid(card):
		return

	_begin_duel_animation_lock()

	var original_pos := card.global_position
	var original_z := card.z_index

	card.z_index = original_z + 100

	var cshape = card.get_node_or_null("Area2D/CollisionShape2D")
	if cshape:
		cshape.disabled = true

	await _play_pre_destroy_impact_fx_if_any(card)

	_play_duel_sfx("destroy_vibration")

	var offsets := [
		-3.0,
		6.0,
		-6.0,
		6.0,
		-5.0,
		5.0,
		-4.0,
		4.0,
		-3.0,
		3.0,
		0.0
	]

	var step_duration := 0.8 / float(offsets.size())

	for x in offsets:
		if not is_instance_valid(card):
			_end_duel_animation_lock()
			return

		var tw := get_tree().create_tween()
		tw.tween_property(
			card,
			"global_position",
			original_pos + Vector2(x, 0),
			step_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

		await tw.finished

	if is_instance_valid(card):
		card.global_position = original_pos

	await _play_destroy_explosion_on_card(card)

	if is_instance_valid(card):
		card.visible = false
		card.queue_free()

	_end_duel_animation_lock()

func _play_destroy_explosion_on_card(card: Node2D) -> void:
	if not is_instance_valid(card):
		return

	if bm.destroy_explosion_scene == null:
		return

	_play_duel_sfx("destroy_explosion")

	var explosion = bm.destroy_explosion_scene.instantiate()
	if not is_instance_valid(explosion):
		return

	var parent_node := card.get_parent()
	if parent_node == null:
		parent_node = get_tree().current_scene

	parent_node.add_child(explosion)

	if explosion is Node2D:
		var exp2d := explosion as Node2D
		exp2d.global_position = _get_card_visual_center_global(card)
		exp2d.global_rotation = card.global_rotation
		exp2d.scale = card.scale
		exp2d.z_index = card.z_index + 10

	if explosion.has_method("play"):
		explosion.play()

	if explosion.has_signal("finished"):
		await explosion.finished
	else:
		await get_tree().create_timer(0.25).timeout

	if is_instance_valid(explosion):
		explosion.queue_free()

func _get_card_visual_center_global(card: Node2D) -> Vector2:
	if not is_instance_valid(card):
		return Vector2.ZERO

	var anchor := card.get_node_or_null("AnchorCenter") as Node2D
	if is_instance_valid(anchor):
		return anchor.global_position

	return card.global_position

func _anchored_position_for_slot_with_scale(card: Node2D, slot: Node2D, target_scale: Vector2) -> Vector2:
	if not is_instance_valid(card) or not is_instance_valid(slot):
		return Vector2.ZERO

	var slot_anchor := slot.get_node_or_null("Anchor") as Node2D
	var target_node := slot_anchor if is_instance_valid(slot_anchor) else slot
	var target_global := target_node.global_position

	var card_anchor := card.get_node_or_null("AnchorCenter") as Node2D
	if not is_instance_valid(card_anchor):
		return target_global

	var old_scale := card.scale
	var old_pos := card.global_position

	card.scale = target_scale
	var anchor_delta := card_anchor.global_position - card.global_position

	card.scale = old_scale
	card.global_position = old_pos

	return target_global - anchor_delta

func _anchored_slot_position(card: Node2D) -> Vector2:
	if card == null:
		return Vector2.ZERO

	var slot = card.get("current_slot")
	if slot == null or not is_instance_valid(slot):
		return (card as Node2D).global_position

	var slot2d := slot as Node2D
	if slot2d == null:
		return (card as Node2D).global_position

	var card_anchor := card.get_node_or_null("AnchorCenter") as Node2D
	var slot_anchor := slot2d.get_node_or_null("Anchor") as Node2D
	var target := slot_anchor if slot_anchor else slot2d

	if card_anchor == null:
		return target.global_position

	var delta := card_anchor.to_global(Vector2.ZERO) - card.to_global(Vector2.ZERO)
	return target.global_position - delta

func _anchored_target_position(attacker: Node2D, defender: Node2D, y_offset := 0.0) -> Vector2:
	var def_anchor := defender.get_node_or_null("AnchorCenter") as Node2D
	var def_center := (def_anchor if def_anchor else defender) as Node2D
	var atk_anchor := attacker.get_node_or_null("AnchorCenter") as Node2D
	var atk_delta := atk_anchor.to_global(Vector2.ZERO) - attacker.to_global(Vector2.ZERO)
	return def_center.global_position - atk_delta + Vector2(0, y_offset)

func _animate_card_to_slot_visual(card: Node2D, slot: Node2D, duration: float = 0.25) -> void:
	if not is_instance_valid(card) or not is_instance_valid(slot):
		return

	var cm := get_node_or_null("../../CardManager")
	var target_scale := card.scale

	if cm != null and "FIELD_SCALE" in cm:
		target_scale = Vector2(cm.FIELD_SCALE, cm.FIELD_SCALE)

	var target_pos := _anchored_position_for_slot_with_scale(card, slot, target_scale)

	var original_z := card.z_index
	card.z_index = 100

	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "global_position", target_pos, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(card, "scale", target_scale, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await tw.finished

	if is_instance_valid(card):
		card.global_position = target_pos
		card.scale = target_scale
		card.z_index = original_z

func _get_duel_fx_manager():
	var fxm = get_node_or_null("../../DuelFxManager")
	if fxm == null:
		fxm = get_node_or_null("/root/DuelFxManager")
	return fxm


func _play_duel_sfx(key: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	var fxm = _get_duel_fx_manager()
	if fxm != null and fxm.has_method("play_sfx_key"):
		fxm.play_sfx_key(key, volume_db, pitch_scale)


func _play_duel_vfx_on_card(key: String, card: Node2D) -> void:
	var fxm = _get_duel_fx_manager()
	if fxm != null and fxm.has_method("play_vfx_key_on_card"):
		await fxm.play_vfx_key_on_card(key, card)


func _activation_sfx_key_for_card(card: Node) -> String:
	var kind := card_runtime_service._card_kind(card)

	match kind:
		"SPELL":
			return "spell_activate"
		"TRAP":
			return "trap_reactive"
		"MONSTER":
			return "monster_effect_activate"
		_:
			return "spell_activate"


func _play_card_activation_sfx(card: Node, ctx: Dictionary = {}) -> void:
	var key := ""

	var presentation = ctx.get("presentation", {})
	if typeof(presentation) == TYPE_DICTIONARY:
		key = str(presentation.get("activation_sfx_key", ""))

	if key == "":
		key = _activation_sfx_key_for_card(card)

	_play_duel_sfx(key)

func _play_pre_destroy_impact_fx_if_any(card: Node2D) -> void:
	if not is_instance_valid(card):
		return

	var sfx_key := ""
	var vfx_key := ""

	if card.has_meta("pre_destroy_sfx_key"):
		sfx_key = str(card.get_meta("pre_destroy_sfx_key"))
		card.remove_meta("pre_destroy_sfx_key")

	if card.has_meta("pre_destroy_vfx_key"):
		vfx_key = str(card.get_meta("pre_destroy_vfx_key"))
		card.remove_meta("pre_destroy_vfx_key")

	if sfx_key != "":
		_play_duel_sfx(sfx_key)

	if vfx_key != "":
		await _play_duel_vfx_on_card(vfx_key, card)
