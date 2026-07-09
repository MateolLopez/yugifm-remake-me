extends CanvasLayer
class_name CoinTossFx

signal finished(success: bool, face: String)

@export var heads_texture: Texture2D
@export var tails_texture: Texture2D

@export var fade_in_duration: float = 0.22
@export var fade_out_duration: float = 0.26

@export var toss_duration: float = 0.90
@export var land_hold_duration: float = 0.18
@export var result_hold_duration: float = 0.65

@export var outside_start_y: float = 420.0
@export var jump_height: float = 190.0
@export var center_offset: Vector2 = Vector2.ZERO

@export var start_scale: Vector2 = Vector2(0.24, 0.24)
@export var end_scale: Vector2 = Vector2(0.52, 0.52)
@export var outro_end_scale: Vector2 = Vector2(0.36, 0.36)

@export var flip_half_duration: float = 0.055
@export var min_edge_scale_x: float = 0.08
@export var rotation_turns: float = 1.0

@export var success_glow_scale_mult: float = 1.22
@export var success_coin_scale_mult: float = 1.08

@onready var root: Control = $Root
@onready var darker: ColorRect = $Root/Darker
@onready var fx_root: Node2D = $Root/FxRoot
@onready var glow: Sprite2D = $Root/FxRoot/Glow
@onready var coin_pivot: Node2D = $Root/FxRoot/CoinPivot
@onready var coin: Sprite2D = $Root/FxRoot/CoinPivot/Coin

@onready var audio_flip: AudioStreamPlayer = $Root/AudioFlip
@onready var audio_land: AudioStreamPlayer = $Root/AudioLand
@onready var audio_success: AudioStreamPlayer = $Root/AudioSuccess
@onready var audio_fail: AudioStreamPlayer = $Root/AudioFail

var _success: bool = false
var _final_heads: bool = true
var _playing: bool = false

var _tossing: bool = false
var _flip_elapsed: float = 0.0
var _last_half_index: int = 0
var _showing_heads: bool = true

var _root_base_modulate: Color
var _darker_base_modulate: Color
var _glow_base_modulate: Color
var _glow_base_scale: Vector2


func _ready() -> void:
	_root_base_modulate = root.modulate
	_darker_base_modulate = darker.modulate
	_glow_base_modulate = glow.modulate
	_glow_base_scale = glow.scale

	root.visible = false
	_set_alpha(root, 1.0)
	_set_alpha(darker, 0.0)

	glow.visible = false
	_set_alpha(glow, 0.0)

	set_process(false)


func play(success: bool, face: String = "") -> void:
	if _playing:
		return

	_success = success

	var normalized_face := str(face).strip_edges().to_upper()

	if normalized_face == "HEADS":
		_final_heads = true
	elif normalized_face == "TAILS":
		_final_heads = false
	else:
		_final_heads = success

	_playing = true
	call_deferred("_play_sequence")


func _process(delta: float) -> void:
	if not _tossing:
		return

	_flip_elapsed += delta

	var half_duration = max(0.01, flip_half_duration)
	var half_index := int(_flip_elapsed / half_duration)

	if half_index != _last_half_index:
		_last_half_index = half_index
		_showing_heads = not _showing_heads
		_show_face(_showing_heads)

	var phase = fposmod(_flip_elapsed, half_duration) / half_duration
	var edge_amount := sin(phase * PI)
	var sx := lerpf(1.0, min_edge_scale_x, edge_amount)

	coin.scale = Vector2(sx, 1.0)


func _play_sequence() -> void:
	_prepare_visuals()

	_play_audio(audio_flip)

	var move_tween := _start_toss_motion()

	await move_tween.finished

	_tossing = false
	set_process(false)

	_show_face(_final_heads)
	coin.scale = Vector2.ONE

	_play_audio(audio_land)
	await _play_land_bounce()

	await get_tree().create_timer(land_hold_duration).timeout

	if _success:
		await _play_success_result()
	else:
		await _play_fail_result()

	await _play_fade_out()

	root.visible = false
	_playing = false

	emit_signal("finished", _success, _face_name())


