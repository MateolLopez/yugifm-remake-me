extends CanvasLayer
class_name BattlePresentationFx

signal damage_cue
signal hold_reached
signal finished

@export_group("Battle Layout")
@export_range(0.0, 1.0) var player_column_ratio: float = 0.30
@export_range(0.0, 1.0) var opponent_column_ratio: float = 0.70
@export_range(0.0, 1.0) var cards_vertical_ratio: float = 0.50
@export_range(0.1, 1.0) var card_height_ratio: float = 0.60

@export var card_reference_size: Vector2 = Vector2(329.0, 479.0)
@export var max_battle_card_scale: float = 2.0

@export_group("Opening")
@export var fade_in_duration: float = 0.25
@export var card_intro_duration: float = 0.30
@export var card_intro_scale: Vector2 = Vector2(0.65, 0.65)
@export var battle_card_scale: Vector2 = Vector2.ONE

@export_group("Impact")
@export var impact_duration: float = 0.08
@export var shake_duration: float = 0.42
@export var shake_distance: float = 14.0
@export var shake_steps: int = 9

@export_group("Attacked FX")
@export var attacked_animation_name: StringName = &"battle_attacked"
@export var attacked_fx_scale: Vector2 = Vector2.ONE
@export var attacked_fx_z_offset: int = 100

@export_group("Damage")
@export var damage_label_duration: float = 0.65
@export var lp_count_duration: float = 0.50

@export_group("Damage Presentation")
@export var damage_appear_duration: float = 0.18
@export var damage_center_hold_duration: float = 0.20
@export var damage_travel_duration: float = 0.45
@export var damage_fade_duration: float = 0.15

@export var damage_start_scale: Vector2 = Vector2(0.35, 0.35)
@export var damage_center_scale: Vector2 = Vector2(1.25, 1.25)
@export var damage_arrival_scale: Vector2 = Vector2(0.75, 0.75)
@export var damage_target_offset: Vector2 = Vector2(0.0, -12.0)

@export_group("Destruction")
@export var destruction_hold_duration: float = 0.22
@export var destroy_fx_scene: PackedScene

@export_group("Closing")
@export var fade_out_duration: float = 0.25

@export_group("LP Layout")
@export var lp_label_gap: float = 24.0
@export var lp_label_width_multiplier: float = 1.15
@export var lp_label_min_height: float = 40.0

@onready var root: Control = $Root
@onready var darker: ColorRect = $Root/Darker
@onready var battle_area: Control = $Root/BattleArea

@onready var battle_attacked_fx: AnimatedSprite2D = \
	$Root/BattleArea/BattleAttackedFx

@onready var player_card_anchor: Node2D = \
	$Root/BattleArea/PlayerCardAnchor

@onready var opponent_card_anchor: Node2D = \
	$Root/BattleArea/OpponentCardAnchor

@onready var player_lp_label: Label = \
	$Root/BattleArea/PlayerLpLabel

@onready var opponent_lp_label: Label = \
	$Root/BattleArea/OpponentLpLabel

@onready var damage_label: Label = \
	$Root/BattleArea/DamageLabel

@onready var audio_open: AudioStreamPlayer = $Root/AudioOpen
@onready var audio_impact: AudioStreamPlayer = $Root/AudioImpact
@onready var audio_destroy: AudioStreamPlayer = $Root/AudioDestroy
@onready var audio_close: AudioStreamPlayer = $Root/AudioClose

var battle_context: Dictionary = {}

var player_proxy: Node2D = null
var opponent_proxy: Node2D = null

var _resolved_player_lp: int = 0
var _resolved_opponent_lp: int = 0

var _playing: bool = false
var _waiting_to_close: bool = false

func _ready() -> void:
	_fit_to_viewport()

	get_viewport().size_changed.connect(
		_fit_to_viewport
	)

	root.visible = false
	damage_label.visible = false
	damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	damage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	damage_label.pivot_offset = damage_label.size * 0.5

	_prepare_battle_attacked_fx()

