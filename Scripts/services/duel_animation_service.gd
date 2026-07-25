extends Node
class_name DuelAnimationService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null

@export_group("Battle Transition")
@export var post_battle_effect_delay: float = 1.0

var _effect_fx_queue_paused: bool = false
var _battle_presentation_active: bool = false

var _effect_fx_queue: Array[Dictionary] = []
var _effect_fx_queue_running: bool = false

const EFFECT_RETAIN_COUNT_META := \
	"_effect_resolution_retain_count"

const EFFECT_PENDING_FREE_META := \
	"_effect_resolution_pending_free"

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

func is_battle_presentation_active() -> bool:
	return _battle_presentation_active

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

	var scene := _get_duel_vfx_scene("monster_reborn_summon")

	if scene == null:
		push_warning(
			"DuelAnimationService: no se encontró VFX 'monster_reborn_summon'."
		)
		return

	_begin_duel_animation_lock()

	_play_duel_sfx("summon_by_effect")

	var fx = scene.instantiate()
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
		request_free_after_effect_resolutions(card)

	_end_duel_animation_lock()

func _play_destroy_explosion_on_card(card: Node2D) -> void:
	if not is_instance_valid(card):
		return

	var scene := _get_duel_vfx_scene("destroy_explosion")

	if scene == null:
		push_warning("DuelAnimationService: no se encontró VFX 'destroy_explosion'.")
		return

	_play_duel_sfx("destroy_explosion")

	var explosion = scene.instantiate()
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


func _get_duel_vfx_scene(key: String) -> PackedScene:
	var fxm = _get_duel_fx_manager()

	if fxm != null and fxm.has_method("get_vfx_scene"):
		var scene = fxm.get_vfx_scene(key)
		if scene is PackedScene:
			return scene

	return null

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


func _play_card_activation_sfx(
	card: Node,
	ctx: Dictionary = {}
) -> void:
	var presentation = ctx.get(
		"presentation",
		{}
	)

	if typeof(presentation) == TYPE_DICTIONARY:
		var activation_fx_key := str(
			presentation.get(
				"activation_fx_key",
				""
			)
		).strip_edges()

		if activation_fx_key != "":
			return

	var key := ""

	if typeof(presentation) == TYPE_DICTIONARY:
		key = str(
			presentation.get(
				"activation_sfx_key",
				""
			)
		)

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

func play_coin_toss_fx(success: bool, face: String = "", on_completed: Callable = Callable()) -> void:
	if bm == null:
		return

	var scene := _get_duel_vfx_scene("coin_toss")

	if scene == null:
		push_warning("DuelAnimationService: no se encontró VFX 'coin_toss'.")
		return

	var fx = scene.instantiate()

	_begin_duel_animation_lock()

	if not is_instance_valid(fx):
		_end_duel_animation_lock()
		return

	var parent_node := get_tree().current_scene

	if parent_node == null:
		parent_node = bm.get_parent()

	if parent_node == null:
		parent_node = bm

	parent_node.add_child(fx)

	var cleanup := func() -> void:
		if on_completed.is_valid():
			on_completed.call()

		if is_instance_valid(fx):
			fx.queue_free()

		_end_duel_animation_lock()

	if fx.has_signal("finished"):
		fx.finished.connect(
			func(_success: bool, _face: String) -> void:
				cleanup.call(),
			CONNECT_ONE_SHOT
		)
	else:
		get_tree().create_timer(2.0).timeout.connect(
			func() -> void:
				cleanup.call(),
			CONNECT_ONE_SHOT
		)

	if fx.has_method("play"):
		fx.play(success, face)
	else:
		cleanup.call()

func play_exodia_win_fx(winner_side: String) -> void:
	var scene := _get_duel_vfx_scene("exodia_win")

	if scene == null:
		push_warning("DuelAnimationService: no se encontró VFX 'exodia_win'.")
		await get_tree().create_timer(0.35).timeout
		return

	_begin_duel_animation_lock()

	var fx = scene.instantiate()

	if not is_instance_valid(fx):
		_end_duel_animation_lock()
		return

	var parent_node := get_tree().current_scene

	if parent_node == null:
		parent_node = bm.get_parent()

	if parent_node == null:
		parent_node = bm

	parent_node.add_child(fx)

	if fx.has_method("setup"):
		fx.setup(winner_side)

	if fx.has_method("play"):
		fx.play()

	if fx.has_signal("finished"):
		await fx.finished
	else:
		await get_tree().create_timer(3.0).timeout

	if is_instance_valid(fx):
		fx.queue_free()

	_end_duel_animation_lock()

