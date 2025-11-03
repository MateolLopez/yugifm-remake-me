# DuelFlow.gd
extends Node

@export var title_scene: PackedScene
@export var story_scene: PackedScene
@export var reward_scene: PackedScene

var _last_result := ""

func _ready() -> void:
	var bm = $"../BattleManager"
	if bm and not bm.is_connected("duel_over", Callable(self, "_on_duel_over")):
		bm.connect("duel_over", Callable(self, "_on_duel_over"))

func _on_duel_over(result: String):
	_last_result = result
	$"../InputManager".inputs_disabled = true
	$"../EndTurnButton".visible = false
	$"../EndTurnButton".disabled = true
	match result:
		"player_victory":
			_show_victory_panel_then_continue()
		"player_defeat":
			_show_defeat_menu()
		"draw":
			_show_draw_menu()

func _show_victory_panel_then_continue():
	if get_node_or_null("ResultPanel"): return
	var panel = _build_simple_panel("¡Victoria!", ["Continuar"])
	add_child(panel)
	panel.show()

func _show_defeat_menu():
	if get_node_or_null("ResultPanel"): return
	var panel = _build_simple_panel("Derrota", ["Reintentar", "Título"])
	add_child(panel); panel.show()

func _show_draw_menu():
	if get_node_or_null("ResultPanel"): return
	var panel = _build_simple_panel("Empate", ["Reintentar", "Título"])
	add_child(panel); panel.show()

func _build_simple_panel(title: String, buttons: Array) -> Panel:
	var panel := Panel.new()
	panel.name = "ResultPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 16)

	var lbl := Label.new()
	lbl.text = title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 28)
	vb.add_child(lbl)
	vb.add_child(Control.new())

	for btxt in buttons:
		var btn := Button.new()
		btn.text = btxt
		btn.custom_minimum_size = Vector2(220, 48)
		btn.pressed.connect(func():
			match btxt:
				"Continuar": _on_continue_story_pressed()
				"Reintentar": _on_retry_pressed()
				"Título": _on_title_pressed()
		)
		vb.add_child(btn)

	panel.add_child(vb)
	return panel

func _on_continue_story_pressed():
	if _last_result == "player_victory":
		var next_key := str(GameState.current_rules.get("next", ""))
		if next_key != "":
			GameState.current_timeline = next_key
			GameState.save_to_disk()  

		if story_scene:
			get_tree().change_scene_to_packed(story_scene)
		else:
			get_tree().change_scene_to_file("res://scenes/StoryScene.tscn")
	else:
		pass


func _next_timeline_for(result: String) -> String:
	var nexts = GameState.current_rules.get("next", {})
	return str(nexts.get(result, ""))

func _on_retry_pressed():
	get_tree().reload_current_scene()

func _on_title_pressed():
	if title_scene:
		get_tree().change_scene_to_packed(title_scene)
	else:
		get_tree().reload_current_scene()
