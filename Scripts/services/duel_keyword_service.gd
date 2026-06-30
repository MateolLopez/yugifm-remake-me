extends Node
class_name DuelKeywordService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service

func _has_kw(card: Node, kw: String) -> bool:
	if not is_instance_valid(card):
		return false

	var want := str(kw).to_upper()

	if card.has_method("equip_has_keyword"):
		if bool(card.call("equip_has_keyword", want)):
			return true

	if card.has_method("has_keyword"):
		if bool(card.call("has_keyword", want)):
			return true

	if "keywords" in card and typeof(card.keywords) == TYPE_ARRAY:
		for k in card.keywords:
			if str(k).to_upper() == want:
				return true

	if card.has_meta("runtime_keywords"):
		var runtime_keywords: Array = card.get_meta("runtime_keywords")
		for k in runtime_keywords:
			if str(k).to_upper() == want:
				return true

	return false

func apply_keyword_to_card_if_matches_side(source_card, target_card, target_side: String, keyword: String, _ctx: Dictionary = {}) -> void:
	if not is_instance_valid(target_card):
		return
	var desired := str(target_side).to_upper()
	var actual := str(card_runtime_service._card_owner_side(target_card)).to_upper()
	if desired in ["OPPONENT", "ENEMY"]:
		var src_side := str(card_runtime_service._card_owner_side(source_card)).to_upper() if is_instance_valid(source_card) else ""
		if src_side == "PLAYER":
			desired = "OPPONENT"
		elif src_side == "OPPONENT":
			desired = "PLAYER"
	if desired in ["PLAYER","OPPONENT"] and actual != desired:
		return
	if target_card.has_method("add_runtime_keyword"):
		target_card.add_runtime_keyword(keyword)
	elif target_card.has_method("add_keyword"):
		target_card.add_keyword(keyword)
	else:
		var kws: Array = []
		if target_card.has_meta("runtime_keywords"):
			kws = target_card.get_meta("runtime_keywords")
		if keyword not in kws:
			kws.append(keyword)
			target_card.set_meta("runtime_keywords", kws)

func apply_keyword_to_target(target: Node, keyword: String, duration: String, effect_controller: String = "") -> void:
	if not is_instance_valid(target):
		return

	keyword = str(keyword).to_upper()
	duration = str(duration).to_upper()

	var runtime_keywords: Array = []
	if target.has_meta("runtime_keywords"):
		runtime_keywords = target.get_meta("runtime_keywords")
	if not runtime_keywords.has(keyword):
		runtime_keywords.append(keyword)
	target.set_meta("runtime_keywords", runtime_keywords)

	var timed_effects: Array = []
	if target.has_meta("timed_keywords"):
		timed_effects = target.get_meta("timed_keywords")

	var owner := card_runtime_service._norm_owner(zone_service._owner_of(target))

	match duration:
		"UNTIL_TURN_END":
			timed_effects.append({
				"keyword": keyword,
				"expire_turn_index": bm.turn_index,
				"expire_on_turn_owner": ("Opponent" if bm.is_opponent_turn else "Player")
			})
		"UNTIL_NEXT_OWNER_TURN_END":
			timed_effects.append({
				"keyword": keyword,
				"expire_turn_index": bm.turn_index + 1,
				"expire_on_turn_owner": effect_controller
			})
		"UNTIL_NEXT_TARGET_TURN_END":
			timed_effects.append({
				"keyword": keyword,
				"expire_turn_index": bm.turn_index + 1,
				"expire_on_turn_owner": owner
			})
		"UNTIL_LEAVE_FIELD":
			timed_effects.append({
				"keyword": keyword,
				"expire_on_leave_field": true
			})
		"PERMANENT_WHILE_FACEUP":
			timed_effects.append({
				"keyword": keyword,
				"expire_on_leave_field": true,
				"expire_if_face_down": true
			})

	target.set_meta("timed_keywords", timed_effects)

func _process_timed_keywords_on_turn_end(turn_owner: String) -> void:
	var all_cards: Array = []
	all_cards.append_array(bm.player_cards_on_battlefield)
	all_cards.append_array(bm.opponent_cards_on_battlefield)

	for c in all_cards:
		if not is_instance_valid(c):
			continue
		if not c.has_meta("timed_keywords"):
			continue

		var timed_keywords: Array = c.get_meta("timed_keywords")
		var kept: Array = []
		var runtime_keywords: Array = c.get_meta("runtime_keywords") if c.has_meta("runtime_keywords") else []

		for item in timed_keywords:
			if typeof(item) != TYPE_DICTIONARY:
				continue

			var expire := false

			if item.get("expire_on_turn_owner", "") == turn_owner and int(item.get("expire_turn_index", -1)) <= bm.turn_index:
				expire = true

			if expire:
				var kw := str(item.get("keyword", "")).to_upper()
				runtime_keywords = runtime_keywords.filter(func(x): return str(x).to_upper() != kw)
			else:
				kept.append(item)

		c.set_meta("timed_keywords", kept)
		c.set_meta("runtime_keywords", runtime_keywords)
