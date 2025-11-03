extends Node

const GROUP1 := ["Mercury","Sun","Moon","Venus"]
const GROUP2 := ["Mars","Jupiter","Saturn","Uranus","Pluto","Neptune"]

var _next_map := {}

func _ready() -> void:
	_build_cycle(GROUP1)
	_build_cycle(GROUP2)

func _build_cycle(arr: Array):
	for  i in range(arr.size()):
		_next_map[arr[i]] = arr[(i+1) % arr.size()]

func who_is_advantaged(attacker_star: String, defender_star: String) -> String:
	if attacker_star == "" or defender_star == "":
		return ""
	if _next_map.get(attacker_star, "") == defender_star:
		return "attacker"
	if _next_map.get(defender_star, "") == attacker_star:
		return "defender"
	return ""


func compute_bonuses(attacker_star: String, defender_star: String):
	var res :={
		"attacker_atk":0, "attacker_def": 0,
		"defender_atk":0, "defender_def": 0,
	}
	var adv = who_is_advantaged(attacker_star,defender_star)
	if adv == "attacker":
		res.attacker_atk = 500
		res.attacker_def = 500
	elif adv == "defender":
		res.defender_atk = 500
		res.defender_def = 500
	return res
