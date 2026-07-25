extends Node2D
class_name GenericEffectActivationFx

signal finished

@export_group("Animation")
@export var animation_name: StringName = &"activate"
@export var fallback_duration: float = 0.93
@export var z_offset: int = 200

@export_group("Audio")
@export var wait_for_audio_completion: bool = true

@onready var effect_animation: AnimatedSprite2D = $EffectAnimation
@onready var audio_activation: AudioStreamPlayer = $AudioActivation

var effect_context: Dictionary = {}
var _playing: bool = false
var _finished: bool = false


func _ready() -> void:
	top_level = true
	visible = false

	if is_instance_valid(effect_animation):
		effect_animation.stop()
		effect_animation.frame = 0


func setup_effect_fx(ctx: Dictionary) -> void:
	effect_context = ctx.duplicate(true)

	var source_snapshot = effect_context.get(
		"source_snapshot",
		{}
	)

	if typeof(source_snapshot) != TYPE_DICTIONARY:
		return

	if source_snapshot.has("global_position"):
		global_position = source_snapshot["global_position"]

	z_index = int(
		source_snapshot.get("z_index", 0)
	) + z_offset

func play_effect_fx() -> void:
	if _playing:
		return

	_playing = true
	_finished = false
	visible = true

	if is_instance_valid(audio_activation):
		if audio_activation.stream != null:
			audio_activation.play()

	if not _has_valid_animation():
		await get_tree().create_timer(
			max(0.05, fallback_duration)
		).timeout

		_finish()
		return

	effect_animation.sprite_frames.set_animation_loop(
		animation_name,
		false
	)

	effect_animation.stop()
	effect_animation.frame = 0
	effect_animation.play(animation_name)

	await effect_animation.animation_finished

	_finish()

func _has_valid_animation() -> bool:
	if not is_instance_valid(effect_animation):
		push_warning(
			"GenericEffectActivationFx: EffectAnimation no existe."
		)
		return false

	if effect_animation.sprite_frames == null:
		push_warning(
			"GenericEffectActivationFx: SpriteFrames no asignado."
		)
		return false

	if not effect_animation.sprite_frames.has_animation(
		animation_name
	):
		push_warning(
			"GenericEffectActivationFx: no existe la animación '%s'. Disponibles: %s"
			% [
				String(animation_name),
				str(
					effect_animation.sprite_frames.get_animation_names()
				)
			]
		)
		return false

	if effect_animation.sprite_frames.get_frame_count(
		animation_name
	) <= 0:
		push_warning(
			"GenericEffectActivationFx: la animación '%s' no tiene frames."
			% String(animation_name)
		)
		return false

	return true

func _finish() -> void:
	if _finished:
		return

	_finished = true
	_playing = false
	visible = false

	finished.emit()