func _prepare_visuals() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var center := viewport_size * 0.5 + center_offset
	var start := center + Vector2(0.0, outside_start_y)

	root.visible = true
	root.modulate = _root_base_modulate
	_set_alpha(root, 1.0)

	darker.modulate = _darker_base_modulate
	_set_alpha(darker, 0.0)

	fx_root.position = Vector2.ZERO

	coin_pivot.position = start
	coin_pivot.scale = start_scale
	coin_pivot.rotation = 0.0

	coin.scale = Vector2.ONE
	_showing_heads = true
	_show_face(true)

	glow.visible = false
	glow.scale = _glow_base_scale * 0.75
	glow.modulate = _glow_base_modulate
	_set_alpha(glow, 0.0)

	_flip_elapsed = 0.0
	_last_half_index = 0
	_tossing = true
	set_process(true)


func _start_toss_motion() -> Tween:
	var viewport_size := get_viewport().get_visible_rect().size
	var center := viewport_size * 0.5 + center_offset
	var apex := center + Vector2(0.0, -jump_height)

	var fade_tween := create_tween()
	fade_tween.tween_property(
		darker,
		"modulate:a",
		_darker_base_modulate.a,
		fade_in_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var scale_tween := create_tween()
	scale_tween.tween_property(
		coin_pivot,
		"scale",
		end_scale,
		toss_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var rotation_tween := create_tween()
	rotation_tween.tween_property(
		coin_pivot,
		"rotation",
		TAU * rotation_turns,
		toss_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var move_tween := create_tween()

	move_tween.tween_property(
		coin_pivot,
		"position",
		apex,
		toss_duration * 0.42
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	move_tween.tween_property(
		coin_pivot,
		"position",
		center,
		toss_duration * 0.58
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	return move_tween


func _play_land_bounce() -> void:
	var base_scale := end_scale

	var tween := create_tween()

	tween.tween_property(
		coin_pivot,
		"scale",
		Vector2(base_scale.x * 1.10, base_scale.y * 0.90),
		0.055
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tween.tween_property(
		coin_pivot,
		"scale",
		base_scale,
		0.11
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await tween.finished


func _play_success_result() -> void:
	_play_audio(audio_success)

	glow.visible = true
	glow.scale = _glow_base_scale * 0.70
	_set_alpha(glow, 0.0)

	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(
		glow,
		"modulate:a",
		_glow_base_modulate.a,
		0.18
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tween.tween_property(
		glow,
		"scale",
		_glow_base_scale * success_glow_scale_mult,
		0.24
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	tween.tween_property(
		coin_pivot,
		"scale",
		end_scale * success_coin_scale_mult,
		0.16
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await tween.finished
	await get_tree().create_timer(result_hold_duration).timeout


func _play_fail_result() -> void:
	_play_audio(audio_fail)

	var base_pos := coin_pivot.position

	var tween := create_tween()

	for x in [-7.0, 7.0, -5.0, 5.0, -3.0, 3.0, 0.0]:
		tween.tween_property(
			coin_pivot,
			"position",
			base_pos + Vector2(x, 0.0),
			0.035
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await tween.finished

	coin_pivot.position = base_pos

	await get_tree().create_timer(result_hold_duration * 0.72).timeout


func _play_fade_out() -> void:
	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(
		root,
		"modulate:a",
		0.0,
		fade_out_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	tween.tween_property(
		coin_pivot,
		"scale",
		outro_end_scale,
		fade_out_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await tween.finished


func _show_face(heads: bool) -> void:
	if heads:
		if heads_texture != null:
			coin.texture = heads_texture
	else:
		if tails_texture != null:
			coin.texture = tails_texture


func _face_name() -> String:
	return "HEADS" if _final_heads else "TAILS"


func _play_audio(player: AudioStreamPlayer) -> void:
	if not is_instance_valid(player):
		return
	if player.stream == null:
		return

	player.stop()
	player.play()


func _set_alpha(item: CanvasItem, alpha: float) -> void:
	if not is_instance_valid(item):
		return

	var c := item.modulate
	c.a = alpha
	item.modulate = c