func queue_effect_fx(
	key: String,
	effect_ctx: Dictionary = {},
	source: Node = null,
	targets: Array = [],
	phase: String = "resolution",
	on_started: Callable = Callable()
) -> bool:
	key = str(key).strip_edges()

	if key == "":
		push_warning(
			"DuelAnimationService: se intentó encolar un FX sin key."
		)
		return false

	var scene := _get_duel_vfx_scene(key)

	if scene == null:
		push_warning(
			"DuelAnimationService: effect FX no registrado: '%s'."
			% key
		)
		return false

	print(
		"QUEUE EFFECT FX key=",
		key,
		" phase=",
		phase,
		" targets=",
		targets.size(),
		" scene=",
		scene.resource_path
	)

	var prepared_ctx := effect_ctx.duplicate(true)

	prepared_ctx["fx_key"] = key
	prepared_ctx["presentation_phase"] = phase
	prepared_ctx["source_snapshot"] = _snapshot_effect_fx_node(
		source
	)

	var target_snapshots: Array = []
	var target_visual_proxies: Array = []

	for target in targets:
		target_snapshots.append(
			_snapshot_effect_fx_node(target)
		)

		var proxy := _create_effect_fx_visual_proxy(target)
		target_visual_proxies.append(proxy)

	prepared_ctx["target_snapshots"] = target_snapshots
	prepared_ctx["target_visual_proxies"] = target_visual_proxies

	print(
		"EFFECT FX PROXIES key=",
		key,
		" targets=",
		targets.size(),
		" proxies=",
		target_visual_proxies.filter(
			func(proxy): return is_instance_valid(proxy)
		).size()
	)

	_effect_fx_queue.append({
		"request_type": "FX",
		"scene": scene,
		"context": prepared_ctx,
		"fallback_duration": float(
			prepared_ctx.get("fx_fallback_duration", 0.75)
		),
		"on_started": on_started
	})

	if not _effect_fx_queue_running \
	and not _effect_fx_queue_paused:
		call_deferred("_drain_effect_fx_queue")

	return true

func queue_effect_resolution(
	callback: Callable,
	label: String = "",
	retained_source: Node = null
) -> bool:
	if not callback.is_valid():
		push_warning(
			"DuelAnimationService: se intentó encolar una resolución inválida."
		)
		return false

	if is_instance_valid(retained_source):
		_retain_node_for_effect_resolution(
			retained_source
		)

	_effect_fx_queue.append({
		"request_type": "CALLBACK",
		"callback": callback,
		"label": label,
		"retained_source": retained_source
	})

	if not _effect_fx_queue_running \
	and not _effect_fx_queue_paused:
		call_deferred("_drain_effect_fx_queue")

	return true

func _create_effect_fx_visual_proxy(target: Node) -> Node2D:
	if not is_instance_valid(target):
		return null

	if not target.has_method("create_fx_visual_clone"):
		push_warning(
			"DuelAnimationService: '%s' no implementa create_fx_visual_clone()."
			% str(target.name)
		)
		return null

	var proxy = target.create_fx_visual_clone()

	if not is_instance_valid(proxy):
		push_warning(
			"DuelAnimationService: create_fx_visual_clone() devolvió null para '%s'."
			% str(target.name)
		)
		return null

	if not (proxy is Node2D):
		push_warning(
			"DuelAnimationService: el proxy de '%s' no es Node2D."
			% str(target.name)
		)
		proxy.free()
		return null

	return proxy as Node2D

func _drain_effect_fx_queue() -> void:
	if _effect_fx_queue_running:
		return

	if _effect_fx_queue_paused:
		return

	_effect_fx_queue_running = true
	_begin_duel_animation_lock()

	while not _effect_fx_queue.is_empty():
		if _effect_fx_queue_paused:
			break

		var request: Dictionary = \
			_effect_fx_queue.pop_front()

		var request_type := str(
			request.get(
				"request_type",
				"FX"
			)
		).to_upper()

		match request_type:
			"CALLBACK":
				await _play_effect_resolution_request(
					request
				)

			_:
				await _play_effect_fx_request(
					request
				)

	_end_duel_animation_lock()
	_effect_fx_queue_running = false

	if not _effect_fx_queue_paused \
	and not _effect_fx_queue.is_empty():
		call_deferred("_drain_effect_fx_queue")

