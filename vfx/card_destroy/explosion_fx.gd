extends Node2D

signal finished

@export var animation_name: StringName = &"explode"
@export var fallback_duration: float = 0.25
@export var auto_free: bool = false

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var audio: AudioStreamPlayer = get_node_or_null("AudioStreamPlayer")


func play() -> void:
	if audio:
		audio.play()

	if sprite == null:
		await get_tree().create_timer(fallback_duration).timeout
		emit_signal("finished")
		if auto_free:
			queue_free()
		return

	sprite.visible = true

	var anim_to_play: StringName = animation_name

	if sprite.sprite_frames == null:
		await get_tree().create_timer(fallback_duration).timeout
		emit_signal("finished")
		if auto_free:
			queue_free()
		return

	if not sprite.sprite_frames.has_animation(anim_to_play):
		var names := sprite.sprite_frames.get_animation_names()
		if names.size() > 0:
			anim_to_play = names[0]
			push_warning("ExplosionFx: no existe la animación '%s'. Usando '%s'." % [str(animation_name), str(anim_to_play)])
		else:
			await get_tree().create_timer(fallback_duration).timeout
			emit_signal("finished")
			if auto_free:
				queue_free()
			return

	sprite.sprite_frames.set_animation_loop(anim_to_play, false)

	sprite.stop()
	sprite.animation = anim_to_play
	sprite.frame = 0
	sprite.play(anim_to_play)

	await sprite.animation_finished

	emit_signal("finished")

	if auto_free:
		queue_free()
