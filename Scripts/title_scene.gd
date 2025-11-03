extends Control
@export var next_scene: PackedScene

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo():
		get_tree().change_scene_to_packed(next_scene)
