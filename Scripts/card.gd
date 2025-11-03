extends Node2D

signal hovered
signal hovered_off

const LAYER_PLAYER := 1
const LAYER_OPP := 8

var starting_position
var card_slot_card_is_in

var card_id
var show_back_only := false 
var card_type := ""
var card_name := ""
var level := 0
var Atk := 0
var Def := 0
var attribute := ""        
var type := ""             # "warrior","dragon","equip?", etc.
var guardian_star := []
var guardian_primary_index := 0
var description := ""
var effect := []
var tags := []
@export var passcode: String = ""
var defeated := false
var in_defense := false

var card_owner := "Player"
var is_facedown := false
var fusion_result := false

var _temp_bonus_atk: int = 0
var _temp_bonus_def: int = 0

# ----- Normalización de arte -----
const ART_TARGET_SIZE := Vector2i(258, 258)
static var _ART_CACHE: Dictionary = {}

func _load_and_resize_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	if _ART_CACHE.has(path):
		return _ART_CACHE[path]
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		return null
	if img.get_width() != ART_TARGET_SIZE.x or img.get_height() != ART_TARGET_SIZE.y:
		img.resize(ART_TARGET_SIZE.x, ART_TARGET_SIZE.y, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(img)
	_ART_CACHE[path] = tex
	return tex

# ----- Rutas de assets -----
const ATR_ICON := {
	"light": "res://_resources/_attributes/light.png",
	"dark":  "res://_resources/_attributes/dark.png",
	"earth": "res://_resources/_attributes/earth.png",
	"wind":  "res://_resources/_attributes/wind.png",
	"water": "res://_resources/_attributes/water.png",
	"fire":  "res://_resources/_attributes/fire.png",
	"spell": "res://_resources/_attributes/spell.png",
	"trap":  "res://_resources/_attributes/trap.png",
}

const FRAME_MONSTER := "res://_resources/card_design/frame_monster.png"
const FRAME_ST      := "res://_resources/card_design/frame_spelltrap.png"
const TEX_MONSTER        := "res://_resources/card_design/texture_yellow.png"
const TEX_MONSTER_EFFECT := "res://_resources/card_design/texture_orange.png"
const TEX_SPELL          := "res://_resources/card_design/texture_green.png"
const TEX_TRAP           := "res://_resources/card_design/texture_pink.png"
const TEX_RITUAL         := "res://_resources/card_design/texture_blue.png"
const TEX_FUSION         := "res://_resources/card_design/texture_purple.png"
const CARD_BACK_TEX      := "res://_resources/card_design/card_back.png"

# ----- Helpers -----
func N(path: String) -> Node:
	if has_node(path):
		return get_node(path)
	return null

func _show_node(p: String) -> void:
	var n := N(p)
	if n and n is CanvasItem:
		(n as CanvasItem).show()

func _hide_node(p: String) -> void:
	var n := N(p)
	if n and n is CanvasItem:
		(n as CanvasItem).hide()

func _overlay_node() -> CanvasItem:
	return N("BackOverlay") as CanvasItem

func play_guardian_star_bonus_animation(guardian_star_name: String) -> void:
	var bonus_sprite = get_node_or_null("guardian_star_bonus") as AnimatedSprite2D
	if bonus_sprite:
		var animation_name = "guardian_star_%s" % guardian_star_name
		if bonus_sprite.sprite_frames and bonus_sprite.sprite_frames.has_animation(animation_name):
			bonus_sprite.visible = true
			bonus_sprite.play(animation_name)
			await bonus_sprite.animation_finished
			bonus_sprite.visible = false
			bonus_sprite.stop()
		else:
			print("Warning: Animation not found for Guardian Star: ", animation_name)

func _on_bonus_animation_finished(bonus_sprite: AnimatedSprite2D):
	if bonus_sprite:
		bonus_sprite.visible = false
		bonus_sprite.stop()

func set_temporary_display_bonus(bonus_atk: int, bonus_def: int) -> void:
	_temp_bonus_atk = bonus_atk
	_temp_bonus_def = bonus_def

func clear_temporary_display_bonus() -> void:
	_temp_bonus_atk = 0
	_temp_bonus_def = 0

# ----- Visual -----
func update_card_visuals() -> void:
	var bg  := N("background_texture") as TextureRect
	var art := N("artwork")           as Sprite2D
	var frm := N("card_frame")        as TextureRect

	# Paneles
	var mon_feat := N("monster_features")
	var st_feat  := N("spelltrap_features")

	# Nombre / atributo
	var name_lbl := N("card_name") as Label
	var attr_tx  := N("attribute") as TextureRect

	# ATK/DEF labels (en monster_features)
	var atk_lbl := N("monster_features/atk_def/atk") as Label
	var def_lbl := N("monster_features/atk_def/def") as Label

	# --- BOCA ABAJO ---
	if is_facedown:
		if art: art.visible = false
		if frm: frm.visible = true
		if bg and ResourceLoader.exists(CARD_BACK_TEX):
			bg.texture = load(CARD_BACK_TEX)

		_hide_node("monster_features")
		_hide_node("spelltrap_features")

		if name_lbl: name_lbl.text = ""
		if attr_tx:  attr_tx.texture = null

		var gs_lbl := get_node_or_null("guardian_star") as Label
		if gs_lbl:
			gs_lbl.visible = false

		_hide_node("new_indicator")
		return

	# --- ARTE (normalizado a 258x258 pa las cartas) ---
	if art:
		art.visible = true
		if passcode != "":
			var p_png = "res://_resources/_card_artwork/%s.png" % passcode
			var p_jpg = "res://_resources/_card_artwork/%s.jpg" % passcode
			var tex: Texture2D = _load_and_resize_texture(p_png)
			if tex == null:
				tex = _load_and_resize_texture(p_jpg)
			if tex:
				art.texture = tex
				art.scale = Vector2.ONE

	# Marco + fondo por tipo/atributo
	if frm and bg:
		if attribute == "spell":
			frm.texture = load(FRAME_ST)
			bg.texture  = load(TEX_SPELL)
			if type == "ritual":
				bg.texture = load(TEX_RITUAL)
		elif attribute == "trap":
			frm.texture = load(FRAME_ST)
			bg.texture  = load(TEX_TRAP)
		else:
			frm.texture = load(FRAME_MONSTER)
			var is_eff := (effect is Array and effect.size() > 0)
			if is_eff:
				bg.texture = load(TEX_MONSTER_EFFECT)
			else:
				bg.texture = load(TEX_MONSTER)
			if fusion_result or type == "fusion" or (tags is Array and tags.has("fusion")):
				bg.texture = load(TEX_FUSION)

	# Icono de atributo
	if attr_tx:
		var key := attribute
		if ATR_ICON.has(key):
			attr_tx.texture = load(ATR_ICON[key])
		else:
			attr_tx.texture = null

	# Nombre
	if name_lbl:
		name_lbl.text = str(card_name)
		var L := name_lbl.text.length()
		var sx := 1.0
		if L > 14:
			var corr = clamp(((L - 14) * 0.033), 0.0, 0.4)
			sx = 1.0 - corr
		name_lbl.scale.x = sx
		name_lbl.clip_text = (L > 14)
		if attribute == "spell" or attribute == "trap":
			name_lbl.add_theme_color_override("font_color", Color(1,1,1))
		else:
			name_lbl.add_theme_color_override("font_color", Color(0,0,0))

	# Paneles por tipo
	if mon_feat and st_feat:
		if attribute == "spell" or attribute == "trap":
			_hide_node("monster_features")
			_show_node("spelltrap_features")
			var t := N("spelltrap_features/type_of_spelltrap") as Label
			if t:
				if type != "" and type != attribute:
					t.text = "%s %s card" % [type, attribute]
				else:
					t.text = "%s card" % attribute
		else:
			_hide_node("spelltrap_features")
			_show_node("monster_features")

	_update_level_stars()

	if atk_lbl: atk_lbl.text = str(Atk + _temp_bonus_atk)
	if def_lbl: def_lbl.text = str(Def + _temp_bonus_def)

	_hide_node("new_indicator")

#Effect
func has_effect_type(effect_type:String):
	if effect == null:
		return false
	if typeof(effect) != TYPE_ARRAY:
		return false
	if effect.size() == 0:
		return false
	return effect[0] == effect_type

#Guardian Star
func ensure_guardian_initialized():
	if guardian_star is Array and guardian_star.size() > 0:
		guardian_primary_index = clamp(guardian_primary_index, 0, guardian_star.size() - 1)
		_update_guardian_star_label()

func current_guardian_star() -> String:
	if guardian_star is Array and guardian_star.size() > 0:
		return str(guardian_star[guardian_primary_index % guardian_star.size()])
	return ""

func set_guardian_primary_index(i: int) -> void:
	if guardian_star is Array and guardian_star.size() > 0:
		guardian_primary_index = clamp(i, 0, guardian_star.size() - 1)
		_update_guardian_star_label()

func toggle_guardian_star() -> void:
	if guardian_star is Array and guardian_star.size() >= 2:
		guardian_primary_index = 1 - guardian_primary_index
		_update_guardian_star_label()

func _update_guardian_star_label() -> void:
	var lbl := get_node_or_null("guardian_star") as Label
	if lbl:
		var txt := current_guardian_star()
		lbl.text = txt
		lbl.visible = (not is_facedown) and (txt != "")

func set_new_indicator(on: bool) -> void:
	var n := N("new_indicator")
	if n and n is CanvasItem:
		(n as CanvasItem).visible = on

func _update_level_stars() -> void:
	var root := N("monster_features/level/level12")
	if not root:
		return

	_show_node("monster_features/level/level12")

	for i in range(1, 13):
		_hide_node("monster_features/level/level12/level%d" % i)

	var to_show = clamp(level, 0, 12)
	for i in range(1, to_show + 1):
		_show_node("monster_features/level/level12/level%d" % i)

func _ready() -> void:
	if get_parent() and get_parent().has_method("connect_card_signals"):
		get_parent().connect_card_signals(self)

func _process(_dt: float) -> void:
	pass

func _on_area_2d_mouse_entered() -> void:
	emit_signal("hovered", self)

func _on_area_2d_mouse_exited() -> void:
	emit_signal("hovered_off", self)

# ----- Carga desde DB -----
func _to_int(v, fallback := 0) -> int:
	if v == null: return fallback
	var t := typeof(v)
	if t == TYPE_INT: return v
	if t == TYPE_FLOAT: return int(v)
	if t == TYPE_STRING:
		return int(v) if (v as String).is_valid_int() else fallback
	return fallback

func apply_db(db: Dictionary) -> void:
	card_type  = str(db.get("card_type",""))
	card_name  = str(db.get("card_name",""))
	attribute  = str(db.get("attribute","")).to_lower()
	type       = str(db.get("type","")).to_lower()

	level = _to_int(db.get("level", null), 0)
	Atk   = _to_int(db.get("atk",   null), 0)
	Def   = _to_int(db.get("def",   null), 0)

	effect = db.get("effect", [])
	description = db.get("description","")
	tags   = db.get("tags", [])
	passcode = str(db.get("passcode",""))
	
	guardian_star = db.get("guardian_star", [])
	fusion_result = (type == "fusion") or (tags is Array and tags.has("fusion"))

	update_card_visuals()

func get_visual_half_size() -> Vector2:
	var cs := $Area2D/CollisionShape2D
	if cs and cs.shape is RectangleShape2D:
		return (cs.shape as RectangleShape2D).extents
	return Vector2(120, 167)

func apply_owner_collision_layers():
	var area := $Area2D
	if not area: return
	if card_owner == "Player":
		area.collision_layer = LAYER_PLAYER
	else:
		area.collision_layer = LAYER_OPP

func set_in_hand_mask(on: bool):
	var area := $Area2D
	if area:
		area.monitoring = not on
		area.input_pickable = not on

func set_show_back_only(on: bool):
	show_back_only = on
	_update_back_overlay_visibility()

func set_facedown(on: bool):
	is_facedown = on
	update_card_visuals()
	_update_back_overlay_visibility()
	
	if not is_facedown:
		if has_method("ensure_guardian_initialized"):
			ensure_guardian_initialized()

	_update_guardian_star_label()

func set_defense_position(on: bool) -> void:
	in_defense = on
	if not card_slot_card_is_in:
		rotation_degrees = 0
		return

	var anchor := get_node_or_null("AnchorCenter") as Node2D
	var slot := card_slot_card_is_in as Node2D
	var slot_anchor := slot.get_node_or_null("Anchor") as Node2D

	var before := global_position
	if anchor:
		before = anchor.to_global(Vector2.ZERO)

	if in_defense:
		rotation_degrees = 90
	else:
		rotation_degrees = 0

	if anchor and slot_anchor:
		var my_delta := anchor.to_global(Vector2.ZERO) - to_global(Vector2.ZERO)
		global_position = slot_anchor.global_position - my_delta
	elif anchor:
		var after := anchor.to_global(Vector2.ZERO)
		global_position += (before - after)

func toggle_defense_position():
	set_defense_position(!in_defense)

func is_in_defense_position():
	return in_defense

func _update_back_overlay_visibility():
	var overlay := _overlay_node()
	if overlay:
		overlay.visible = (show_back_only or is_facedown)
