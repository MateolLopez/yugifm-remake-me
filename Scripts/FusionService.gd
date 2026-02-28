extends Node
class_name FusionService

var repo: FusionRepository
var card_scene: PackedScene

func _init(_repo: FusionRepository = null, _card_scene: PackedScene = null) -> void:
	repo = _repo
	card_scene = _card_scene

func find_generic_fusion(card1: Node, card2: Node) -> Node:
	if repo == null:
		return card2
	var t1: Array = _get_tags(card1)
	var t2: Array = _get_tags(card2)
	var a1 := int(card1.get("atk"))
	var a2 := int(card2.get("atk"))
	var candidates: Array = []

	for f in repo.generic_fusions:
		if f is not Dictionary:
			continue
		var req = f.get("required_groups", null)
		if typeof(req) != TYPE_ARRAY or req.size() != 2:
			continue
		var result_id := str(f.get("result_id", ""))
		if result_id == "" or not repo.has_card(result_id):
			continue
		var result_def := repo.get_card_def(result_id)
		var result_atk := int(result_def.get("atk", 0))
		if result_atk <= 0:
			continue
		# Regla: materiales no pueden tener ATK >= al resultado
		if a1 >= result_atk or a2 >= result_atk:
			continue
		if _tags_match_distributed(t1, t2, req):
			candidates.append({
				"result_id": result_id,
				"result_atk": result_atk,
				"priority": float(f.get("priority", 1.0))
			})

	candidates.sort_custom(func(a, b):
		if int(a.result_atk) != int(b.result_atk):
			return int(a.result_atk) < int(b.result_atk)
		return float(a.priority) > float(b.priority)
	)

	if candidates.is_empty():
		return card2
	return _instantiate_card(str(candidates[0].result_id))

func find_specific_fusion(selected_cards: Array) -> Node:
	if repo == null:
		return selected_cards.back() if not selected_cards.is_empty() else null
	var selected_ids: Array = []
	for c in selected_cards:
		if is_instance_valid(c):
			selected_ids.append(str(c.get("id")))
	for f in repo.specific_fusions:
		if f is not Dictionary:
			continue
		var required: Array = f.get("required_ids", [])
		if typeof(required) != TYPE_ARRAY:
			continue
		var exact := bool(f.get("exact_count", true))
		if exact and selected_ids.size() != required.size():
			continue
		if _multiset_matches(selected_ids, required):
			var result_id := str(f.get("result_id", ""))
			if result_id != "" and repo.has_card(result_id):
				return _instantiate_card(result_id)

	return selected_cards.back() if not selected_cards.is_empty() else null

func _instantiate_card(id: String) -> Node:
	if card_scene == null:
		card_scene = preload("res://Scenes/Card.tscn")
	var c = card_scene.instantiate()
	var def := repo.get_card_def(id)
	if def.is_empty():
		c.queue_free()
		return null
	if c.has_method("apply_db"):
		c.apply_db(def)
	c.set("fusion_result", true)
	return c

func _get_tags(card: Node) -> Array:
	var t = card.get("tags")
	return t if typeof(t) == TYPE_ARRAY else []

func _tags_match_distributed(tags1: Array, tags2: Array, required_groups: Array) -> bool:
	var options1: Array = required_groups[0]
	var options2: Array = required_groups[1]
	var case1 := _has_any_tag(tags1, options1) and _has_any_tag(tags2, options2)
	var case2 := _has_any_tag(tags1, options2) and _has_any_tag(tags2, options1)
	return case1 or case2

func _has_any_tag(card_tags: Array, required_options: Array) -> bool:
	for tag in required_options:
		if card_tags.has(tag):
			return true
	return false

func _multiset_matches(selected: Array, required: Array) -> bool:
	var tmp := selected.duplicate()
	for rid in required:
		var i := tmp.find(str(rid))
		if i == -1:
			return false
		tmp.remove_at(i)
	return true
