extends Node
class_name FusionService

const GENERIC_FUSION_MIN_ATK_GAIN := 249

var repo: FusionRepository
var card_scene: PackedScene


func _init(_repo: FusionRepository = null, _card_scene: PackedScene = null) -> void:
	repo = _repo
	card_scene = _card_scene


func find_generic_fusion(card1: Node, card2: Node) -> Node:
	if repo == null:
		return card2

	if not is_instance_valid(card1) or not is_instance_valid(card2):
		return card2

	var t1: Array = _get_tags(card1)
	var t2: Array = _get_tags(card2)

	var a1 := _to_int(card1.get("atk"))
	var a2 := _to_int(card2.get("atk"))
	var highest_material_atk = max(a1, a2)

	var candidates: Array = []

	for f in repo.generic_fusions:
		if f is not Dictionary:
			continue

		var req = f.get("required_groups", null)
		if typeof(req) != TYPE_ARRAY or req.size() != 2:
			continue

		var result_id := str(f.get("result_id", "")).strip_edges()
		if result_id == "" or not repo.has_card(result_id):
			continue

		var result_def := repo.get_card_def(result_id)
		var result_atk := _to_int(result_def.get("atk", 0))

		if result_atk <= 0:
			continue

		# Regla de FM-like:
		# El resultado debe superar al material de mayor ATK por al menos X.
		# Si querés exigir 250 exacto, cambiá la constante a 250.
		if result_atk < highest_material_atk + GENERIC_FUSION_MIN_ATK_GAIN:
			continue

		if _groups_match_distributed(t1, t2, req):
			candidates.append({
				"result_id": result_id,
				"result_atk": result_atk,
				"priority": float(f.get("priority", 1.0)),
				"fusion_id": str(f.get("fusion_id", ""))
			})

	candidates.sort_custom(func(a, b):
		var atk_a := int(a.get("result_atk", 0))
		var atk_b := int(b.get("result_atk", 0))

		if atk_a != atk_b:
			return atk_a < atk_b

		var priority_a := float(a.get("priority", 1.0))
		var priority_b := float(b.get("priority", 1.0))

		if priority_a != priority_b:
			return priority_a > priority_b

		return str(a.get("fusion_id", "")) < str(b.get("fusion_id", ""))
	)

	if candidates.is_empty():
		return card2

	return _instantiate_card(str(candidates[0].get("result_id", "")))


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
			var result_id := str(f.get("result_id", "")).strip_edges()

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


func _groups_match_distributed(tags1: Array, tags2: Array, required_groups: Array) -> bool:
	if required_groups.size() != 2:
		return false

	var group_a = required_groups[0]
	var group_b = required_groups[1]

	var case1 := _group_matches(tags1, group_a) and _group_matches(tags2, group_b)
	var case2 := _group_matches(tags1, group_b) and _group_matches(tags2, group_a)

	return case1 or case2


func _group_matches(card_tags: Array, group_spec) -> bool:
	var normalized_tags := _normalize_tag_array(card_tags)

	match typeof(group_spec):
		TYPE_ARRAY:
			return _array_group_matches(normalized_tags, group_spec)

		TYPE_DICTIONARY:
			return _dictionary_group_matches(normalized_tags, group_spec)

		TYPE_STRING:
			return normalized_tags.has(str(group_spec).strip_edges().to_lower())

		_:
			return false


func _array_group_matches(card_tags: Array, group_spec: Array) -> bool:
	if group_spec.is_empty():
		return false

	var contains_subgroups := false

	for item in group_spec:
		if typeof(item) == TYPE_ARRAY:
			contains_subgroups = true
			break

	# Compatibilidad nueva opcional:
	# [["fiend","dark"], ["fiend","red-eyes"]]
	# significa: cumplir todos los tags de cualquiera de esos subgrupos.
	if contains_subgroups:
		for subgroup in group_spec:
			if typeof(subgroup) != TYPE_ARRAY:
				continue

			if _has_all_tags(card_tags, subgroup):
				return true

		return false

	# Compatibilidad vieja:
	# ["dragon","snake","sea-serpent"]
	# significa dragon OR snake OR sea-serpent.
	return _has_any_tag(card_tags, group_spec)


func _dictionary_group_matches(card_tags: Array, group_spec: Dictionary) -> bool:
	var checked_any_rule := false
	var ok := true

	if group_spec.has("any"):
		checked_any_rule = true
		ok = ok and _has_any_tag(card_tags, _ensure_array(group_spec.get("any", [])))

	if group_spec.has("all"):
		checked_any_rule = true
		ok = ok and _has_all_tags(card_tags, _ensure_array(group_spec.get("all", [])))

	if group_spec.has("any_of_all"):
		checked_any_rule = true
		ok = ok and _matches_any_all_group(card_tags, _ensure_array(group_spec.get("any_of_all", [])))

	if not checked_any_rule:
		return false

	return ok


func _matches_any_all_group(card_tags: Array, groups: Array) -> bool:
	for group in groups:
		if typeof(group) != TYPE_ARRAY:
			continue

		if _has_all_tags(card_tags, group):
			return true

	return false


func _has_any_tag(card_tags: Array, required_options: Array) -> bool:
	var normalized_required := _normalize_tag_array(required_options)

	for tag in normalized_required:
		if card_tags.has(tag):
			return true

	return false


func _has_all_tags(card_tags: Array, required_tags: Array) -> bool:
	var normalized_required := _normalize_tag_array(required_tags)

	if normalized_required.is_empty():
		return false

	for tag in normalized_required:
		if not card_tags.has(tag):
			return false

	return true


func _normalize_tag_array(values: Array) -> Array:
	var result: Array = []

	for v in values:
		var s := str(v).strip_edges().to_lower()

		if s != "" and not result.has(s):
			result.append(s)

	return result


func _ensure_array(value) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value

	if value == null:
		return []

	return [value]


func _get_tags(card: Node) -> Array:
	if not is_instance_valid(card):
		return []

	var t = card.get("tags")
	if typeof(t) != TYPE_ARRAY:
		return []

	return _normalize_tag_array(t)


func _multiset_matches(selected: Array, required: Array) -> bool:
	var tmp := selected.duplicate()

	for rid in required:
		var i := tmp.find(str(rid))

		if i == -1:
			return false

		tmp.remove_at(i)

	return true


func _to_int(v) -> int:
	if v == null:
		return 0

	if typeof(v) == TYPE_INT:
		return v

	if typeof(v) == TYPE_FLOAT:
		return int(v)

	return str(v).to_int()
