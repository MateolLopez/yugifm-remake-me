extends Node2D
class_name Card

@onready var card_name_label: Label = $CardName
@onready var card_art: TextureRect = $CardArt
@onready var card_back: TextureRect = $CardBack
@onready var card_text_box: Label = $TextBox

var id: String = ""
var kind: String = ""
var cardname: String = ""
var attribute: String = ""
var race: String = ""
var level: int = 0
var atk: int = 0
var def: int = 0
var guardian_star: Array = []
var tags: Array = []
var keywords: Array = []
var description: String = ""
var effects: Array = []

var owner_side: String = "OWNER"
var face_down: bool = false
var show_back_only: bool = false
var in_hand_mask: bool = false

func apply_db(card_def: Dictionary) -> void:
	id = str(card_def.get("id", ""))
	kind = str(card_def.get("kind", ""))

	var n = card_def.get("cardname", null)
	if n == null:
		n = card_def.get("name", "")
	cardname = str(n)

	attribute = _safe_upper(card_def.get("attribute", ""))
	race = _safe_upper(card_def.get("race", ""))

	level = int(card_def.get("level", 0) if card_def.get("level", 0) != null else 0)
	atk = int(card_def.get("atk", 0) if card_def.get("atk", 0) != null else 0)
	def = int(card_def.get("def", 0) if card_def.get("def", 0) != null else 0)

	guardian_star = card_def.get("guardian_star", []) if card_def.get("guardian_star", []) != null else []
	tags = card_def.get("tags", []) if card_def.get("tags", []) != null else []
	keywords = card_def.get("keywords", []) if card_def.get("keywords", []) != null else []
	description = str(card_def.get("description", "")) if card_def.get("description", "") != null else ""
	effects = card_def.get("effects", []) if card_def.get("effects", []) != null else []

	_update_visuals()

func set_face_down(v: bool) -> void:
	face_down = v
	_update_back_visibility()

func set_facedown(v: bool) -> void:
	set_face_down(v)

func set_show_back_only(v: bool) -> void:
	show_back_only = v
	_update_back_visibility()

func set_in_hand_mask(v: bool) -> void:
	in_hand_mask = v

func apply_owner_collision_layers() -> void:
	pass

func _update_visuals() -> void:
	if is_instance_valid(card_name_label):
		card_name_label.text = cardname
	_update_back_visibility()
	_try_set_art_texture()
	_update_text_box()

func _update_back_visibility() -> void:
	if is_instance_valid(card_back):
		card_back.visible = face_down or show_back_only
	if is_instance_valid(card_art):
		card_art.visible = not (face_down or show_back_only)

func _try_set_art_texture() -> void:
	if not is_instance_valid(card_art):
		return
	if id == "":
		return

	var base := "res://Assets/Cards/CardArt/%s" % id
	var candidates := ["%s.webp" % base, "%s.png" % base, "%s.jpg" % base, "%s.jpeg" % base]
	for p in candidates:
		if ResourceLoader.exists(p):
			card_art.texture = load(p)
			return

func _update_text_box() -> void:
	if not is_instance_valid(card_text_box):
		return

	var lines: Array[String] = []
	if kind == "MONSTER":
		lines.append("%s / %s" % [attribute if attribute != "" else "?", race if race != "" else "?"])
		lines.append("LV %d  ATK %d  DEF %d" % [level, atk, def])
	if description != "":
		lines.append("")
		lines.append(description)

	card_text_box.text = "\n".join(lines)

func _safe_upper(v) -> String:
	if v == null:
		return ""
	return str(v).to_upper()
