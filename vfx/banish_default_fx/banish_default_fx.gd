extends CanvasLayer
class_name BanishDefaultFx

signal finished

@export_group("Darker")
@export var darker_alpha: float = 0.72
@export var fade_in_duration: float = 0.28
@export var fade_out_duration: float = 0.38

@export_group("Hole")
@export var hole_start_scale: Vector2 = Vector2(0.08, 0.08)
@export var hole_open_scale: Vector2 = Vector2(0.55, 0.55)
@export var hole_end_scale: Vector2 = Vector2(0.03, 0.03)
@export var hole_rotation_speed: float = 1.8

@export_group("Absorption")
@export var absorb_duration: float = 0.62
@export var delay_between_cards: float = 0.12
@export var absorb_spin_turns: float = 2.5
@export var stretch_x_multiplier: float = 0.10
@export var stretch_y_multiplier: float = 1.35
@export var final_card_scale: Vector2 = Vector2(0.01, 0.01)

@export_group("Timing")
@export var open_hold_duration: float = 0.10
@export var close_hold_duration: float = 0.08

@onready var root: Control = $Root
@onready var darker: ColorRect = $Root/Darker
@onready var absorb_layer: Node2D = $Root/AbsorbLayer
@onready var hole_root: Node2D = $Root/HoleRoot
@onready var hole_glow: Sprite2D = $Root/HoleRoot/HoleGlow
@onready var hole_pivot: Node2D = $Root/HoleRoot/HolePivot
@onready var hole_sprite: Sprite2D = $Root/HoleRoot/HolePivot/HoleSprite

@onready var audio_open: AudioStreamPlayer = $Root/AudioOpen
@onready var audio_absorb: AudioStreamPlayer = $Root/AudioAbsorb
@onready var audio_close: AudioStreamPlayer = $Root/AudioClose

var effect_context: Dictionary = {}
var _playing: bool = false


func _ready() -> void:
	_fit_fullscreen_controls()
	_center_hole()

	var viewport := get_viewport()
	var resize_callback := Callable(
		self,
		"_on_viewport_size_changed"
	)

	if not viewport.size_changed.is_connected(resize_callback):
		viewport.size_changed.connect(resize_callback)

	root.visible = false
	set_process(false)

	darker.modulate.a = 0.0
	hole_root.modulate.a = 0.0
	hole_root.scale = hole_start_scale


func setup_effect_fx(ctx: Dictionary) -> void:
	effect_context = ctx.duplicate(true)

func play_effect_fx() -> void:
	if _playing:
		return

	_playing = true

	root.visible = true
	set_process(true)

	_center_hole()
	_prepare_visual_proxies()

	call_deferred("_play_sequence")

func _process(delta: float) -> void:
	hole_pivot.rotation += hole_rotation_speed * delta


func _play_sequence() -> void:
	await _open_hole()

	var proxies: Array = effect_context.get(
		"target_visual_proxies",
		[]
	)

	var snapshots: Array = effect_context.get(
		"target_snapshots",
		[]
	)

	for index in range(proxies.size()):
		var proxy = proxies[index]

		if not is_instance_valid(proxy):
			continue

		var snapshot: Dictionary = {}

		if index < snapshots.size() \
		and typeof(snapshots[index]) == TYPE_DICTIONARY:
			snapshot = snapshots[index]

		await _absorb_proxy(proxy, snapshot)

		if delay_between_cards > 0.0 \
		and index < proxies.size() - 1:
			await get_tree().create_timer(
				delay_between_cards
			).timeout

	if close_hold_duration > 0.0:
		await get_tree().create_timer(
			close_hold_duration
		).timeout

	await _close_hole()

	_cleanup_visual_proxies()

	set_process(false)
	root.visible = false
	_playing = false

	finished.emit()

func _center_hole() -> void:
	if not is_instance_valid(root):
		return

	hole_root.position = root.size * 0.5

