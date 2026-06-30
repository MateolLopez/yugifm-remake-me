extends Node
class_name DuelSummonService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null
var graveyard_service: DuelGraveyardService = null
var reveal_service: DuelRevealService = null
var card_db_service: DuelCardDbService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service
	graveyard_service = bm.graveyard_service
	reveal_service = bm.reveal_service
	card_db_service = bm.card_db_service

func _get_db_monster_pool(filters: Dictionary, exclude_ids: Array = [], exclude_tags: Array = []) -> Array:
	var out := []
	var db: Array = card_db_service._get_cards_db()

	var excluded_ids: Array = []
	for id_value in exclude_ids:
		excluded_ids.append(str(id_value))

	for card_def in db:
		if typeof(card_def) != TYPE_DICTIONARY:
			continue

		if not card_db_service._db_card_matches_filters(card_def, filters):
			continue

		var card_id := str(card_def.get("id", ""))

		if excluded_ids.has(card_id):
			continue

		if card_db_service._db_card_has_any_excluded_tag(card_def, exclude_tags):
			continue

		out.append(card_def)

	return out

func _pick_db_card_from_pool(pool: Array, pick_mode: String = "RANDOM") -> Dictionary:
	if pool.is_empty():
		return {}

	pick_mode = str(pick_mode).to_upper()

	match pick_mode:
		"FIRST":
			return pool[0]

		"HIGHEST_LEVEL":
			pool.sort_custom(func(a, b):
				return int(a.get("level", 0)) > int(b.get("level", 0))
			)
			return pool[0]

		"LOWEST_LEVEL":
			pool.sort_custom(func(a, b):
				return int(a.get("level", 0)) < int(b.get("level", 0))
			)
			return pool[0]

		"HIGHEST_ATK":
			pool.sort_custom(func(a, b):
				return int(a.get("atk", 0)) > int(b.get("atk", 0))
			)
			return pool[0]

		"LOWEST_ATK":
			pool.sort_custom(func(a, b):
				return int(a.get("atk", 0)) < int(b.get("atk", 0))
			)
			return pool[0]

		_:
			return pool.pick_random()

func _apply_summoned_card_position(card: Node, position: String) -> void:
	if not is_instance_valid(card):
		return

	position = str(position).to_upper()

	match position:
		"FACEUP_DEF":
			card_runtime_service._set_card_face_down(card, false)

			if card.has_method("set_defense_position"):
				card.set_defense_position(true)
			elif "in_defense" in card:
				card.in_defense = true

			reveal_service.reveal_card(card)

		"FACEDOWN_DEF":
			card_runtime_service._set_card_face_down(card, true)

			if card.has_method("set_defense_position"):
				card.set_defense_position(true)
			elif "in_defense" in card:
				card.in_defense = true

		_:
			card_runtime_service._set_card_face_down(card, false)

			if card.has_method("set_defense_position"):
				card.set_defense_position(false)
			elif "in_defense" in card:
				card.in_defense = false

			reveal_service.reveal_card(card)

func _summon_db_monster_def_to_slot(
	card_def: Dictionary,
	owner: String,
	slot: Node2D,
	position: String,
	effect_source: Node,
	summon_type: String = "EFFECT"
) -> Node:
	if card_def.is_empty():
		return null

	if not is_instance_valid(slot):
		return null

	owner = card_runtime_service._norm_owner(owner)

	if owner == "":
		return null

	if str(card_def.get("kind", "")).to_upper() != "MONSTER":
		return null

	var card = card_db_service._spawn_card_from_db_entry(card_def, owner)

	if not is_instance_valid(card):
		return null

	card.set_meta("played_from_hand", false)
	card.owner_side = "PLAYER" if owner == "Player" else "OPPONENT"

	if card.has_method("set_show_back_only"):
		card.set_show_back_only(false)

	if card.has_method("apply_owner_collision_layers"):
		card.apply_owner_collision_layers()

	_apply_summoned_card_position(card, position)

	zone_service._place_card_in_slot(card, slot, "EFFECT")

	event_service._emit_duel_event("ON_SUMMON_BY_EFFECT", {
		"battle_manager": bm,
		"source": effect_source,
		"summoned": card,
		"controller": owner,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
		"summon_type": summon_type
	})

	return card