func setup_battle_presentation(
	ctx: Dictionary
) -> void:
	battle_context = ctx.duplicate(true)

	player_proxy = battle_context.get(
		"player_card_proxy",
		null
	)

	opponent_proxy = battle_context.get(
		"opponent_card_proxy",
		null
	)

	_resolved_player_lp = int(
		battle_context.get(
			"player_hp_before",
			0
		)
	)

	_resolved_opponent_lp = int(
		battle_context.get(
			"opponent_hp_before",
			0
		)
	)

	player_lp_label.text = str(_resolved_player_lp)
	opponent_lp_label.text = str(_resolved_opponent_lp)

	_attach_proxy(
		player_proxy,
		player_card_anchor
	)

	_attach_proxy(
		opponent_proxy,
		opponent_card_anchor
	)

	_layout_battle_cards(
		get_viewport().get_visible_rect().size
	)
func _attach_proxy(
	proxy: Node2D,
	anchor: Node2D
) -> void:
	if not is_instance_valid(proxy):
		return

	if proxy.get_parent() != null:
		proxy.reparent(anchor)
	else:
		anchor.add_child(proxy)

	proxy.position = Vector2.ZERO
	proxy.rotation = 0.0
	proxy.scale = battle_card_scale * card_intro_scale
	proxy.modulate.a = 0.0
	proxy.visible = true

func _fit_to_viewport() -> void:
	if not is_instance_valid(root):
		return

	var viewport_size := get_viewport().get_visible_rect().size

	root.position = Vector2.ZERO
	root.size = viewport_size

	if is_instance_valid(darker):
		darker.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT
		)

	if is_instance_valid(battle_area):
		battle_area.position = Vector2.ZERO
		battle_area.size = viewport_size

	_layout_battle_cards(viewport_size)

func _layout_battle_cards(viewport_size: Vector2) -> void:
	if is_instance_valid(player_card_anchor):
		player_card_anchor.position = Vector2(
			viewport_size.x * player_column_ratio,
			viewport_size.y * cards_vertical_ratio
		)

	if is_instance_valid(opponent_card_anchor):
		opponent_card_anchor.position = Vector2(
			viewport_size.x * opponent_column_ratio,
			viewport_size.y * cards_vertical_ratio
		)

	battle_card_scale = _calculate_battle_card_scale(
		viewport_size
	)

	if is_instance_valid(player_proxy):
		player_proxy.scale = battle_card_scale

	if is_instance_valid(opponent_proxy):
		opponent_proxy.scale = battle_card_scale

	_layout_lp_labels()

func _layout_lp_labels() -> void:
	var displayed_card_width := (
		card_reference_size.x
		* battle_card_scale.x
	)

	var displayed_card_height := (
		card_reference_size.y
		* battle_card_scale.y
	)

	var label_width := (
		displayed_card_width
		* lp_label_width_multiplier
	)

	var label_height = max(
		lp_label_min_height,
		player_lp_label.get_combined_minimum_size().y,
		opponent_lp_label.get_combined_minimum_size().y
	)

	if is_instance_valid(player_card_anchor) \
	and is_instance_valid(player_lp_label):
		_position_lp_label_below_anchor(
			player_lp_label,
			player_card_anchor,
			displayed_card_height,
			label_width,
			label_height
		)

	if is_instance_valid(opponent_card_anchor) \
	and is_instance_valid(opponent_lp_label):
		_position_lp_label_below_anchor(
			opponent_lp_label,
			opponent_card_anchor,
			displayed_card_height,
			label_width,
			label_height
		)

func _position_lp_label_below_anchor(
	label: Label,
	card_anchor: Node2D,
	displayed_card_height: float,
	label_width: float,
	label_height: float
) -> void:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	label.size = Vector2(
		label_width,
		label_height
	)

	var card_bottom_y := (
		card_anchor.position.y
		+ displayed_card_height * 0.5
	)

	label.position = Vector2(
		card_anchor.position.x - label_width * 0.5,
		card_bottom_y + lp_label_gap
	)

func _calculate_battle_card_scale(
	viewport_size: Vector2
) -> Vector2:
	if card_reference_size.y <= 0.0:
		return Vector2.ONE

	var target_height := viewport_size.y * card_height_ratio
	var uniform_scale := target_height / card_reference_size.y

	uniform_scale = min(
		uniform_scale,
		max_battle_card_scale
	)

	return Vector2(
		uniform_scale,
		uniform_scale
	)

func play_battle_presentation() -> void:
	if _playing:
		return

	_playing = true
	call_deferred("_run_until_hold")


func _run_until_hold() -> void:
	root.visible = true

	await _open_presentation()

	var attacked_proxy := _get_attacked_proxy()

	await _play_impact(attacked_proxy)

	damage_cue.emit()

	await _show_resolved_damage()

	await _play_projected_destructions()

	_waiting_to_close = true
	hold_reached.emit()

