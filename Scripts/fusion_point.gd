extends Node2D

@export var fade_in_duration: float = 0.22
@export var fade_out_duration: float = 0.26
@export var intro_start_scale: float = 0.62
@export var outro_end_scale: float = 0.28

@onready var spiral_sprite: Node2D = get_node_or_null("fusionSpiral")
@onready var animation_player: AnimationPlayer = get_node_or_null("AnimationPlayer")
@onready var fusion_darker: CanvasItem = get_node_or_null("FusionDarker")

var current_fusion_type: String = ""
var _spiral_base_scale: Vector2 = Vector2.ONE
var _spiral_base_modulate: Color = Color.WHITE
var _darker_base_modulate: Color = Color.WHITE
var _transition_tween: Tween = null


func _ready() -> void:
	if is_instance_valid(spiral_sprite):
		_spiral_base_scale = spiral_sprite.scale
		_spiral_base_modulate = spiral_sprite.modulate

	if is_instance_valid(fusion_darker):
		_darker_base_modulate = fusion_darker.modulate

	_force_hidden()
	_ensure_spiral_animation_running()


func update_fusion_display(fusion_type: String, has_materials: bool) -> void:
	# No mostramos el espiral grande al seleccionar materiales.
	current_fusion_type = fusion_type if has_materials else ""


func begin_execution(fusion_type: String) -> void:
	current_fusion_type = fusion_type

	_kill_transition_tween()

	visible = true

	if is_instance_valid(fusion_darker):
		fusion_darker.visible = true
		fusion_darker.modulate = Color(
			_darker_base_modulate.r,
			_darker_base_modulate.g,
			_darker_base_modulate.b,
			0.0
		)

	if is_instance_valid(spiral_sprite):
		spiral_sprite.visible = true
		spiral_sprite.scale = _spiral_base_scale * intro_start_scale
		spiral_sprite.modulate = Color(
			_spiral_base_modulate.r,
			_spiral_base_modulate.g,
			_spiral_base_modulate.b,
			0.0
		)

	_configure_spiral_for_type(fusion_type)
	_ensure_spiral_animation_running()

	_transition_tween = create_tween()
	_transition_tween.set_parallel(true)

	if is_instance_valid(fusion_darker):
		_transition_tween.tween_property(
			fusion_darker,
			"modulate:a",
			_darker_base_modulate.a,
			fade_in_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if is_instance_valid(spiral_sprite):
		_transition_tween.tween_property(
			spiral_sprite,
			"modulate:a",
			_spiral_base_modulate.a,
			fade_in_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

		_transition_tween.tween_property(
			spiral_sprite,
			"scale",
			_spiral_base_scale,
			fade_in_duration
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await _transition_tween.finished
	_transition_tween = null


func end_execution() -> void:
	if not visible:
		_force_hidden()
		return

	_kill_transition_tween()

	_transition_tween = create_tween()
	_transition_tween.set_parallel(true)

	if is_instance_valid(fusion_darker):
		_transition_tween.tween_property(
			fusion_darker,
			"modulate:a",
			0.0,
			fade_out_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	if is_instance_valid(spiral_sprite):
		_transition_tween.tween_property(
			spiral_sprite,
			"modulate:a",
			0.0,
			fade_out_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

		_transition_tween.tween_property(
			spiral_sprite,
			"scale",
			_spiral_base_scale * outro_end_scale,
			fade_out_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await _transition_tween.finished
	_transition_tween = null

	_force_hidden()

	# Importante:
	# No detenemos AnimationPlayer.
	# El espiral puede seguir girando aunque esté invisible.


func force_hidden() -> void:
	_force_hidden()


func get_absorb_center_global() -> Vector2:
	return global_position


func _force_hidden() -> void:
	visible = false
	current_fusion_type = ""

	if is_instance_valid(fusion_darker):
		fusion_darker.visible = false
		fusion_darker.modulate = Color(
			_darker_base_modulate.r,
			_darker_base_modulate.g,
			_darker_base_modulate.b,
			0.0
		)

	if is_instance_valid(spiral_sprite):
		spiral_sprite.visible = false
		spiral_sprite.scale = _spiral_base_scale
		spiral_sprite.modulate = Color(
			_spiral_base_modulate.r,
			_spiral_base_modulate.g,
			_spiral_base_modulate.b,
			0.0
		)


func _kill_transition_tween() -> void:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()

	_transition_tween = null


func _ensure_spiral_animation_running() -> void:
	if animation_player == null:
		return

	if animation_player.has_animation("fusion_active"):
		var anim := animation_player.get_animation("fusion_active")
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR

		if not animation_player.is_playing():
			animation_player.play("fusion_active")


func _configure_spiral_for_type(fusion_type: String) -> void:
	if spiral_sprite == null:
		return

	if spiral_sprite.material is ShaderMaterial:
		var shader := spiral_sprite.material as ShaderMaterial

		match fusion_type:
			"specific":
				shader.set_shader_parameter("enabled", true)
			_:
				shader.set_shader_parameter("enabled", false)