func summon_multiple_monsters_from_db(
	owner: String,
	filters: Dictionary,
	max_count: int = 1,
	position: String = "FACEUP_ATK",
	effect_source: Node = null,
	summon_type: String = "EFFECT",
	exclude_ids: Array = [],
	exclude_tags: Array = [],
	pick_mode: String = "RANDOM",
	allow_repeats: bool = true
) -> Array:
	owner = card_runtime_service._norm_owner(owner)

	if owner == "":
		return []

	max_count = max(1, max_count)

	var pool := _get_db_monster_pool(filters, exclude_ids, exclude_tags)

	if pool.is_empty():
		return []

	var summoned: Array = []

	while summoned.size() < max_count:
		var free_slot = zone_service._get_free_monster_slot_for(owner)

		if free_slot == null:
			break

		if pool.is_empty():
			break

		var picked := _pick_db_card_from_pool(pool, pick_mode)

		if picked.is_empty():
			break

		var card := _summon_db_monster_def_to_slot(
			picked,
			owner,
			free_slot,
			position,
			effect_source,
			summon_type
		)

		if not is_instance_valid(card):
			break

		summoned.append(card)

		if not allow_repeats:
			var picked_id := str(picked.get("id", ""))

			for i in range(pool.size() - 1, -1, -1):
				if str(pool[i].get("id", "")) == picked_id:
					pool.remove_at(i)

	return summoned

func activate_sacrifice_self_to_summon_temporary_token_copies(source_card: Node, ctx: Dictionary, params: Dictionary) -> bool:
	if not is_instance_valid(source_card):
		return false

	var source_controller := card_runtime_service._norm_owner(ctx.get("controller", ""))

	if source_controller == "" and "owner_side" in source_card:
		source_controller = "Player" if str(source_card.owner_side).to_upper() == "PLAYER" else "Opponent"

	source_controller = card_runtime_service._norm_owner(source_controller)

	if source_controller == "":
		return false

	var controller_param := str(params.get("controller", "SELF")).to_upper()
	var token_controller := source_controller

	if controller_param == "OPPONENT":
		token_controller = card_runtime_service._opponent_of(source_controller)
	elif controller_param == "SELF":
		token_controller = source_controller

	token_controller = card_runtime_service._norm_owner(token_controller)

	if token_controller == "":
		return false

	if zone_service._owner_of(source_card) != token_controller:
		return false

	if card_runtime_service._card_kind(source_card) != "MONSTER":
		return false

	if not source_card.is_on_field():
		return false

	var max_tokens = max(1, int(params.get("max_tokens", 5)))
	var token_snapshot = _make_token_snapshot_from_source(source_card, params)

	var cost_ctx := ctx.duplicate(true)
	cost_ctx["effect_cost_source"] = source_card
	cost_ctx["activation_type"] = "MONSTER_EFFECT"

	if not graveyard_service._send_monster_to_graveyard_as_cost(source_card, token_controller, cost_ctx):
		return false

	var summoned := 0
	var due_owner := card_runtime_service._opponent_of(token_controller)

	while summoned < max_tokens:
		var free_slot := zone_service._get_free_monster_slot_for(token_controller)

		if free_slot == null:
			break

		var token = _spawn_temporary_token_from_snapshot(token_snapshot, token_controller, free_slot, params, due_owner)

		if not is_instance_valid(token):
			break

		summoned += 1

	return summoned > 0

