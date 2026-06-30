extends Node
class_name DuelRuleService

var bm: Node = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager

func _rules_value(key: String, fallback):
	var rules = get_node_or_null("/root/DuelRules")
	if rules:
		if rules.has_method("get_rule"):
			return rules.get_rule(key, fallback)
	var json_rules = null
	if "duel_rules" in self:
		json_rules = get("duel_rules")
	if json_rules is Dictionary and json_rules.has(key):
		return json_rules[key]
	return fallback

func _max_hand_size() -> int:
	return int(_rules_value("max_hand_size", bm.DEFAULT_MAX_HAND_SIZE))

func _starting_hp() -> int:
	return int(_rules_value("starting_hp", bm.DEFAULT_STARTING_HP))
