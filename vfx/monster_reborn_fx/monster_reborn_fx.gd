extends Node2D

signal finished

@export var effect_size_multiplier: float = 1.20
@export var total_duration: float = 2.0
@export var fade_in_duration: float = 0.25
@export var fade_out_duration: float = 0.75
@export var white_card_default_size: Vector2 = Vector2(329, 479)
@export var white_card_start_scale: float = 0.94
@export var white_card_hold_scale: float = 1.02
@export var white_card_end_scale: float = 1.08
@export var heat_amplitude: float = 4.0
@export var heat_strips: int = 48
@export var auto_free: bool = false
@export var edge_softness: float = 0.18
@export var heat_speed: float = 8.0
@export var heat_frequency: float = 24.0
@export var horizontal_edge_columns: int = 10

@onready var audio: AudioStreamPlayer = get_node_or_null("AudioStreamPlayer")

var target_card: Node2D = null
var target_original_modulate: Color = Color.WHITE

var _card_size: Vector2 = Vector2.ZERO
var _white_alpha: float = 0.0
var _white_scale: float = 1.0
var _heat_time: float = 0.0
var _playing: bool = false


func _ready() -> void:
	set_as_top_level(true)
	visible = false
	modulate = Color.WHITE


func _process(delta: float) -> void:
	if not _playing:
		return

	_heat_time += delta
	queue_redraw()


func setup_from_card(card: Node2D, forced_size: Vector2 = Vector2.ZERO) -> void:
	if not is_instance_valid(card):
		return

	target_card = card
	target_original_modulate = card.modulate

	_card_size = forced_size
	if _card_size == Vector2.ZERO:
		_card_size = _guess_card_visual_size(card)

	if _card_size.x <= 0.0 or _card_size.y <= 0.0:
		_card_size = white_card_default_size

	var anchor := card.get_node_or_null("AnchorCenter") as Node2D
	if is_instance_valid(anchor):
		global_transform = anchor.global_transform
	else:
		global_transform = card.global_transform

	z_index = card.z_index + 120

	target_card.modulate = Color(
		target_original_modulate.r,
		target_original_modulate.g,
		target_original_modulate.b,
		0.0
	)

	_white_alpha = 0.0
	_white_scale = white_card_start_scale
	visible = true
	queue_redraw()


func play() -> void:
	_playing = true
	visible = true

	if audio:
		audio.play()

	if not is_instance_valid(target_card):
		await get_tree().create_timer(total_duration).timeout
		_finish()
		return

	var hold_duration: float = max(0.0, total_duration - fade_in_duration - fade_out_duration)

	var tw_in := get_tree().create_tween()
	tw_in.set_parallel(true)
	tw_in.tween_method(_set_white_alpha, 0.0, 1.0, fade_in_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw_in.tween_method(_set_white_scale, white_card_start_scale, 1.0, fade_in_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw_in.finished

	if hold_duration > 0.0:
		var tw_hold := get_tree().create_tween()
		tw_hold.tween_method(_set_white_scale, 1.0, white_card_hold_scale, hold_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tw_hold.finished

	var tw_out := get_tree().create_tween()
	tw_out.set_parallel(true)

	tw_out.tween_method(_set_white_alpha, 1.0, 0.0, fade_out_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw_out.tween_method(_set_white_scale, white_card_hold_scale, white_card_end_scale, fade_out_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if is_instance_valid(target_card):
		target_card.modulate = Color(
			target_original_modulate.r,
			target_original_modulate.g,
			target_original_modulate.b,
			0.0
		)
		tw_out.tween_property(target_card, "modulate:a", target_original_modulate.a, fade_out_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await tw_out.finished

	if is_instance_valid(target_card):
		target_card.modulate = target_original_modulate

	_finish()


func _finish() -> void:
	_playing = false
	_white_alpha = 0.0
	visible = false
	queue_redraw()

	emit_signal("finished")

	if auto_free:
		queue_free()


func _set_white_alpha(value: float) -> void:
	_white_alpha = clampf(value, 0.0, 1.0)
	queue_redraw()


func _set_white_scale(value: float) -> void:
	_white_scale = value
	queue_redraw()

func _draw() -> void:
	if _white_alpha <= 0.0:
		return

	var rows: int = max(8, heat_strips)
	var cols: int = 32

	var scaled_size := _card_size * effect_size_multiplier * _white_scale
	var half := scaled_size * 0.5

	var cell_h := scaled_size.y / float(rows)
	var cell_w := scaled_size.x / float(cols)

	var edge_softness := 0.18
	var heat_speed := 8.0
	var heat_frequency := 24.0

	for y_i in range(rows):
		var y0 := -half.y + cell_h * float(y_i)
		var y1 := -half.y + cell_h * float(y_i + 1)

		var ty0 := float(y_i) / float(rows)
		var ty1 := float(y_i + 1) / float(rows)
		var ty_mid := (float(y_i) + 0.5) / float(rows)

		var wave0 := sin((_heat_time * heat_speed) + ty0 * heat_frequency) * heat_amplitude
		var wave1 := sin((_heat_time * heat_speed) + ty1 * heat_frequency) * heat_amplitude

		var vertical_fade = min(
			smoothstep(0.0, edge_softness, ty_mid),
			smoothstep(0.0, edge_softness, 1.0 - ty_mid)
		)

		for x_i in range(cols):
			var x0 := -half.x + cell_w * float(x_i)
			var x1 := -half.x + cell_w * float(x_i + 1)

			var tx_mid := (float(x_i) + 0.5) / float(cols)

			var horizontal_fade = min(
				smoothstep(0.0, edge_softness, tx_mid),
				smoothstep(0.0, edge_softness, 1.0 - tx_mid)
			)

			var edge_fade = min(vertical_fade, horizontal_fade)
			var alpha = _white_alpha * edge_fade

			if alpha <= 0.01:
				continue

			var col := Color(1, 1, 1, alpha)

			draw_colored_polygon(
				PackedVector2Array([
					Vector2(x0 + wave0, y0),
					Vector2(x1 + wave0, y0),
					Vector2(x1 + wave1, y1),
					Vector2(x0 + wave1, y1)
				]),
				col
			)

func _guess_card_visual_size(card: Node2D) -> Vector2:
	if not is_instance_valid(card):
		return white_card_default_size

	var anchor := card.get_node_or_null("AnchorCenter") as Node2D
	if is_instance_valid(anchor):
		var anchor_local := card.to_local(anchor.global_position)

		if anchor_local.x > 0.0 and anchor_local.y > 0.0:
			return anchor_local * 2.0

	var card_back := card.get_node_or_null("CardBack")
	if card_back is TextureRect:
		return (card_back as TextureRect).size

	if card_back is Sprite2D:
		var spr := card_back as Sprite2D
		if spr.texture:
			return spr.texture.get_size()

	var front := card.get_node_or_null("CardFront")
	if front is TextureRect:
		return (front as TextureRect).size

	if front is Sprite2D:
		var spr2 := front as Sprite2D
		if spr2.texture:
			return spr2.texture.get_size()

	return white_card_default_size