func _make_token_snapshot_from_source(source_card: Node, params: Dictionary) -> Dictionary:
	var snapshot := {
		"id": str(params.get("token_id", "")),
		"art_id": "",
		"cardname": str(params.get("token_name", "Token")),
		"kind": "MONSTER",
		"attribute": "DARK",
		"race": "Fiend",
		"level": 1,
		"atk": 0,
		"def": 0,
		"guardian_star": [],
		"tags": [],
		"keywords": [],
		"description": ""
	}

	if bool(params.get("copy_attribute", true)) and "attribute" in source_card:
		snapshot["attribute"] = str(source_card.attribute)

	if bool(params.get("copy_race", true)) and "race" in source_card:
		snapshot["race"] = str(source_card.race)

	if bool(params.get("copy_level", true)) and "level" in source_card:
		snapshot["level"] = int(source_card.level)

	if bool(params.get("copy_atk", true)) and "atk" in source_card:
		snapshot["atk"] = int(source_card.atk)

	if bool(params.get("copy_def", true)) and "def" in source_card:
		snapshot["def"] = int(source_card.def)

	if bool(params.get("copy_guardian_star", true)) and "guardian_star" in source_card and typeof(source_card.guardian_star) == TYPE_ARRAY:
		snapshot["guardian_star"] = source_card.guardian_star.duplicate()

	var token_tags = params.get("token_tags", [])

	if typeof(token_tags) == TYPE_ARRAY:
		snapshot["tags"] = token_tags.duplicate()
	elif "tags" in source_card and typeof(source_card.tags) == TYPE_ARRAY:
		snapshot["tags"] = source_card.tags.duplicate()
	else:
		snapshot["tags"] = ["token"]

	if not (snapshot["tags"] as Array).has("token"):
		(snapshot["tags"] as Array).append("token")

	if bool(params.get("copy_keywords", false)) and "keywords" in source_card and typeof(source_card.keywords) == TYPE_ARRAY:
		snapshot["keywords"] = source_card.keywords.duplicate()
	else:
		snapshot["keywords"] = []

	if bool(params.get("copy_art", true)):
		if "id" in source_card:
			snapshot["art_id"] = str(source_card.id)

	return snapshot

func _spawn_temporary_token_from_snapshot(
	snapshot: Dictionary,
	controller: String,
	free_slot: Node2D,
	params: Dictionary,
	due_turn_end_owner: String
) -> Node:
	if not is_instance_valid(free_slot):
		return null

	var card_scene: PackedScene = preload("res://Scenes/Card.tscn")
	var token: Card = card_scene.instantiate()

	if not is_instance_valid(token):
		return null

	get_tree().current_scene.add_child(token)

	token.kind = "MONSTER"
	token.id = str(snapshot.get("id", ""))
	token.art_id_override = str(snapshot.get("art_id", ""))
	token.cardname = str(snapshot.get("cardname", "Token"))
	token.attribute = str(snapshot.get("attribute", "DARK"))
	token.race = str(snapshot.get("race", "Fiend"))
	token.level = int(snapshot.get("level", 1))
	token.atk = int(snapshot.get("atk", 0))
	token.def = int(snapshot.get("def", 0))

	var gs = snapshot.get("guardian_star", [])
	if typeof(gs) == TYPE_ARRAY:
		token.guardian_star = gs.duplicate()
	else:
		token.guardian_star = []

	var tags = snapshot.get("tags", ["token"])
	if typeof(tags) == TYPE_ARRAY:
		token.tags = tags.duplicate()
	else:
		token.tags = ["token"]

	var keywords = snapshot.get("keywords", [])
	if typeof(keywords) == TYPE_ARRAY:
		token.keywords = keywords.duplicate()
	else:
		token.keywords = []

	token.effects = []
	token.description = ""

	if token.has_method("_update_visuals"):
		token._update_visuals()

	token.set_meta("is_token", true)
	token.set_meta("temporary_token", true)
	token.set_meta("destroy_token_at_opponent_turn_end", bool(params.get("destroy_at_opponent_turn_end", true)))

	if bool(params.get("destroy_at_opponent_turn_end", true)):
		token.set_meta("scheduled_destruction", {
			"due_turn_end_owner": due_turn_end_owner
		})

	token.owner_side = "PLAYER" if card_runtime_service._norm_owner(controller) == "Player" else "OPPONENT"

	if token.has_method("set_show_back_only"):
		token.set_show_back_only(false)

	card_runtime_service._set_card_face_down(token, false)

	var position := str(params.get("position", "FACEUP_DEF")).to_upper()

	if position == "FACEUP_ATK":
		if token.has_method("set_defense_position"):
			token.set_defense_position(false)
		else:
			token.in_defense = false
	else:
		if token.has_method("set_defense_position"):
			token.set_defense_position(true)
		else:
			token.in_defense = true

	if token.has_method("apply_owner_collision_layers"):
		token.apply_owner_collision_layers()

	zone_service._set_card_slot(token, free_slot)
	zone_service._place_card_in_slot(token, free_slot, "EFFECT")

	if position == "FACEUP_ATK" or position == "FACEUP_DEF":
		reveal_service.reveal_card(token)

	event_service._emit_duel_event("ON_SUMMON_BY_EFFECT", {
		"battle_manager": bm,
		"source": token,
		"summoned": token,
		"controller": card_runtime_service._norm_owner(controller),
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
		"summon_type": "TOKEN",
		"temporary_token": true
	})

	return token

