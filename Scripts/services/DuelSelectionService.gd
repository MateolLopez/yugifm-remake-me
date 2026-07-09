extends Node
class_name DuelSelectionService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null

var card_selection_active: bool = false
var _selection_candidates: Array = []
var _selection_on_selected: Callable = Callable()
var _selection_options: Dictionary = {}

var _selection_prompt_layer: CanvasLayer = null
var _selection_prompt_root: Control = null
var _selection_prompt_label: Label = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service

func _runtime_card_has_tag(card: Node, tag: String) -> bool:
	if not is_instance_valid(card):
		return false

	tag = str(tag).strip_edges().to_lower()

	if tag == "":
		return true

	if not ("tags" in card):
		return false

	if typeof(card.tags) != TYPE_ARRAY:
		return false

	for t in card.tags:
		if str(t).strip_edges().to_lower() == tag:
			return true

	return false

func _runtime_card_has_any_excluded_tag(card: Node, exclude_tags: Array) -> bool:
	for tag in exclude_tags:
		if _runtime_card_has_tag(card, str(tag)):
			return true

	return false

func _runtime_monster_matches_filters(card: Node, filters: Dictionary, exclude_tags: Array = []) -> bool:
	if not is_instance_valid(card):
		return false

	if card_runtime_service._card_kind(card) != "MONSTER":
		return false

	if _runtime_card_has_any_excluded_tag(card, exclude_tags):
		return false

	var filter_id := str(filters.get("id", "")).strip_edges()
	var filter_tag := str(filters.get("tag", "")).strip_edges().to_lower()
	var filter_attribute := str(filters.get("attribute", "")).strip_edges().to_upper()
	var filter_race := str(filters.get("race", "")).strip_edges().to_upper()

	var min_level = filters.get("min_level", null)
	var max_level = filters.get("max_level", null)
	var min_atk = filters.get("min_atk", null)
	var max_atk = filters.get("max_atk", null)
	var min_def = filters.get("min_def", null)
	var max_def = filters.get("max_def", null)

	if filter_id != "" and ("id" in card) and str(card.id) != filter_id:
		return false

	if filter_tag != "" and not _runtime_card_has_tag(card, filter_tag):
		return false

	if filter_attribute != "":
		var attr := ""
		if card.has_method("get_effective_attribute"):
			attr = str(card.get_effective_attribute()).to_upper()
		elif "attribute" in card:
			attr = str(card.attribute).to_upper()

		if attr != filter_attribute:
			return false

	if filter_race != "":
		var race := ""
		if card.has_method("get_effective_race"):
			race = str(card.get_effective_race()).to_upper()
		elif "race" in card:
			race = str(card.race).to_upper()

		if race != filter_race:
			return false

	var lv := 0
	if card.has_method("get_effective_level"):
		lv = int(card.get_effective_level())
	elif "level" in card:
		lv = int(card.level)

	var atk_value := 0
	if card.has_method("get_effective_atk"):
		atk_value = int(card.get_effective_atk())
	elif "atk" in card:
		atk_value = int(card.atk)

	var def_value := 0
	if card.has_method("get_effective_def"):
		def_value = int(card.get_effective_def())
	elif "def" in card:
		def_value = int(card.def)

	if min_level != null and lv < int(min_level):
		return false

	if max_level != null and lv > int(max_level):
		return false

	if min_atk != null and atk_value < int(min_atk):
		return false

	if max_atk != null and atk_value > int(max_atk):
		return false

	if min_def != null and def_value < int(min_def):
		return false

	if max_def != null and def_value > int(max_def):
		return false

	return true

func _find_first_controlled_monster(owner: String, filters: Dictionary, exclude_tags: Array = []) -> Node:
	owner = card_runtime_service._norm_owner(owner)

	var cards: Array = []

	if owner == "Player":
		cards = bm.player_cards_on_battlefield.duplicate()
	elif owner == "Opponent":
		cards = bm.opponent_cards_on_battlefield.duplicate()
	else:
		return null

	for card in cards:
		if _runtime_monster_matches_filters(card, filters, exclude_tags):
			return card

	return null