func _prepare_visual_proxies() -> void:
	var proxies: Array = effect_context.get(
		"target_visual_proxies",
		[]
	)

	var snapshots: Array = effect_context.get(
		"target_snapshots",
		[]
	)

	for index in range(proxies.size()):
		var proxy = proxies[index]

		if not is_instance_valid(proxy):
			continue

		if proxy.get_parent() != null:
			proxy.reparent(absorb_layer)
		else:
			absorb_layer.add_child(proxy)

		var snapshot: Dictionary = {}

		if index < snapshots.size() \
		and typeof(snapshots[index]) == TYPE_DICTIONARY:
			snapshot = snapshots[index]

		proxy.position = snapshot.get(
			"screen_position",
			Vector2.ZERO
		)

		proxy.rotation = float(
			snapshot.get(
				"global_rotation",
				0.0
			)
		)

		proxy.scale = snapshot.get(
			"global_scale",
			Vector2.ONE
		)

		proxy.modulate = Color.WHITE
		proxy.visible = true

func _open_hole() -> void:
	darker.modulate.a = 0.0
	hole_root.modulate.a = 0.0
	hole_root.scale = hole_start_scale

	if audio_open.stream != null:
		audio_open.play()

	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(
		darker,
		"modulate:a",
		darker_alpha,
		fade_in_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tween.tween_property(
		hole_root,
		"modulate:a",
		1.0,
		fade_in_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tween.tween_property(
		hole_root,
		"scale",
		hole_open_scale,
		fade_in_duration
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await tween.finished

	if open_hold_duration > 0.0:
		await get_tree().create_timer(
			open_hold_duration
		).timeout

func _absorb_proxy(
	proxy: Node2D,
	_snapshot: Dictionary
) -> void:
	if not is_instance_valid(proxy):
		return

	if audio_absorb.stream != null:
		audio_absorb.play()

	var start_scale := proxy.scale
	var stretched_scale := Vector2(
		start_scale.x * stretch_x_multiplier,
		start_scale.y * stretch_y_multiplier
	)

	var destination := hole_root.position
	var final_rotation := proxy.rotation \
		+ TAU * absorb_spin_turns

	var movement := create_tween()
	movement.set_parallel(true)

	movement.tween_property(
		proxy,
		"position",
		destination,
		absorb_duration
	).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)

	movement.tween_property(
		proxy,
		"rotation",
		final_rotation,
		absorb_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	var scale_tween := create_tween()

	scale_tween.tween_property(
		proxy,
		"scale",
		stretched_scale,
		absorb_duration * 0.62
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	scale_tween.tween_property(
		proxy,
		"scale",
		final_card_scale,
		absorb_duration * 0.38
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

	var fade := create_tween()

	fade.tween_interval(absorb_duration * 0.72)

	fade.tween_property(
		proxy,
		"modulate:a",
		0.0,
		absorb_duration * 0.28
	)

	await movement.finished

	if is_instance_valid(proxy):
		proxy.queue_free()

func _close_hole() -> void:
	if audio_close.stream != null:
		audio_close.play()

	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(
		darker,
		"modulate:a",
		0.0,
		fade_out_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	tween.tween_property(
		hole_root,
		"modulate:a",
		0.0,
		fade_out_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	tween.tween_property(
		hole_root,
		"scale",
		hole_end_scale,
		fade_out_duration
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	await tween.finished

func _cleanup_visual_proxies() -> void:
	var proxies: Array = effect_context.get(
		"target_visual_proxies",
		[]
	)

	for proxy in proxies:
		if is_instance_valid(proxy):
			proxy.queue_free()

func _fit_fullscreen_controls() -> void:
	if not is_instance_valid(root):
		return

	var viewport_size := get_viewport().get_visible_rect().size

	root.position = Vector2.ZERO
	root.size = viewport_size

	if is_instance_valid(darker):
		darker.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT
		)

func _on_viewport_size_changed() -> void:
	_fit_fullscreen_controls()
	_center_hole()