func summon_token_from_source_basestats(source_card, params: Dictionary, ctx: Dictionary = {}) -> void:
	if not is_instance_valid(source_card):
		return

	var controller := ""
	if ctx is Dictionary and ctx.has("controller"):
		controller = card_runtime_service._norm_owner(ctx["controller"])
	else:
		controller = card_runtime_service._norm_owner(zone_service._owner_of(source_card))

	var slots_root := $"../../CardSlots" if controller == "Player" else $"../../CardSlotsRival"
	if not is_instance_valid(slots_root):
		return

	var free_slot: Node2D = null
	for s in slots_root.get_children():
		if not is_instance_valid(s):
			continue
		if str(s.get("card_slot_type")) != "Monster":
			continue
		if bool(s.get("card_in_slot")):
			continue
		free_slot = s
		break

	if free_slot == null:
		return

	var card_scene: PackedScene = preload("res://Scenes/Card.tscn")
	var token: Card = card_scene.instantiate()
	if not is_instance_valid(token):
		return

	get_tree().current_scene.add_child(token)

	token.kind = "MONSTER"
	token.id = "" 
	token.cardname = str(params.get("token_name", "Token"))
	token.attribute = str(source_card.attribute)
	token.race = str(source_card.race)
	token.level = int(source_card.level)
	token.atk = int(source_card.atk)
	token.def = int(source_card.def)
	token.guardian_star = source_card.guardian_star.duplicate() if source_card.guardian_star != null else []

	token.tags = (params.get("token_tags", ["token"]) as Array).duplicate()
	token.keywords = []
	token.effects = []
	token.description = ""
	if token.has_method("_update_visuals"):
		token._update_visuals()
	token.set_meta("is_token", true)

	token.owner_side = ("PLAYER" if controller == "Player" else "OPPONENT")
	token.set_show_back_only(false)
	token.set_face_down(false)
	token.apply_owner_collision_layers()

	var src_art: TextureRect = source_card.get_node_or_null("CardArt")
	var tok_art: TextureRect = token.get_node_or_null("CardArt")
	if is_instance_valid(src_art) and is_instance_valid(tok_art):
		tok_art.texture = src_art.texture

	free_slot.card_in_slot = true
	if "card_ref" in free_slot:
		free_slot.card_ref = token

	token.set_field_slot(free_slot)
	if token.has_method("set_defense_position"):
		token.set_defense_position(true)
	else:
		token.in_defense = true
	token.scale = Vector2($"../../CardManager".FIELD_SCALE, $"../../CardManager".FIELD_SCALE)
	$"../../CardManager"._snap_card_to_slot_center(token, free_slot)
	token.z_index = -4

	event_service._register_card_with_effect_engine(token, controller)
	
	if controller == "Player":
		if not bm.player_cards_on_battlefield.has(token):
			bm.player_cards_on_battlefield.append(token)
	else:
		if not bm.opponent_cards_on_battlefield.has(token):
			bm.opponent_cards_on_battlefield.append(token)

	zone_service._clean_battlefield_lists()
	
	event_service._emit_duel_event("ON_SUMMON_BY_EFFECT", {
		"battle_manager": bm,
		"source": token,
		"controller": controller,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
		"created_from": source_card
	})