func is_selecting_card() -> bool:
	return card_selection_active


func start_card_selection(candidates: Array, on_selected: Callable, options: Dictionary = {}) -> bool:
	_clear_card_selection_visuals()

	_selection_candidates.clear()

	for card in candidates:
		if is_instance_valid(card):
			_selection_candidates.append(card)

	if _selection_candidates.is_empty():
		return false

	if not on_selected.is_valid():
		return false

	card_selection_active = true
	_selection_on_selected = on_selected
	_selection_options = options.duplicate(true)

	_apply_card_selection_visuals()
	_show_selection_prompt(str(_selection_options.get("prompt", "Selecciona una carta.")))

	return true


func try_receive_card_selection(card: Node) -> bool:
	if not card_selection_active:
		return false

	if not is_instance_valid(card):
		return false

	if not _selection_candidates.has(card):
		return false

	var callback := _selection_on_selected

	_clear_card_selection_state()

	if callback.is_valid():
		callback.call(card)

	return true


func cancel_card_selection() -> void:
	if not card_selection_active:
		return

	var on_cancel = _selection_options.get("on_cancel", Callable())

	_clear_card_selection_state()

	if on_cancel is Callable and on_cancel.is_valid():
		on_cancel.call()

func _apply_card_selection_visuals() -> void:
	for card in _selection_candidates:
		if not is_instance_valid(card):
			continue

		if not card.has_meta("selection_prev_modulate"):
			card.set_meta("selection_prev_modulate", card.modulate)

		if not card.has_meta("selection_prev_z_index"):
			card.set_meta("selection_prev_z_index", card.z_index)

		card.modulate = Color(1.35, 1.35, 1.35, 1.0)
		card.z_index = card.z_index + 200


func _clear_card_selection_visuals() -> void:
	for card in _selection_candidates:
		if not is_instance_valid(card):
			continue

		if card.has_meta("selection_prev_modulate"):
			card.modulate = card.get_meta("selection_prev_modulate")
			card.remove_meta("selection_prev_modulate")

		if card.has_meta("selection_prev_z_index"):
			card.z_index = int(card.get_meta("selection_prev_z_index"))
			card.remove_meta("selection_prev_z_index")

func _clear_card_selection_state() -> void:
	_clear_card_selection_visuals()
	_hide_selection_prompt()

	card_selection_active = false
	_selection_candidates.clear()
	_selection_on_selected = Callable()
	_selection_options.clear()

func is_current_selection_cancelable() -> bool:
	return bool(_selection_options.get("cancelable", true))

func _show_selection_prompt(text: String) -> void:
	_hide_selection_prompt()

	_selection_prompt_layer = CanvasLayer.new()
	_selection_prompt_layer.name = "SelectionPromptLayer"
	_selection_prompt_layer.layer = 80
	add_child(_selection_prompt_layer)

	_selection_prompt_root = Control.new()
	_selection_prompt_root.name = "SelectionPromptRoot"
	_selection_prompt_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_selection_prompt_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_prompt_layer.add_child(_selection_prompt_root)

	var panel := PanelContainer.new()
	panel.name = "SelectionPromptPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(420, 54)

	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -210
	panel.offset_right = 210
	panel.offset_top = 24
	panel.offset_bottom = 78

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.82)
	style.border_color = Color(1.0, 1.0, 1.0, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	_selection_prompt_root.add_child(panel)

	_selection_prompt_label = Label.new()
	_selection_prompt_label.name = "SelectionPromptLabel"
	_selection_prompt_label.text = text
	_selection_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selection_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_selection_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selection_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_prompt_label.add_theme_font_size_override("font_size", 20)

	panel.add_child(_selection_prompt_label)


func _hide_selection_prompt() -> void:
	if is_instance_valid(_selection_prompt_layer):
		_selection_prompt_layer.queue_free()

	_selection_prompt_layer = null
	_selection_prompt_root = null
	_selection_prompt_label = null