func _play_effect_resolution_request(
	request: Dictionary
) -> void:
	var callback: Callable = request.get(
		"callback",
		Callable()
	)

	var retained_source: Node = request.get(
		"retained_source",
		null
	)

	if not callback.is_valid():
		_release_node_after_effect_resolution(
			retained_source
		)
		return

	var label := str(
		request.get(
			"label",
			"unnamed_effect"
		)
	)

	print(
		"RESOLVE EFFECT CALLBACK label=",
		label
	)

	# La cola ya posee un lock propio. Si la resolución
	# inicia destrucciones, coin toss u otras animaciones,
	# esos procesos elevarán temporalmente este contador.
	var base_lock_count := int(
		bm.duel_animation_lock_count
	)

	callback.call()

	# Espera las animaciones iniciadas por la resolución,
	# pero no espera el lock perteneciente a esta propia cola.
	while int(bm.duel_animation_lock_count) \
	> base_lock_count:
		await get_tree().process_frame

	_release_node_after_effect_resolution(
		retained_source
	)

	await get_tree().process_frame



func _play_effect_fx_request(request: Dictionary) -> void:
	var scene = request.get("scene", null)

	if not (scene is PackedScene):
		return
	print(
	"PLAY EFFECT FX scene=",
	scene.resource_path
	)
	var fx = (scene as PackedScene).instantiate()

	if not is_instance_valid(fx):
		push_warning(
			"DuelAnimationService: no se pudo instanciar %s."
			% scene.resource_path
		)
		return
	if not fx.has_method("play_effect_fx"):
		push_warning(
			"DuelAnimationService: la escena %s no tiene play_effect_fx()."
			% scene.resource_path
		)

	var parent_node := get_tree().current_scene

	if parent_node == null and bm != null:
		parent_node = bm.get_parent()

	if parent_node == null:
		parent_node = bm

	parent_node.add_child(fx)

	var effect_ctx: Dictionary = request.get(
		"context",
		{}
	)

	if fx.has_method("setup_effect_fx"):
		fx.setup_effect_fx(effect_ctx)
	else:
		_apply_effect_fx_fallback_transform(
			fx,
			effect_ctx
		)

	var playback_started := false

	if fx.has_method("play_effect_fx"):
		fx.play_effect_fx()
		playback_started = true
	elif fx.has_method("play"):
		fx.play()
		playback_started = true

	if playback_started:
		var on_started = request.get(
			"on_started",
			Callable()
		)

		if on_started is Callable \
		and on_started.is_valid():
			on_started.call()

	if fx.has_signal("finished"):
		await fx.finished
	else:
		var fallback_duration = max(
			0.05,
			float(request.get("fallback_duration", 0.75))
		)

		await get_tree().create_timer(
			fallback_duration
		).timeout

	if is_instance_valid(fx):
		fx.queue_free()

func _snapshot_effect_fx_node(node: Node) -> Dictionary:
	if not is_instance_valid(node):
		return {}

	var snapshot := {
		"instance_id": node.get_instance_id(),
		"node_name": str(node.name)
	}

	if node is Node2D:
		var node_2d := node as Node2D
		var visual_center := _get_card_visual_center_global(node_2d)
		var canvas_transform := node_2d.get_viewport().get_canvas_transform()

		snapshot["global_position"] = visual_center
		snapshot["screen_position"] = canvas_transform * visual_center
		snapshot["global_rotation"] = node_2d.global_rotation
		snapshot["global_scale"] = node_2d.global_scale
		snapshot["z_index"] = node_2d.z_index

	if "id" in node:
		snapshot["card_id"] = str(node.id)

	if "cardname" in node:
		snapshot["card_name"] = str(node.cardname)

	if "kind" in node:
		snapshot["kind"] = str(node.kind)

	if "owner_side" in node:
		snapshot["owner_side"] = str(node.owner_side)

	return snapshot

func _apply_effect_fx_fallback_transform(
	fx: Node,
	effect_ctx: Dictionary
) -> void:
	if not (fx is Node2D):
		return

	var snapshots = effect_ctx.get(
		"target_snapshots",
		[]
	)

	if typeof(snapshots) != TYPE_ARRAY:
		return

	if snapshots.is_empty():
		return

	var first = snapshots[0]

	if typeof(first) != TYPE_DICTIONARY:
		return

	if not first.has("global_position"):
		return

	var fx_2d := fx as Node2D
	fx_2d.global_position = first["global_position"]
	fx_2d.z_index = int(first.get("z_index", 0)) + 150

