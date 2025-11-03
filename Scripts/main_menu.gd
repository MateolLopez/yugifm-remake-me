extends Control

@export var story_scene: PackedScene
@export var free_duel_scene: PackedScene
@export var deck_edit_scene: PackedScene
@export var options_scene: PackedScene
@onready var confirm_new_game := $confirm_new_game

func _ready():
	GameState.load_from_disk()
	confirm_new_game.visible = false
	confirm_new_game.title = "Iniciar nueva partida"
	confirm_new_game.dialog_text = "Iniciar una nueva partida reiniciará TODO tu progreso, ¿estás seguro de que quieres continuar?"
	confirm_new_game.connect("confirmed", Callable(self, "_on_confirm_new_game"))

func _on_story_pressed():
	GameState.mode = GameState.Mode.STORY
	var tl := GameState.continue_story_fallback_default("ep_1_01")
	GameState.current_timeline = tl
	if GameState.current_episode == "" or GameState.current_episode == null:
		GameState.current_episode = "ep_1_01"

	if story_scene:
		get_tree().change_scene_to_packed(story_scene)
	else:
		get_tree().change_scene_to_file("res://scenes/story_scene.tscn")

func _on_new_game_pressed() -> void:
	confirm_new_game.popup_centered(Vector2(450, 180))

func _on_confirm_new_game() -> void:
	GameState.new_game()
	if story_scene:
		get_tree().change_scene_to_packed(story_scene)
	else:
		get_tree().change_scene_to_file("res://scenes/story_scene.tscn")

func _on_free_duel_pressed():
	GameState.mode = GameState.Mode.FREE_DUEL
	get_tree().change_scene_to_packed(free_duel_scene)

func _on_deck_edit_pressed():
	get_tree().change_scene_to_packed(deck_edit_scene)

func _on_options_pressed():
	get_tree().change_scene_to_packed(options_scene)

func _on_save_pressed():
	GameState.save_to_disk()
