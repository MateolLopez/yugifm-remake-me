extends Node

@export_group("Fallback Presentation")
@export var fallback_duel_bgm: AudioStream
@export var fallback_background: Texture2D

@export_group("Scene Targets")
@export var background_target_path: NodePath

@export_group("SFX Timing")
@export var draw_sfx_min_interval: float = 0.30

var _last_sfx_time_msec: Dictionary = {}
var _background_target: Node = null

@export_group("Audio Buses")
@export var sfx_bus: StringName = &"SFX"
@export var music_bus: StringName = &"Music"

@export_group("Music")
@export var duel_bgm: AudioStream
@export var autoplay_bgm: bool = true
@export var loop_bgm: bool = true
@export var bgm_volume_db: float = -8.0

@export_group("SFX - Basic Duel")
@export var draw_sfx: AudioStream
@export var summon_faceup_sfx: AudioStream
@export var summon_set_sfx: AudioStream
@export var set_spelltrap_sfx: AudioStream
@export var spell_activate_sfx: AudioStream
@export var monster_effect_activate_sfx: AudioStream
@export var trap_reactive_sfx: AudioStream
@export var summon_by_effect_sfx: AudioStream

@export_group("SFX - Destruction")
@export var destroy_vibration_sfx: AudioStream
@export var destroy_explosion_sfx: AudioStream

@export_group("SFX - Impact / Typed")
@export var thunder_destroy_sfx: AudioStream

@export_group("SFX - Fusion")
@export var material_absorb_sfx: AudioStream
@export var fusion_intent_sfx: AudioStream
@export var fusion_result_sfx: AudioStream

@export_group("VFX")
@export var default_activation_fx_scene: PackedScene
@export var monster_reborn_summon_fx_scene: PackedScene
@export var thunder_destroy_fx_scene: PackedScene
@export var fusion_result_summoned_vfx_scene: PackedScene

@export_group("VFX - Fullscreen")
@export var coin_toss_fx_scene: PackedScene
@export var exodia_win_fx_scene: PackedScene

var _bgm_player: AudioStreamPlayer = null


func _ready() -> void:
	_setup_bgm_player()
	_background_target = get_node_or_null(background_target_path)

	if autoplay_bgm:
		if duel_bgm != null:
			play_bgm(duel_bgm)
		elif fallback_duel_bgm != null:
			play_bgm(fallback_duel_bgm)


# =========================
# BGM
# =========================

func _setup_bgm_player() -> void:
	if is_instance_valid(_bgm_player):
		return

	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGMPlayer"
	_bgm_player.bus = music_bus
	_bgm_player.volume_db = bgm_volume_db

	add_child(_bgm_player)

	if not _bgm_player.finished.is_connected(_on_bgm_finished):
		_bgm_player.finished.connect(_on_bgm_finished)


func play_bgm(stream: AudioStream = null, from_position: float = 0.0, restart_if_same: bool = false) -> void:
	_setup_bgm_player()

	if stream != null:
		duel_bgm = stream

	if duel_bgm == null:
		return

	var should_restart := restart_if_same

	if _bgm_player.stream != duel_bgm:
		should_restart = true

	_bgm_player.bus = music_bus
	_bgm_player.volume_db = bgm_volume_db
	_bgm_player.stream = duel_bgm

	if should_restart:
		_bgm_player.stop()
		_bgm_player.play(from_position)
		return

	if not _bgm_player.playing:
		_bgm_player.play(from_position)

func stop_bgm() -> void:
	if is_instance_valid(_bgm_player):
		_bgm_player.stop()


func pause_bgm() -> void:
	if is_instance_valid(_bgm_player):
		_bgm_player.stream_paused = true


func resume_bgm() -> void:
	if is_instance_valid(_bgm_player):
		_bgm_player.stream_paused = false

func play_bgm_from_path(path: String, from_position: float = 0.0, restart_if_same: bool = true) -> void:
	path = path.strip_edges()

	if path == "":
		if fallback_duel_bgm != null:
			play_bgm(fallback_duel_bgm, from_position, restart_if_same)
		return

	if not ResourceLoader.exists(path):
		push_warning("DuelFxManager: no existe la música: %s" % path)

		if fallback_duel_bgm != null:
			play_bgm(fallback_duel_bgm, from_position, restart_if_same)

		return

	var res := ResourceLoader.load(path)

	if res == null:
		push_warning("DuelFxManager: no se pudo cargar la música: %s" % path)

		if fallback_duel_bgm != null:
			play_bgm(fallback_duel_bgm, from_position, restart_if_same)

		return

	if not (res is AudioStream):
		push_warning("DuelFxManager: el recurso no es AudioStream: %s" % path)

		if fallback_duel_bgm != null:
			play_bgm(fallback_duel_bgm, from_position, restart_if_same)

		return

	play_bgm(res as AudioStream, from_position, restart_if_same)

func set_bgm_volume_db(value: float) -> void:
	bgm_volume_db = value

	if is_instance_valid(_bgm_player):
		_bgm_player.volume_db = bgm_volume_db


func _on_bgm_finished() -> void:
	if not loop_bgm:
		return

	if not is_instance_valid(_bgm_player):
		return

	if _bgm_player.stream == null:
		return

	_bgm_player.play(0.0)