func set_random_spelltrap_from_db(source: Node, ctx: Dictionary, params: Dictionary) -> bool:
	print("BM set_random_spelltrap_from_db ENTER source=", source.cardname if is_instance_valid(source) and ("cardname" in source) else "<null>", " params=", params)

	var controller := str(params.get("controller", "SELF")).to_upper()
	var filters: Dictionary = params.get("filters", {})
	var exclude_ids: Array = params.get("exclude_ids", [])
	var exclude_self_id := bool(params.get("exclude_self_id", false))

	var source_controller := card_runtime_service._norm_owner(ctx.get("controller", ""))
	if source_controller == "" and is_instance_valid(source) and ("owner_side" in source):
		source_controller = ("Player" if str(source.owner_side).to_upper() == "PLAYER" else "Opponent")
	source_controller = card_runtime_service._norm_owner(source_controller)

	var target_controller := source_controller
	if controller == "OPPONENT":
		target_controller = ("Opponent" if source_controller == "Player" else "Player")
	elif controller == "SELF":
		target_controller = source_controller

	var free_slot := zone_service._get_free_spelltrap_slot_for(target_controller)
	if free_slot == null:
		print("BM set_random_spelltrap_from_db FAIL: no free spell/trap slot")
		return false

	var db: Array = card_db_service._get_cards_db()
	if db.is_empty():
		print("BM set_random_spelltrap_from_db FAIL: db empty")
		return false

	var excluded: Array[String] = []
	for x in exclude_ids:
		excluded.append(str(x))

	if exclude_self_id and is_instance_valid(source) and ("id" in source):
		excluded.append(str(source.id))

	var pool: Array = []
	for card_def in db:
		if typeof(card_def) != TYPE_DICTIONARY:
			continue
		if not card_db_service._db_card_matches_spelltrap_filters(card_def, filters):
			continue

		var candidate_id := str(card_def.get("id", ""))
		if excluded.has(candidate_id):
			continue

		pool.append(card_def)

	if pool.is_empty():
		print("BM set_random_spelltrap_from_db FAIL: pool empty")
		return false

	pool.shuffle()
	var picked: Dictionary = pool[0]

	var card := card_db_service._spawn_card_from_db_entry(picked, target_controller)
	if not is_instance_valid(card):
		print("BM set_random_spelltrap_from_db FAIL: spawn invalid")
		return false

	card_runtime_service._set_card_face_down(card, true)

	zone_service._set_card_slot(card, free_slot)
	zone_service._place_card_in_slot(card, free_slot, "EFFECT")

	card_runtime_service._set_card_face_down(card, true)
	if card.has_method("set_show_back_only"):
		card.set_show_back_only(false)

	print("BM set_random_spelltrap_from_db SUCCESS set=", card.cardname if ("cardname" in card) else str(card))
	return true