func _open_presentation() -> void:
	darker.modulate.a = 0.0
	battle_area.modulate.a = 0.0

	if is_instance_valid(audio_open) \
	and audio_open.stream != null:
		audio_open.play()

	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(
		darker,
		"modulate:a",
		1.0,
		fade_in_duration
	)

	tween.tween_property(
		battle_area,
		"modulate:a",
		1.0,
		fade_in_duration
	)

	for proxy in [player_proxy, opponent_proxy]:
		if not is_instance_valid(proxy):
			continue

		tween.tween_property(
			proxy,
			"modulate:a",
			1.0,
			card_intro_duration
		)

		tween.tween_property(
			proxy,
			"scale",
			battle_card_scale,
			card_intro_duration
		).set_trans(
			Tween.TRANS_BACK
		).set_ease(
			Tween.EASE_OUT
		)

	await tween.finished

func _get_attacked_proxy() -> Node2D:
	var defender_owner := str(
		battle_context.get(
			"defender_owner",
			""
		)
	)

	if defender_owner == "Player":
		return player_proxy

	return opponent_proxy

func _play_impact(target: Node2D) -> void:
	if not is_instance_valid(target):
		return

	if is_instance_valid(audio_impact) \
	and audio_impact.stream != null:
		audio_impact.play()

	_start_battle_attacked_fx(target)

	var original_position := target.position
	var original_scale := target.scale
	var original_modulate := target.modulate

	var impact := create_tween()
	impact.set_parallel(true)

	impact.tween_property(
		target,
		"scale",
		original_scale * 0.93,
		impact_duration
	).set_trans(
		Tween.TRANS_SINE
	).set_ease(
		Tween.EASE_OUT
	)

	impact.tween_property(
		target,
		"modulate",
		Color(1.8, 1.8, 1.8, original_modulate.a),
		impact_duration
	)

	await impact.finished

	if not is_instance_valid(target):
		return

	target.scale = original_scale
	target.modulate = original_modulate

	var step_duration := shake_duration / float(
		max(1, shake_steps)
	)

	for index in range(shake_steps):
		if not is_instance_valid(target):
			break

		var direction := -1.0 if index % 2 == 0 else 1.0

		var shake := create_tween()

		shake.tween_property(
			target,
			"position",
			original_position + Vector2(
				shake_distance * direction,
				0.0
			),
			step_duration
		).set_trans(
			Tween.TRANS_SINE
		).set_ease(
			Tween.EASE_IN_OUT
		)

		await shake.finished

	if is_instance_valid(target):
		target.position = original_position

	if is_instance_valid(battle_attacked_fx):
		if battle_attacked_fx.is_playing():
			await battle_attacked_fx.animation_finished

		battle_attacked_fx.stop()
		battle_attacked_fx.frame = 0
		battle_attacked_fx.visible = false

func set_resolved_lp(
	player_lp: int,
	opponent_lp: int
) -> void:
	_resolved_player_lp = player_lp
	_resolved_opponent_lp = opponent_lp

func _show_resolved_damage() -> void:
	var damage := int(
		battle_context.get(
			"battle_damage",
			0
		)
	)

	var target_owner := str(
		battle_context.get(
			"damage_target_owner",
			""
		)
	)

	if damage <= 0 or target_owner == "":
		await _update_lp_labels_without_damage_animation()
		return

	var target_label := _get_lp_label_for_owner(
		target_owner
	)

	if not is_instance_valid(target_label):
		await _update_lp_labels_without_damage_animation()
		return

	var lp_before := _get_lp_before_for_owner(
		target_owner
	)

	var lp_after := _get_resolved_lp_for_owner(
		target_owner
	)

	_prepare_damage_label(damage)

	await _animate_damage_label_appearance()

	if damage_center_hold_duration > 0.0:
		await get_tree().create_timer(
			damage_center_hold_duration
		).timeout

	await _move_damage_label_to_lp(
		target_label
	)

	await _animate_lp_label(
		target_label,
		lp_before,
		lp_after
	)

	await _animate_damage_label_disappearance()

	await _update_other_resolved_lp(target_owner)

