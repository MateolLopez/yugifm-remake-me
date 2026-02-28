extends Node2D
class_name Card

enum FusionMarker { NONE, GENERIC, SPECIFIC }
@onready var fusion_spiral: CanvasItem = get_node_or_null("fusionSpiral")
var _fusion_spiral_original_material: Material = null

signal hovered(card)
signal hovered_off(card)
signal clicked(card)

@onready var area_2d: Area2D = get_node_or_null("Area2D")
@onready var card_name_label: Label = get_node_or_null("CardName")
@onready var card_art: TextureRect = get_node_or_null("CardArt")
@onready var card_back: TextureRect = get_node_or_null("CardBack")
@onready var background_texture: TextureRect = get_node_or_null("background_texture")
@onready var card_frame: TextureRect = get_node_or_null("card_frame")
@onready var attribute_icon: TextureRect = get_node_or_null("attribute")
@onready var monster_features: Control = get_node_or_null("monster_features")
@onready var spelltrap_features: Control = get_node_or_null("spelltrap_features")
@onready var atk_label: Label = get_node_or_null("monster_features/atk_def/atk")
@onready var def_label: Label = get_node_or_null("monster_features/atk_def/def")
@onready var spelltrap_type_label: Label = get_node_or_null("spelltrap_features/type_of_spelltrap")
@onready var guardian_star_label: Label = get_node_or_null("guardian_star")

@onready var card_text_box: Label = get_node_or_null("TextBox")

# -------------------------
# Card DB fields
# -------------------------
var id: String = ""
var kind: String = "" # MONSTER / SPELL / TRAP
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

# -------------------------
# Guardian Star activa (switchable)
# -------------------------
var active_guardian_star_index: int = 0

var actual_guardian_star: String:
	get:
		if guardian_star == null or guardian_star.is_empty():
			return ""
		var idx = clamp(active_guardian_star_index, 0, guardian_star.size() - 1)
		return str(guardian_star[idx])
	set(value):
		if guardian_star == null or guardian_star.is_empty():
			return
		var s := str(value).to_upper()
		for i in range(guardian_star.size()):
			if str(guardian_star[i]).to_upper() == s:
				active_guardian_star_index = i
				_update_guardian_star_label()
				return

func set_active_guardian_star_index(i: int) -> void:
	if guardian_star == null or guardian_star.is_empty():
		active_guardian_star_index = 0
	else:
		active_guardian_star_index = clamp(i, 0, guardian_star.size() - 1)
	_update_guardian_star_label()

# -------------------------
# Runtime ownership/visibility
# -------------------------
var owner_side: String = "OWNER" # PLAYER / OPPONENT
var face_down: bool = false
var show_back_only: bool = false
var in_hand_mask: bool = false

# Runtime state
var current_zone: String = "DECK" # DECK, HAND, FIELD, GRAVE, BANISHED, NONE
var current_slot: Node = null
var in_defense: bool = false
var starting_position: Vector2 = Vector2.ZERO
var defeated: bool = false
var fusion_result: bool = false

func _ready() -> void:
	_connect_area_signals()
	_configure_texture_rects()
	if is_instance_valid(fusion_spiral):
		_fusion_spiral_original_material = fusion_spiral.material
	_update_visuals()

# -------------------------
# Input signals
# -------------------------
func _connect_area_signals() -> void:
	if not is_instance_valid(area_2d):
		return
	if not area_2d.mouse_entered.is_connected(_on_area_mouse_entered):
		area_2d.mouse_entered.connect(_on_area_mouse_entered)
	if not area_2d.mouse_exited.is_connected(_on_area_mouse_exited):
		area_2d.mouse_exited.connect(_on_area_mouse_exited)
	if not area_2d.input_event.is_connected(_on_area_input_event):
		area_2d.input_event.connect(_on_area_input_event)

func _on_area_mouse_entered() -> void:
	emit_signal("hovered", self)

func _on_area_mouse_exited() -> void:
	emit_signal("hovered_off", self)

func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		emit_signal("clicked", self)

# -------------------------
# DB apply
# -------------------------
func apply_db(card_def: Dictionary) -> void:
	id = str(card_def.get("id", ""))
	kind = str(card_def.get("kind", "")).to_upper()

	var n: Variant = card_def.get("cardname", null)
	if n == null:
		n = card_def.get("name", "")
	cardname = str(n)

	attribute = _safe_upper(card_def.get("attribute", ""))
	race = _safe_upper(card_def.get("race", ""))

	level = int(card_def.get("level", 0) if card_def.get("level", 0) != null else 0)
	atk = int(card_def.get("atk", 0) if card_def.get("atk", 0) != null else 0)
	def = int(card_def.get("def", 0) if card_def.get("def", 0) != null else 0)

	guardian_star = card_def.get("guardian_star", []) if card_def.get("guardian_star", []) != null else []
	active_guardian_star_index = 0

	tags = card_def.get("tags", []) if card_def.get("tags", []) != null else []
	keywords = card_def.get("keywords", []) if card_def.get("keywords", []) != null else []
	description = str(card_def.get("description", "")) if card_def.get("description", "") != null else ""
	effects = card_def.get("effects", []) if card_def.get("effects", []) != null else []

	_update_visuals()