func summon_random_from_db(source: Node, ctx: Dictionary, params: Dictionary) -> bool:
	print("BM summon_random_from_db ENTER source=", source.cardname if is_instance_valid(source) and ("cardname" in source) else "<null>", " params=", params)

	var controller := str(params.get("controller", "SELF")).to_upper()
	var filters: Dictionary = params.get("filters", {})
	var position := str(params.get("position", "FACEUP_ATK")).to_upper()
	var exclude_ids: Array = params.get("exclude_ids", [])
	var exclude_self_id := bool(params.get("exclude_self_id", false))
	var prefer_highest_level := bool(params.get("prefer_highest_level", false))

	print("  controller=", controller, " filters=", filters, " position=", position, " exclude_self_id=", exclude_self_id, " exclude_ids=", exclude_ids)

	var source_controller := card_runtime_service._norm_owner(ctx.get("controller", ""))
	if source_controller == "" and is_instance_valid(source) and ("owner_side" in source):
		source_controller = ("Player" if str(source.owner_side).to_upper() == "PLAYER" else "Opponent")
	source_controller = card_runtime_service._norm_owner(source_controller)

	var summon_controller := source_controller
	if controller == "OPPONENT":
		summon_controller = ("Opponent" if source_controller == "Player" else "Player")
	elif controller == "SELF":
		summon_controller = source_controller

	print("  source_controller=", source_controller, " summon_controller=", summon_controller)

	var free_slot := zone_service._get_free_monster_slot_for(summon_controller)
	print("  free_slot=", free_slot)
	if free_slot == null:
		print("BM summon_random_from_db FAIL: no free slot")
		return false

	var db: Array = card_db_service._get_cards_db()
	print("  db size=", db.size())
	if db.is_empty():
		print("BM summon_random_from_db FAIL: db empty")
		return false

	var excluded: Array[String] = []
	for x in exclude_ids:
		excluded.append(str(x))

	if exclude_self_id and is_instance_valid(source) and ("id" in source):
		excluded.append(str(source.id))

	print("  excluded=", excluded)

	var pool: Array = []
	for card_def in db:
		if typeof(card_def) != TYPE_DICTIONARY:
			continue

		var candidate_id := str(card_def.get("id", ""))
		var candidate_name := str(card_def.get("cardname", ""))
		var matches := card_db_service._db_card_matches_filters(card_def, filters)

		if not matches:
			continue

		if excluded.has(candidate_id):
			print("    EXCLUDED candidate=", candidate_name, " id=", candidate_id)
			continue

		print("    POOL candidate=", candidate_name, " id=", candidate_id)
		pool.append(card_def)

	print("  pool size=", pool.size())

	if pool.is_empty():
		print("BM summon_random_from_db FAIL: pool empty")
		return false

	if prefer_highest_level:
		pool.sort_custom(func(a, b):
			var la := int(a.get("level", 0) if a.get("level", 0) != null else 0)
			var lb := int(b.get("level", 0) if b.get("level", 0) != null else 0)
			return la > lb
		)
		var top_level := int(pool[0].get("level", 0) if pool[0].get("level", 0) != null else 0)
		var filtered_top: Array = []
		for c in pool:
			var lv := int(c.get("level", 0) if c.get("level", 0) != null else 0)
			if lv == top_level:
				filtered_top.append(c)
		pool = filtered_top
		print("  prefer_highest_level filtered pool size=", pool.size(), " top_level=", top_level)

	pool.shuffle()
	var picked: Dictionary = pool[0]
	print("  picked=", picked.get("cardname", "<no name>"), " id=", picked.get("id", ""))

	var card := card_db_service._spawn_card_from_db_entry(picked, summon_controller)
	print("  spawned card=", card)
	if not is_instance_valid(card):
		print("BM summon_random_from_db FAIL: spawn invalid")
		return false
	card.set_meta("played_from_hand", false)
	if position == "FACEUP_ATK":
		card_runtime_service._set_card_face_down(card, false)
		if card.has_method("set_defense_position"):
			card.set_defense_position(false)
		else:
			card.in_defense = false
	elif position == "FACEUP_DEF":
		card_runtime_service._set_card_face_down(card, false)
		if card.has_method("set_defense_position"):
			card.set_defense_position(true)
		else:
			card.in_defense = true
	elif position == "FACEDOWN_DEF":
		card_runtime_service._set_card_face_down(card, true)
		if card.has_method("set_defense_position"):
			card.set_defense_position(true)
		else:
			card.in_defense = true
	else:
		card_runtime_service._set_card_face_down(card, false)
		if card.has_method("set_defense_position"):
			card.set_defense_position(false)
		else:
			card.in_defense = false

	zone_service._set_card_slot(card, free_slot)
	zone_service._place_card_in_slot(card, free_slot, "EFFECT")

	if position == "FACEUP_ATK":
		card_runtime_service._set_card_face_down(card, false)
		reveal_service.reveal_card(card)
	elif position == "FACEUP_DEF":
		card_runtime_service._set_card_face_down(card, false)
		reveal_service.reveal_card(card)
	elif position == "FACEDOWN_DEF":
		card_runtime_service._set_card_face_down(card, true)

	event_service._emit_duel_event("ON_SUMMON_BY_EFFECT", {
		"battle_manager": bm,
		"source": card,
		"controller": summon_controller,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
		"created_from": source
	})

	print("BM summon_random_from_db SUCCESS summoned=", card.cardname if ("cardname" in card) else str(card))
	return true