# =========================
# SFX
# =========================
func play_sfx_key(key: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if _is_sfx_rate_limited(key):
		return

	var stream := _get_sfx_stream(key)
	if stream == null:
		return

	_register_sfx_played(key)

	var player := AudioStreamPlayer.new()
	player.name = "SFX_" + key
	player.stream = stream
	player.bus = sfx_bus
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale

	add_child(player)

	player.finished.connect(func():
		if is_instance_valid(player):
			player.queue_free()
	)

	player.play()


func _is_sfx_rate_limited(key: String) -> bool:
	if key != "draw":
		return false

	var now := Time.get_ticks_msec()
	var last := int(_last_sfx_time_msec.get(key, -999999))
	var min_ms := int(draw_sfx_min_interval * 1000.0)

	return now - last < min_ms


func _register_sfx_played(key: String) -> void:
	_last_sfx_time_msec[key] = Time.get_ticks_msec()

func _get_sfx_stream(key: String) -> AudioStream:
	match key:
		"draw":
			return draw_sfx

		"summon_faceup":
			return summon_faceup_sfx

		"summon_set":
			return summon_set_sfx

		"set_spelltrap":
			return set_spelltrap_sfx

		"spell_activate":
			return spell_activate_sfx

		"monster_effect_activate":
			return monster_effect_activate_sfx

		"trap_reactive":
			return trap_reactive_sfx

		"summon_by_effect":
			return summon_by_effect_sfx

		"destroy_vibration":
			return destroy_vibration_sfx

		"destroy_explosion":
			return destroy_explosion_sfx

		"thunder_destroy":
			return thunder_destroy_sfx

		"material_absorb":
			return material_absorb_sfx

		"fusion_intent":
			return fusion_intent_sfx

		"fusion_result":
			return fusion_result_sfx

		_:
			return null


# =========================
# VFX
# =========================
func apply_background_from_path(path: String) -> void:
	path = path.strip_edges()

	if not is_instance_valid(_background_target):
		_background_target = get_node_or_null(background_target_path)

	if path == "":
		_apply_background_texture(fallback_background)
		return

	if not ResourceLoader.exists(path):
		push_warning("DuelFxManager: no existe el background: %s" % path)
		_apply_background_texture(fallback_background)
		return

	var res := ResourceLoader.load(path)

	if res == null:
		push_warning("DuelFxManager: no se pudo cargar el background: %s" % path)
		_apply_background_texture(fallback_background)
		return

	if not (res is Texture2D):
		push_warning("DuelFxManager: el background no es Texture2D: %s" % path)
		_apply_background_texture(fallback_background)
		return

	_apply_background_texture(res as Texture2D)


func _apply_background_texture(texture: Texture2D) -> void:
	if texture == null:
		return

	if not is_instance_valid(_background_target):
		return

	if _background_target is TextureRect:
		(_background_target as TextureRect).texture = texture
		return

	if _background_target is Sprite2D:
		(_background_target as Sprite2D).texture = texture
		return

	push_warning("DuelFxManager: background_target no es TextureRect ni Sprite2D.")

func play_vfx_key_on_card(key: String, card: Node2D) -> void:
	if not is_instance_valid(card):
		return

	var scene := get_vfx_scene(key)
	if scene == null:
		return

	var fx = scene.instantiate()
	if not is_instance_valid(fx):
		return

	var parent_node := get_tree().current_scene
	if parent_node == null:
		parent_node = self

	parent_node.add_child(fx)

	if fx.has_method("setup_from_card"):
		fx.setup_from_card(card)

	elif fx is Node2D:
		var fx2d := fx as Node2D
		fx2d.set_as_top_level(true)
		fx2d.global_position = _get_card_visual_center_global(card)
		fx2d.global_rotation = card.global_rotation
		fx2d.scale = card.scale
		fx2d.z_index = card.z_index + 150

	if fx.has_method("play"):
		fx.play()

	if fx.has_signal("finished"):
		await fx.finished
	else:
		await get_tree().create_timer(0.35).timeout

	if is_instance_valid(fx):
		fx.queue_free()


func get_vfx_scene(key: String) -> PackedScene:
	match key:
		"default_activation":
			return default_activation_fx_scene

		"monster_reborn_summon":
			return monster_reborn_summon_fx_scene

		"thunder_destroy":
			return thunder_destroy_fx_scene

		"fusion_result_summoned":
			return fusion_result_summoned_vfx_scene

		"coin_toss":
			return coin_toss_fx_scene

		"exodia_win":
			return exodia_win_fx_scene
		_:
			return null


func _get_card_visual_center_global(card: Node2D) -> Vector2:
	if not is_instance_valid(card):
		return Vector2.ZERO

	var anchor := card.get_node_or_null("AnchorCenter") as Node2D
	if is_instance_valid(anchor):
		return anchor.global_position

	return card.global_position

func configure_for_opponent(opponent_data: Dictionary) -> void:
	var music_path := str(opponent_data.get("music", ""))
	var background_path := str(opponent_data.get("background", ""))

	play_bgm_from_path(music_path, 0.0, true)
	apply_background_from_path(background_path)