# -------------------------
# Visibility setters used everywhere
# -------------------------
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
	if not is_instance_valid(area_2d):
		area_2d = get_node_or_null("Area2D")
	if not is_instance_valid(area_2d):
		return

	var side := str(owner_side).to_upper()
	if side == "OPPONENT":
		area_2d.collision_layer = 8
	else:
		area_2d.collision_layer = 1

	area_2d.input_pickable = true
	area_2d.monitoring = true

# -------------------------
# Visuals
# -------------------------
func _configure_texture_rects() -> void:
	for tr in [card_art, card_back, background_texture, card_frame, attribute_icon]:
		if not is_instance_valid(tr):
			continue
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

func _update_visuals() -> void:
	_update_name_label()
	_update_kind_visuals()
	_update_stat_labels()
	_update_guardian_star_label()
	_update_attribute_icon()
	_try_set_art_texture()
	_update_back_visibility()
	_update_text_box_optional()

func _update_name_label() -> void:
	if is_instance_valid(card_name_label):
		card_name_label.text = cardname

func _update_kind_visuals() -> void:
	var is_monster_card: bool = (kind == "MONSTER")
	if is_instance_valid(monster_features):
		monster_features.visible = is_monster_card
	if is_instance_valid(spelltrap_features):
		spelltrap_features.visible = not is_monster_card

	if is_instance_valid(background_texture):
		background_texture.texture = _load_kind_background_texture()
	if is_instance_valid(card_frame):
		card_frame.texture = _load_kind_frame_texture()

	if is_instance_valid(spelltrap_type_label):
		if kind == "SPELL":
			spelltrap_type_label.text = "SPELL"
		elif kind == "TRAP":
			spelltrap_type_label.text = "TRAP"
		else:
			spelltrap_type_label.text = ""

func _update_stat_labels() -> void:
	if is_instance_valid(atk_label):
		atk_label.text = str(atk)
	if is_instance_valid(def_label):
		def_label.text = str(def)
	_update_level_stars()

func _update_level_stars() -> void:
	for i in range(1, 13):
		var star: TextureRect = get_node_or_null("monster_features/level/level12/level%d" % i)
		if is_instance_valid(star):
			star.visible = (kind == "MONSTER" and level >= i and level > 0)

func _update_guardian_star_label() -> void:
	if not is_instance_valid(guardian_star_label):
		return
	if guardian_star == null or guardian_star.is_empty():
		guardian_star_label.text = ""
		return
	var a: String = str(guardian_star[0])
	var b: String = str(guardian_star[1]) if guardian_star.size() > 1 else ""
	guardian_star_label.text = a if b == "" else "%s / %s" % [a, b]

func _update_attribute_icon() -> void:
	if not is_instance_valid(attribute_icon):
		return
	if kind != "MONSTER":
		attribute_icon.visible = false
		return
	attribute_icon.visible = true
	if attribute == "":
		attribute_icon.texture = null
		return
	var attr_candidates: Array[String] = [
		"res://_resources/_attributes/%s.png" % attribute.to_lower(),
		"res://_resources/_attributes/%s.webp" % attribute.to_lower(),
		"res://_resources/_attributes/%s.jpg" % attribute.to_lower()
	]
	for p in attr_candidates:
		if ResourceLoader.exists(p):
			attribute_icon.texture = load(p)
			return
	attribute_icon.texture = null

func _update_back_visibility() -> void:
	var covered: bool = face_down or show_back_only

	if is_instance_valid(card_back):
		card_back.visible = covered
	if is_instance_valid(card_art):
		card_art.visible = not covered

	if is_instance_valid(card_name_label):
		card_name_label.visible = not covered
	if is_instance_valid(attribute_icon):
		attribute_icon.visible = (not covered and kind == "MONSTER")
	if is_instance_valid(monster_features):
		monster_features.visible = (not covered and kind == "MONSTER")
	if is_instance_valid(spelltrap_features):
		spelltrap_features.visible = (not covered and kind != "MONSTER")
	if is_instance_valid(guardian_star_label):
		guardian_star_label.visible = not covered