func begin_battle_presentation(
	request: Dictionary,
	on_damage_cue: Callable = Callable()
) -> Node:
	var scene := _get_duel_vfx_scene("battle_presentation")

	if scene == null:
		push_warning(
			"DuelAnimationService: falta VFX 'battle_presentation'."
		)

		if on_damage_cue.is_valid():
			on_damage_cue.call()

		return null

	var attacker = request.get("attacker", null)
	var defender = request.get("defender", null)

	if not is_instance_valid(attacker):
		return null

	if not is_instance_valid(defender):
		return null

	var attacker_owner := str(
		request.get("attacker_owner", "")
	)

	var defender_owner := str(
		request.get("defender_owner", "")
	)

	var player_card = (
		attacker
		if attacker_owner == "Player"
		else defender
	)

	var opponent_card = (
		attacker
		if attacker_owner == "Opponent"
		else defender
	)

	var player_proxy := _create_effect_fx_visual_proxy(
		player_card
	)

	var opponent_proxy := _create_effect_fx_visual_proxy(
		opponent_card
	)

	var prepared_request := request.duplicate(true)

	prepared_request["player_card_proxy"] = player_proxy
	prepared_request["opponent_card_proxy"] = opponent_proxy
	prepared_request["player_card_snapshot"] = \
		_snapshot_effect_fx_node(player_card)
	prepared_request["opponent_card_snapshot"] = \
		_snapshot_effect_fx_node(opponent_card)

	var fx = scene.instantiate()

	if not is_instance_valid(fx):
		return null

	var parent_node := get_tree().current_scene

	if parent_node == null:
		parent_node = bm

	parent_node.add_child(fx)

	if not fx.has_method("setup_battle_presentation"):
		fx.queue_free()
		return null

	_battle_presentation_active = true
	_effect_fx_queue_paused = true
	_begin_duel_animation_lock()

	fx.setup_battle_presentation(prepared_request)

	if fx.has_signal("damage_cue"):
		fx.damage_cue.connect(
			func() -> void:
				if on_damage_cue.is_valid():
					on_damage_cue.call()

				if fx.has_method("set_resolved_lp"):
					fx.set_resolved_lp(
						bm.player_hp,
						bm.opponent_hp
					),
			CONNECT_ONE_SHOT
		)

	if fx.has_method("play_battle_presentation"):
		fx.play_battle_presentation()

	if fx.has_signal("hold_reached"):
		await fx.hold_reached

	return fx

func finish_battle_presentation(fx: Node) -> void:
	if is_instance_valid(fx):
		if fx.has_method("continue_to_close"):
			fx.continue_to_close()

		if fx.has_signal("finished"):
			await fx.finished

		if is_instance_valid(fx):
			fx.queue_free()

	_battle_presentation_active = false

	if not _effect_fx_queue.is_empty() \
	and post_battle_effect_delay > 0.0:
		await get_tree().create_timer(
			post_battle_effect_delay
		).timeout

	_effect_fx_queue_paused = false

	if not _effect_fx_queue.is_empty() \
	and not _effect_fx_queue_running:
		_drain_effect_fx_queue()

	_end_duel_animation_lock()

func _retain_node_for_effect_resolution(
	node: Node
) -> void:
	if not is_instance_valid(node):
		return

	var current_count := int(
		node.get_meta(
			EFFECT_RETAIN_COUNT_META,
			0
		)
	)

	node.set_meta(
		EFFECT_RETAIN_COUNT_META,
		current_count + 1
	)

func request_free_after_effect_resolutions(
	node: Node
) -> void:
	if not is_instance_valid(node):
		return

	var retain_count := int(
		node.get_meta(
			EFFECT_RETAIN_COUNT_META,
			0
		)
	)

	if retain_count > 0:
		node.set_meta(
			EFFECT_PENDING_FREE_META,
			true
		)

		if node is CanvasItem:
			(node as CanvasItem).visible = false

		return

	_free_effect_node(node)

func _release_node_after_effect_resolution(
	node: Node
) -> void:
	if not is_instance_valid(node):
		return

	var retain_count := int(
		node.get_meta(
			EFFECT_RETAIN_COUNT_META,
			0
		)
	)

	retain_count = max(
		0,
		retain_count - 1
	)

	node.set_meta(
		EFFECT_RETAIN_COUNT_META,
		retain_count
	)

	if retain_count > 0:
		return

	node.remove_meta(
		EFFECT_RETAIN_COUNT_META
	)

	var pending_free := bool(
		node.get_meta(
			EFFECT_PENDING_FREE_META,
			false
		)
	)

	if pending_free:
		node.remove_meta(
			EFFECT_PENDING_FREE_META
		)

		_free_effect_node(node)

func _free_effect_node(node: Node) -> void:
	if not is_instance_valid(node):
		return

	if node.is_inside_tree():
		node.queue_free()
	else:
		node.free()
