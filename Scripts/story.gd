extends Node2D

var dlg_handler: Node = null

func _ready() -> void:
	if GameState.current_timeline == "" or GameState.current_timeline == null:
		GameState.current_timeline = "ep_1_01"
	_start_timeline(GameState.current_timeline)

func _start_timeline(tl_name: String) -> void:
	if dlg_handler and is_instance_valid(dlg_handler):
		dlg_handler.queue_free()
		dlg_handler = null

	dlg_handler = Dialogic.start(tl_name, {"parent": self})
	if dlg_handler == null:
		push_error("Dialogic.start() devolvió null para: " + tl_name)
		return

	_connect_end_signals()

func _connect_end_signals() -> void:
	var handler_signal_names := [
		"timeline_ended",
		"timeline_finished",
		"finished",
		"dialogic_end",
		"dialogic_timeline_end"
	]
	for s in handler_signal_names:
		if dlg_handler.has_signal(s):
			if not dlg_handler.is_connected(s, Callable(self, "_on_timeline_end_from_handler")):
				dlg_handler.connect(s, Callable(self, "_on_timeline_end_from_handler"))
			break

	var global_signal_names := [
		"timeline_ended",
		"timeline_finished",
		"finished",
		"dialogic_end",
		"dialogic_timeline_end"
	]
	for s in global_signal_names:
		if Dialogic.has_signal(s):
			if not Dialogic.is_connected(s, Callable(self, "_on_timeline_end_from_singleton")):
				Dialogic.connect(s, Callable(self, "_on_timeline_end_from_singleton"))
			break

func _on_timeline_end_from_handler(_a = null, _b = null) -> void:
	_go_next()

func _on_timeline_end_from_singleton(_a = null, _b = null) -> void:
	_go_next()

func _go_next() -> void:
	if dlg_handler and is_instance_valid(dlg_handler):
		dlg_handler.queue_free()
		dlg_handler = null

	var key := GameState.current_timeline
	if not StoryDB.exists(key):
		push_warning("[Story] Nodo no definido en StoryDB: " + str(key))
		return

	var node := StoryDB.get_node_def(key)
	if node.get("type","") != "timeline":
		push_warning("[Story] Nodo no es timeline: " + str(key))
		return

	var next_key = node.get("next", "")
	if next_key == "":
		print("[Story] Fin de historia: no hay next para ", key)
		return

	_advance_to(next_key)

func _advance_to(next_key: String) -> void:
	if not StoryDB.exists(next_key):
		push_error("[Story] next_key inexistente: " + str(next_key))
		return

	var node := StoryDB.get_node_def(next_key)
	match node.get("type",""):
		"timeline":
			GameState.current_timeline = next_key
			GameState.save_to_disk()
			_start_timeline(next_key)

		"duel":
			GameState.current_opponent_id = node.get("opponent", "")
			GameState.set_duel_route(node.get("next",""), true, "")
			GameState.save_to_disk()
			get_tree().change_scene_to_file("res://scenes/DuelLoader.tscn")

		_:
			push_warning("[Story] Tipo desconocido: " + str(node.get("type","")))