func _try_set_art_texture() -> void:
	if not is_instance_valid(card_art):
		return
	if id == "":
		card_art.texture = null
		return

	var id_padded8: String = id.pad_zeros(8)
	var id_padded10: String = id.pad_zeros(10)
	var candidates: Array[String] = [
		"res://_resources/_card_artwork/%s.png" % id,
		"res://_resources/_card_artwork/%s.webp" % id,
		"res://_resources/_card_artwork/%s.jpg" % id,
		"res://_resources/_card_artwork/%s.jpeg" % id,
		"res://_resources/_card_artwork/%s.png" % id_padded8,
		"res://_resources/_card_artwork/%s.webp" % id_padded8,
		"res://_resources/_card_artwork/%s.jpg" % id_padded8,
		"res://_resources/_card_artwork/%s.jpeg" % id_padded8,
		"res://_resources/_card_artwork/%s.png" % id_padded10,
		"res://_resources/_card_artwork/%s.webp" % id_padded10,
		"res://_resources/_card_artwork/%s.jpg" % id_padded10,
		"res://_resources/_card_artwork/%s.jpeg" % id_padded10,
	]
	for p in candidates:
		if ResourceLoader.exists(p):
			card_art.texture = load(p)
			card_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			card_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			return

func _load_kind_background_texture() -> Texture2D:
	var candidates: Array[String] = []
	match kind:
		"MONSTER":
			candidates = [
				"res://_resources/card_design/texture_monster.png",
				"res://_resources/card_design/texture_orange.png",
			]
		"SPELL":
			candidates = [
				"res://_resources/card_design/texture_spell.png",
				"res://_resources/card_design/texture_green.png",
			]
		"TRAP":
			candidates = [
				"res://_resources/card_design/texture_trap.png",
				"res://_resources/card_design/texture_pink.png",
			]
		_:
			candidates = ["res://_resources/card_design/texture_orange.png"]
	return _load_first_texture(candidates)

func _load_kind_frame_texture() -> Texture2D:
	var candidates: Array[String] = []
	if kind == "MONSTER":
		candidates = ["res://_resources/card_design/frame_monster.png", "res://_resources/card_design/frame_monster.jpg"]
	else:
		candidates = ["res://_resources/card_design/frame_spelltrap.png", "res://_resources/card_design/frame_spelltrap.jpg"]
	return _load_first_texture(candidates)

func _load_first_texture(paths: Array[String]) -> Texture2D:
	for p in paths:
		if ResourceLoader.exists(p):
			return load(p)
	return null

func _update_text_box_optional() -> void:
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

func get_effects() -> Array:
	return effects if effects != null else []

func has_keyword(k: String) -> bool:
	if keywords == null:
		return false
	return keywords.has(k)

# -------------------------
# Runtime helpers 
# -------------------------
func is_on_field() -> bool:
	return current_zone == "FIELD" and current_slot != null

func is_spell_like() -> bool:
	return kind == "SPELL" or kind == "TRAP"

func is_monster() -> bool:
	return kind == "MONSTER"

func set_field_slot(slot: Node) -> void:
	current_slot = slot
	current_zone = "FIELD"

func clear_field_slot() -> void:
	current_slot = null
	if current_zone == "FIELD":
		current_zone = "NONE"

func move_to_zone(zone_name: String) -> void:
	current_zone = zone_name.to_upper()
	if current_zone != "FIELD":
		current_slot = null

func get_visual_half_size() -> Vector2:
	if is_instance_valid(card_art) and card_art.size != Vector2.ZERO:
		return card_art.size * 0.5
	if is_instance_valid(card_back) and card_back.size != Vector2.ZERO:
		return card_back.size * 0.5
	return Vector2(32, 48)

func set_defense_position(value: bool) -> void:
	in_defense = value
	_update_battle_position_visual()

func _update_battle_position_visual() -> void:
	var anchor: Node2D = get_node_or_null("AnchorCenter") as Node2D
	if not is_instance_valid(anchor):
		rotation_degrees = 90 if in_defense else 0
		return

	var anchor_global_before: Vector2 = anchor.global_position

	rotation_degrees = 90 if in_defense else 0

	var anchor_global_after: Vector2 = anchor.global_position

	global_position += (anchor_global_before - anchor_global_after)

# -------------------------
# Utils
# -------------------------
func _safe_upper(v: Variant) -> String:
	if v == null:
		return ""
	return str(v).to_upper()


# ---------------------------
# Marcadores de fusión
# ---------------------------
var fusion_marker: int = FusionMarker.NONE

func set_fusion_marker(marker: int) -> void:
	if not is_instance_valid(fusion_spiral):
		return

	if marker == FusionMarker.NONE:
		fusion_spiral.visible = false
		if _fusion_spiral_original_material != null:
			fusion_spiral.material = _fusion_spiral_original_material
		return

	fusion_spiral.visible = true

	if marker == FusionMarker.GENERIC:
		fusion_spiral.material = null
		return

	if marker == FusionMarker.SPECIFIC:
		if _fusion_spiral_original_material != null:
			var m := _fusion_spiral_original_material.duplicate(true)
			m.resource_local_to_scene = true
			fusion_spiral.material = m

			if m is ShaderMaterial:
				var sm := m as ShaderMaterial
				if sm.shader != null:
					pass
		return

	fusion_spiral.material = null
