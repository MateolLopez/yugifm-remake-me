extends Node2D

signal finished

@export var animation_name: StringName = &"shine"
@export var fallback_duration: float = 0.45
@export var auto_free: bool = false

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")


func _ready() -> void:
	set_as_top_level(true)


func setup_from_card(card: Node2D) -> void:
	if not is_instance_valid(card):
		return

	var anchor := card.get_node_or_null("AnchorCenter") as Node2D
	if is_instance_valid(anchor):
		global_position = anchor.global_position
	else:
		global_position = card.global_position

	global_rotation = card.global_rotation
	scale = card.scale
	z_index = card.z_index + 180


func play() -> void:
	if sprite == null or sprite.sprite_frames == null:
		await get_tree().create_timer(fallback_duration).timeout
		_finish()
		return

	var anim := animation_name

	if not sprite.sprite_frames.has_animation(anim):
		var names := sprite.sprite_frames.get_animation_names()

		if names.size() > 0:
			anim = names[0]
		else:
			await get_tree().create_timer(fallback_duration).timeout
			_finish()
			return

	sprite.sprite_frames.set_animation_loop(anim, false)

	sprite.visible = true
	sprite.stop()
	sprite.animation = anim
	sprite.frame = 0
	sprite.play(anim)

	await sprite.animation_finished

	_finish()


func _finish() -> void:
	emit_signal("finished")

	if auto_free:
		queue_free()