func _update_lp_labels_without_damage_animation() -> void:
	var player_before := int(
		battle_context.get(
			"player_hp_before",
			_resolved_player_lp
		)
	)

	var opponent_before := int(
		battle_context.get(
			"opponent_hp_before",
			_resolved_opponent_lp
		)
	)

	if player_before != _resolved_player_lp:
		await _animate_lp_label(
			player_lp_label,
			player_before,
			_resolved_player_lp
		)
	else:
		player_lp_label.text = str(
			_resolved_player_lp
		)

	if opponent_before != _resolved_opponent_lp:
		await _animate_lp_label(
			opponent_lp_label,
			opponent_before,
			_resolved_opponent_lp
		)
	else:
		opponent_lp_label.text = str(
			_resolved_opponent_lp
		)

func _update_other_resolved_lp(
	damaged_owner: String
) -> void:
	if damaged_owner != "Player":
		var player_before := int(
			battle_context.get(
				"player_hp_before",
				_resolved_player_lp
			)
		)

		if player_before != _resolved_player_lp:
			await _animate_lp_label(
				player_lp_label,
				player_before,
				_resolved_player_lp
			)
		else:
			player_lp_label.text = str(
				_resolved_player_lp
			)

	if damaged_owner != "Opponent":
		var opponent_before := int(
			battle_context.get(
				"opponent_hp_before",
				_resolved_opponent_lp
			)
		)

		if opponent_before != _resolved_opponent_lp:
			await _animate_lp_label(
				opponent_lp_label,
				opponent_before,
				_resolved_opponent_lp
			)
		else:
			opponent_lp_label.text = str(
				_resolved_opponent_lp
			)

func _prepare_damage_label(damage: int) -> void:
	damage_label.text = str(damage)
	damage_label.reset_size()

	var minimum_size := damage_label.get_combined_minimum_size()

	damage_label.size = Vector2(
		max(minimum_size.x, 120.0),
		max(minimum_size.y, 60.0)
	)

	damage_label.pivot_offset = damage_label.size * 0.5

	var viewport_size := get_viewport().get_visible_rect().size

	damage_label.position = (
		viewport_size * 0.5
		- damage_label.size * 0.5
	)

	damage_label.scale = damage_start_scale
	damage_label.modulate.a = 0.0
	damage_label.visible = true

func _animate_damage_label_appearance() -> void:
	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(
		damage_label,
		"modulate:a",
		1.0,
		damage_appear_duration
	).set_trans(
		Tween.TRANS_SINE
	).set_ease(
		Tween.EASE_OUT
	)

	tween.tween_property(
		damage_label,
		"scale",
		damage_center_scale,
		damage_appear_duration
	).set_trans(
		Tween.TRANS_BACK
	).set_ease(
		Tween.EASE_OUT
	)

	await tween.finished

func _move_damage_label_to_lp(
	target_label: Label
) -> void:
	var target_center := (
		target_label.position
		+ target_label.size * 0.5
	)

	var destination := (
		target_center
		- damage_label.size * 0.5
		+ damage_target_offset
	)

	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(
		damage_label,
		"position",
		destination,
		damage_travel_duration
	).set_trans(
		Tween.TRANS_QUINT
	).set_ease(
		Tween.EASE_IN
	)

	tween.tween_property(
		damage_label,
		"scale",
		damage_arrival_scale,
		damage_travel_duration
	).set_trans(
		Tween.TRANS_SINE
	).set_ease(
		Tween.EASE_IN
	)

	await tween.finished

func _animate_damage_label_disappearance() -> void:
	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(
		damage_label,
		"modulate:a",
		0.0,
		damage_fade_duration
	)

	tween.tween_property(
		damage_label,
		"scale",
		damage_arrival_scale * 0.6,
		damage_fade_duration
	)

	await tween.finished

	damage_label.visible = false

func _get_lp_label_for_owner(
	owner: String
) -> Label:
	match owner:
		"Player":
			return player_lp_label

		"Opponent":
			return opponent_lp_label

		_:
			return null

func _get_lp_before_for_owner(
	owner: String
) -> int:
	if owner == "Player":
		return int(
			battle_context.get(
				"player_hp_before",
				_resolved_player_lp
			)
		)

	if owner == "Opponent":
		return int(
			battle_context.get(
				"opponent_hp_before",
				_resolved_opponent_lp
			)
		)

	return 0

