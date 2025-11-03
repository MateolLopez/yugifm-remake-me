extends Node

enum Mode { STORY, FREE_DUEL }

var mode := Mode.STORY
var current_timeline := ""
var current_episode := ""
var current_opponent_id := ""

var current_rules := {
	"next": "",
	"return_to_story": true,     
	"reward_scene_id": ""        
}

var player_decks := { "main": [], "side": [], "extra": [] }
var active_player_deck_key := "main"

var collection := {}
var unlocks := { "opponents": {}, "cards": {} }

func set_duel_route(next_timeline: String, return_to_story = true, reward_scene_id = "") -> void:
	current_rules = {
		"next": next_timeline,
		"return_to_story": return_to_story,
		"reward_scene_id": reward_scene_id
	}

func clear_duel_routes() -> void:
	set_duel_route("", true, "")

func next_timeline() -> String:
	return str(current_rules.get("next", ""))

func resolve_opponent_deck() -> Array:
	return OpponentDB.get_deck_for_opponent(current_opponent_id)

func resolve_player_deck() -> Array:
	return PlayerDeckDB.get_deck_by_key(active_player_deck_key)

func new_game() -> void:
	mode = Mode.STORY
	current_episode = "ep_1"
	current_timeline = "ep_1_01"
	current_opponent_id = ""
	clear_duel_routes()
	active_player_deck_key = "main"
	save_to_disk()

func continue_story_fallback_default(default_tl := "ep_1_01") -> String:
	if current_timeline == "" or current_timeline == null:
		current_timeline = default_tl
	return current_timeline

func mark_opponent_unlocked(id: String) -> void:
	unlocks.opponents[id] = true
	save_to_disk()

# SAVE / LOAD 
func save_to_disk():
	var data = {
		"mode": int(mode),
		"episode": current_episode,
		"timeline": current_timeline,
		"opponent": current_opponent_id,
		"player_decks": player_decks,
		"active_player_deck_key": active_player_deck_key,
		"collection": collection,
		"unlocks": unlocks,
		"current_rules": current_rules,
	}
	var f = FileAccess.open("user://save.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func load_from_disk():
	if not FileAccess.file_exists("user://save.json"): return
	var txt = FileAccess.get_file_as_string("user://save.json")
	var res = JSON.parse_string(txt)
	if typeof(res) == TYPE_DICTIONARY:
		mode = Mode.STORY if res.get("mode") == null else Mode[Mode.keys()[res.get("mode")]]
		current_episode = res.get("episode","")
		current_timeline = res.get("timeline","")
		current_opponent_id = res.get("opponent","")
		player_decks = res.get("player_decks", player_decks)
		active_player_deck_key = res.get("active_player_deck_key", "main")
		collection = res.get("collection", {})
		unlocks = res.get("unlocks", {})
		var cr = res.get("current_rules", null)
		if typeof(cr) == TYPE_DICTIONARY:
			current_rules = cr
		else:
			clear_duel_routes()
