extends Node2D

@onready var spiral_sprite: Sprite2D = $fusionSpiral 
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	visible = false

func update_fusion_display(fusion_type: String, has_materials: bool) -> void:
	visible = has_materials
	
	if not has_materials:
		return
	
	match fusion_type:
		"generic":
			if spiral_sprite.material is ShaderMaterial:
				(spiral_sprite.material as ShaderMaterial).set_shader_parameter("enabled", false)
		"specific":
			if spiral_sprite.material is ShaderMaterial:
				(spiral_sprite.material as ShaderMaterial).set_shader_parameter("enabled", true)

func play_fusion_animation():
	if animation_player and animation_player.has_animation("fusion_active"):
		animation_player.play("fusion_active")

func stop_fusion_animation():
	if animation_player and animation_player.is_playing():
		animation_player.stop()