func _get_resolved_lp_for_owner(
	owner: String
) -> int:
	if owner == "Player":
		return _resolved_player_lp

	if owner == "Opponent":
		return _resolved_opponent_lp

	return 0

func _animate_lp_label(
	label: Label,
	from_value: int,
	to_value: int
) -> void:
	if from_value == to_value:
		label.text = str(to_value)
		return

	var tween := create_tween()

	tween.tween_method(
		func(value: float) -> void:
			label.text = str(roundi(value)),
		float(from_value),
		float(to_value),
		lp_count_duration
	)

	await tween.finished
	label.text = str(to_value)

func _play_projected_destructions() -> void:
	var player_destroyed := bool(
		battle_context.get(
			"player_destroyed_by_battle",
			false
		)
	)

	var opponent_destroyed := bool(
		battle_context.get(
			"opponent_destroyed_by_battle",
			false
		)
	)

	if player_destroyed:
		await _play_proxy_destruction(player_proxy)

	if opponent_destroyed:
		await _play_proxy_destruction(opponent_proxy)

	if player_destroyed or opponent_destroyed:
		await get_tree().create_timer(
			destruction_hold_duration
		).timeout

func _play_proxy_destruction(
	proxy: Node2D
) -> void:
	if not is_instance_valid(proxy):
		return

	if is_instance_valid(audio_destroy) \
	and audio_destroy.stream != null:
		audio_destroy.play()

	if destroy_fx_scene != null:
		var destroy_fx = destroy_fx_scene.instantiate()

		if is_instance_valid(destroy_fx):
			proxy.get_parent().add_child(destroy_fx)

			if destroy_fx is Node2D:
				var destroy_2d := destroy_fx as Node2D
				destroy_2d.position = proxy.position
				destroy_2d.z_index = proxy.z_index + 20

			if destroy_fx.has_method("play"):
				destroy_fx.play()

			if destroy_fx.has_signal("finished"):
				await destroy_fx.finished

			if is_instance_valid(destroy_fx):
				destroy_fx.queue_free()

	var fade := create_tween()
	fade.set_parallel(true)

	fade.tween_property(
		proxy,
		"modulate:a",
		0.0,
		0.18
	)

	fade.tween_property(
		proxy,
		"scale",
		proxy.scale * 0.75,
		0.18
	)

	await fade.finished

func continue_to_close() -> void:
	if not _waiting_to_close:
		return

	_waiting_to_close = false
	call_deferred("_close_presentation")

func _close_presentation() -> void:
	if is_instance_valid(audio_close) \
	and audio_close.stream != null:
		audio_close.play()

	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(
		darker,
		"modulate:a",
		0.0,
		fade_out_duration
	)

	tween.tween_property(
		battle_area,
		"modulate:a",
		0.0,
		fade_out_duration
	)

	await tween.finished

	_cleanup_proxy(player_proxy)
	_cleanup_proxy(opponent_proxy)

	root.visible = false
	_playing = false

	finished.emit()

func _cleanup_proxy(proxy: Node2D) -> void:
	if is_instance_valid(proxy):
		proxy.queue_free()

func _prepare_battle_attacked_fx() -> void:
	if not is_instance_valid(battle_attacked_fx):
		return

	battle_attacked_fx.stop()
	battle_attacked_fx.frame = 0
	battle_attacked_fx.visible = false
	battle_attacked_fx.scale = attacked_fx_scale
	battle_attacked_fx.z_index = attacked_fx_z_offset

func _start_battle_attacked_fx(target: Node2D) -> void:
	if not is_instance_valid(target):
		return

	if not is_instance_valid(battle_attacked_fx):
		return

	if battle_attacked_fx.sprite_frames == null:
		return

	if not battle_attacked_fx.sprite_frames.has_animation(
		attacked_animation_name
	):
		push_warning(
			"BattlePresentationFx: no existe la animación '%s'."
			% String(attacked_animation_name)
		)
		return

	battle_attacked_fx.sprite_frames.set_animation_loop(
		attacked_animation_name,
		false
	)

	battle_attacked_fx.global_position = target.global_position
	battle_attacked_fx.global_rotation = 0.0
	battle_attacked_fx.scale = attacked_fx_scale
	battle_attacked_fx.z_index = target.z_index + attacked_fx_z_offset
	battle_attacked_fx.visible = true

	battle_attacked_fx.stop()
	battle_attacked_fx.frame = 0
	battle_attacked_fx.play(attacked_animation_name)
