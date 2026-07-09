extends Node2D

const ACT_PLAY_FACEDOWN := 1
const ACT_PLAY_FACEUP := 2
const ACT_SET_SPELLTRAP := 3
const ACT_ACTIVATE_FROM_HAND := 4
const ACT_ACTIVATE_ON_FIELD := 5
const ACT_FLIP_FACEUP := 6
const ACT_TOGGLE_POSITION := 7
const ACT_CHANGE_GUARDIAN_STAR := 8
const ACT_ATTACK := 9
const ACT_FUSION_GENERIC := 10
const ACT_FUSION_SPECIFIC := 11

signal left_mouse_button_clicked
signal left_mouse_button_released

const COLLISION_MASK_CARD := 1
const COLLISION_MASK_OPPONENT_CARD := 8

var card_manager_reference
var inputs_disabled := false
var is_animating:= false

func _ready() -> void:
	card_manager_reference = $"../CardManager"

func _input(event: InputEvent) -> void:
	if is_animating:
		return

	var bm_main = _battle_manager()
	
	if _handle_card_selection_input(event, bm_main):
		return

	var opponent_turn := bm_main != null and bool(bm_main.get("is_opponent_turn"))

	# -------------------------
	# Activar Spell desde mano
	# -------------------------
	if Input.is_action_just_pressed("activate_from_hand") and not _duel_input_locked():
		if opponent_turn:
			return

		var hovered_card = _get_hovered_card()
		if not is_instance_valid(hovered_card):
			print("activate_from_hand: no hovered_card")
			return

		print(
			"activate_from_hand hovered:",
			hovered_card.cardname if ("cardname" in hovered_card) else hovered_card.name,
			" zone=", _card_zone(hovered_card),
			" kind=", _card_kind(hovered_card),
			" race=", str(hovered_card.race) if ("race" in hovered_card) else ""
		)

		if bm_main != null and bm_main.has_method("try_activate_from_hand"):
			bm_main.try_activate_from_hand(hovered_card)

		return

	# -------------------------
	# Click derecho: menú contextual
	# -------------------------
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not _duel_input_locked():
		if opponent_turn:
			return

		var right_clicked_card = _get_card_under_mouse_any_side()
		if not is_instance_valid(right_clicked_card):
			return

		if not _is_player_card(right_clicked_card):
			return

		_show_context_menu_for_card(right_clicked_card, get_global_mouse_position())
		return

	# -------------------------
	# Cambiar posición
	# -------------------------
	if Input.is_action_just_pressed("change_pos") and not _duel_input_locked():
		if opponent_turn:
			return

		if card_manager_reference and card_manager_reference.is_dragging():
			return

		var position_card = _get_hovered_card()
		if not _is_player_card(position_card):
			return

		if not _is_monster_on_field(position_card):
			return

		if _has_attacked_this_turn(position_card):
			return

		_toggle_monster_position(position_card)
		return

	# -------------------------
	# Cambiar Guardian Star
	# -------------------------
	if Input.is_action_just_pressed("star_guardian_changer") and not _duel_input_locked():
		if opponent_turn:
			return

		if card_manager_reference and card_manager_reference.is_dragging():
			return

		var guardian_card = _get_hovered_card()
		if not _is_player_card(guardian_card):
			return

		if not _is_monster_on_field(guardian_card):
			return

		if _has_attacked_this_turn(guardian_card):
			return

		if guardian_card.has_method("toggle_guardian_star"):
			guardian_card.toggle_guardian_star()

		return

	# -------------------------
	# Activar efecto de monstruo en campo
	# -------------------------
	if event.is_action_pressed("activate_effect") and not _duel_input_locked():
		if opponent_turn:
			return

		var effect_card = _get_hovered_card()
		if not is_instance_valid(effect_card):
			return

		if _card_kind(effect_card) == "SPELL":
			return

		if bm_main != null:
			var activation_service = bm_main.get("card_activation_service")

			if activation_service != null and activation_service.has_method("try_activate_card"):
				activation_service.try_activate_card(effect_card)

		return

	# -------------------------
	# Fusión
	# Importante:
	# No usamos _duel_input_locked(), porque ese helper incluye inputs_disabled.
	# La fusión solo debe bloquearse por animación/duelo animando.
	# -------------------------
	var card_manager := get_node_or_null("../CardManager")
	var can_fuse := true

	if card_manager != null and "played_monster_card_this_turn" in card_manager:
		can_fuse = not bool(card_manager.played_monster_card_this_turn)

	if event.is_action_pressed("select_for_fusion_generic") and can_fuse and not _fusion_input_locked():
		if opponent_turn:
			return

		var fusion_card_generic = _get_hovered_card()
		if is_instance_valid(fusion_card_generic):
			var fusion_manager_generic = get_node_or_null("../FusionManager")
			if fusion_manager_generic != null and bool(fusion_manager_generic.get("is_animating_fusion")):
				return

			if fusion_manager_generic != null and fusion_manager_generic.has_method("can_select_material"):
				if fusion_manager_generic.can_select_material("generic"):
					fusion_manager_generic.add_material(fusion_card_generic, "generic")

		return

	if event.is_action_pressed("select_for_fusion_specific") and can_fuse and not _fusion_input_locked():
		if opponent_turn:
			return

		var fusion_card_specific = _get_hovered_card()
		if is_instance_valid(fusion_card_specific):
			var fusion_manager_specific = get_node_or_null("../FusionManager")
			if fusion_manager_specific != null and bool(fusion_manager_specific.get("is_animating_fusion")):
				return

			if fusion_manager_specific != null and fusion_manager_specific.has_method("can_select_material"):
				if fusion_manager_specific.can_select_material("specific"):
					fusion_manager_specific.add_material(fusion_card_specific, "specific")

		return

	if event.is_action_pressed("try_to_fuse") and can_fuse and not _fusion_input_locked():
		if opponent_turn:
			return

		var fusion_manager_try = get_node_or_null("../FusionManager")
		if fusion_manager_try == null:
			return

		var fusion_result = await fusion_manager_try.try_fusion("Player")

		if not fusion_result.success:
			print("Fusión: ", fusion_result.message)

		return

	# -------------------------
	# Click izquierdo
	# -------------------------
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _duel_input_locked() or opponent_turn:
			return

		if event.pressed:
			emit_signal("left_mouse_button_clicked")

			if card_manager_reference and card_manager_reference.is_dragging():
				await card_manager_reference.click_to_drop()
				return

			raycast_at_cursor()
		else:
			emit_signal("left_mouse_button_released")

		return

	# -------------------------
	# Cancelar
	# -------------------------
	if event.is_action_pressed("cancel") and not _duel_input_locked():
		var fusion_manager_cancel = get_node_or_null("../FusionManager")
		if fusion_manager_cancel != null and fusion_manager_cancel.has_method("clear_materials"):
			fusion_manager_cancel.clear_materials()

		if bm_main != null and bool(bm_main.get("equip_targeting")) and bm_main.has_method("_cancel_equip_targeting"):
			bm_main._cancel_equip_targeting()

		return

func _get_hovered_card():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD
	var result = space_state.intersect_point(parameters)
	
	if result.size() > 0:
		return get_card_with_highest_z_index(result)
	return null

func get_card_with_highest_z_index(cards):
	var highest_z_card = cards[0].collider.get_parent()
	var highest_z_index = highest_z_card.z_index
	for i in range(1, cards.size()):
		var current_card = cards[i].collider.get_parent()
		if current_card.z_index > highest_z_index:
			highest_z_card = current_card
			highest_z_index = current_card.z_index
	return highest_z_card

func raycast_at_cursor() -> void:
	if inputs_disabled:
		var ui := get_viewport().gui_get_hovered_control()
		if ui != null:
			return
		return

	var bm := get_node_or_null("../BattleManager")
	var equip_mode := (bm != null and bool(bm.get("equip_targeting")))

	var space_state = get_world_2d().direct_space_state
	var p := PhysicsPointQueryParameters2D.new()
	p.position = get_global_mouse_position()
	p.collide_with_areas = true

	for hit in space_state.intersect_point(p):
		var area = hit.collider
		var layer = area.collision_layer
		var card_clicked = area.get_parent()

		if equip_mode:
			if is_instance_valid(card_clicked) and card_clicked.has_method("is_on_field") and card_clicked.is_on_field():
				var k := ""
				if "kind" in card_clicked:
					k = str(card_clicked.kind).to_upper()
				elif card_clicked.has_method("is_monster") and card_clicked.is_monster():
					k = "MONSTER"

				if k == "MONSTER":
					if bm != null and bm.equip_service.has_method("resolve_equip_target"):
						bm.equip_service.resolve_equip_target(card_clicked)
					return
			continue

		if (layer & COLLISION_MASK_OPPONENT_CARD) != 0:
			if bm == null:
				return

			var combat_service = bm.get("combat_service")
			var card_activation_service = bm.get("card_activation_service")
			var cm := get_node_or_null("../CardManager")

			# Si ya hay un monstruo propio seleccionado para atacar,
			# este click sobre carta rival debe resolverse como ataque.
			if cm != null and ("selected_monster" in cm) and is_instance_valid(cm.selected_monster):
				if combat_service != null and combat_service.has_method("enemy_card_selected"):
					combat_service.enemy_card_selected(card_clicked)
				else:
					push_warning("InputManager: combat_service no tiene enemy_card_selected(card).")
				return

			var spell_targeting := false

			if is_instance_valid(card_activation_service) and ("spell_targeting" in card_activation_service):
				spell_targeting = bool(card_activation_service.spell_targeting)

			if spell_targeting:
				if card_activation_service.has_method("receive_spell_target"):
					card_activation_service.receive_spell_target(card_clicked)
				else:
					push_warning("InputManager: card_activation_service no puede recibir spell target.")
				return

			if combat_service != null and combat_service.has_method("enemy_card_selected"):
				combat_service.enemy_card_selected(card_clicked)
			else:
				push_warning("InputManager: combat_service no tiene enemy_card_selected(card).")

			return

		if (layer & COLLISION_MASK_CARD) != 0:
			if is_instance_valid(card_clicked):
				card_manager_reference.card_clicked(card_clicked)
			return

func _get_card_under_mouse_any_side():
	var space_state := get_world_2d().direct_space_state
	var q := PhysicsPointQueryParameters2D.new()
	q.position = get_global_mouse_position()
	q.collide_with_areas = true
	q.collision_mask = COLLISION_MASK_CARD | COLLISION_MASK_OPPONENT_CARD

	var hits := space_state.intersect_point(q)
	if hits.size() == 0:
		return null

	var best = hits[0].collider.get_parent()
	var best_z = best.z_index
	for h in hits:
		var c = h.collider.get_parent()
		if is_instance_valid(c) and c.z_index > best_z:
			best = c
			best_z = c.z_index
	return best

func _handle_card_selection_input(event: InputEvent, bm_main: Node) -> bool:
	if bm_main == null:
		return false

	var selection_service = bm_main.get("selection_service")

	if selection_service == null:
		return false

	if not selection_service.has_method("is_selecting_card"):
		return false

	if not bool(selection_service.is_selecting_card()):
		return false

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var selected_card = _get_card_under_mouse_any_side()

			if is_instance_valid(selected_card):
				if selection_service.has_method("try_receive_card_selection"):
					selection_service.try_receive_card_selection(selected_card)

			get_viewport().set_input_as_handled()
			return true

		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if _selection_can_be_canceled(selection_service):
				if selection_service.has_method("cancel_card_selection"):
					selection_service.cancel_card_selection()

			get_viewport().set_input_as_handled()
			return true

	if event.is_action_pressed("cancel"):
		if _selection_can_be_canceled(selection_service):
			if selection_service.has_method("cancel_card_selection"):
				selection_service.cancel_card_selection()

		get_viewport().set_input_as_handled()
		return true

	get_viewport().set_input_as_handled()
	return true

func _selection_can_be_canceled(selection_service: Node) -> bool:
	if selection_service == null:
		return false

	if selection_service.has_method("is_current_selection_cancelable"):
		return bool(selection_service.is_current_selection_cancelable())

	return true

func _get_context_menu() -> PopupMenu:
	return get_node_or_null("../UILayer/CardContextMenu") as PopupMenu

func _show_context_menu_for_card(card, mouse_pos: Vector2) -> void:
	var menu := _get_context_menu()
	if menu == null:
		print("ContextMenu: falta ../UILayer/CardContextMenu en la escena.")
		return

	menu.clear()
	menu.set_meta("card", card)

	var zone := _card_zone(card)
	var is_in_hand := (zone == "HAND")
	var is_on_field = (card.has_method("is_on_field") and card.is_on_field())

	var kind := _card_kind(card)

	# --- Mano ---
	if is_in_hand:
		if kind == "MONSTER":
			if _can_fuse_now():
				menu.add_item("Jugar boca abajo", ACT_PLAY_FACEDOWN)
				menu.add_item("Jugar boca arriba", ACT_PLAY_FACEUP)

		elif kind == "TRAP":
			menu.add_item("Colocar", ACT_SET_SPELLTRAP)

		elif kind == "SPELL":
			menu.add_item("Activar", ACT_ACTIVATE_FROM_HAND)
			menu.add_item("Colocar", ACT_SET_SPELLTRAP)

		if _can_fuse_now():
			menu.add_separator()
			menu.add_item("Generic Fusion", ACT_FUSION_GENERIC)
			menu.add_item("Specific Fusion", ACT_FUSION_SPECIFIC)

	# --- Campo ---
	elif is_on_field:
		if kind == "SPELL":
			menu.add_item("Activar", ACT_ACTIVATE_ON_FIELD)

		elif kind == "TRAP":
			pass

		elif kind == "MONSTER":
			var facedown := bool(card.face_down) if ("face_down" in card) else false

			if facedown:
				if _can_manual_flip_faceup(card):
					menu.add_item("Voltear", ACT_FLIP_FACEUP)

				menu.add_item("Cambiar posición", ACT_TOGGLE_POSITION)
				menu.add_item("Cambiar Guardian Star", ACT_CHANGE_GUARDIAN_STAR)
			else:
				menu.add_item("Cambiar posición", ACT_TOGGLE_POSITION)
				menu.add_item("Cambiar Guardian Star", ACT_CHANGE_GUARDIAN_STAR)

				if card.has_method("get_effects"):
					for e in (card.get_effects() as Array):
						if e is Dictionary and str(e.get("trigger", "")).to_upper() == "ON_ACTIVATE":
							menu.add_item("Activar", ACT_ACTIVATE_ON_FIELD)
							break

				menu.add_item("Atacar", ACT_ATTACK)

	if not menu.id_pressed.is_connected(_on_context_menu_id_pressed):
		menu.id_pressed.connect(_on_context_menu_id_pressed)

	await get_tree().process_frame

	var size := menu.size
	var pos := mouse_pos
	pos.y -= size.y + 8
	menu.position = pos
	menu.popup()

func _can_manual_flip_faceup(card) -> bool:
	if not is_instance_valid(card):
		return false

	var bm = _battle_manager()
	if bm == null:
		return true

	var runtime_service = bm.get("card_runtime_service")

	if runtime_service != null and runtime_service.has_method("can_manually_flip_faceup"):
		return bool(runtime_service.can_manually_flip_faceup(card))

	return true

func _on_context_menu_id_pressed(id: int) -> void:
	var menu := _get_context_menu()
	if menu == null:
		return

	var card = menu.get_meta("card", null)
	if not is_instance_valid(card):
		return

	var bm := get_node_or_null("../BattleManager")
	var cm := get_node_or_null("../CardManager")
	var fm := get_node_or_null("../FusionManager")
	var card_activation_service = bm.get("card_activation_service") if bm != null else null
	var card_play_service = bm.get("card_play_service") if bm != null else null
	var reveal_service = bm.get("reveal_service") if bm != null else null
	var animation_service = bm.get("animation_service") if bm != null else null

	if bm != null and bool(bm.get("is_opponent_turn")):
		return

	if is_animating:
		return

	if animation_service != null and animation_service.has_method("is_duel_animating"):
		if bool(animation_service.is_duel_animating()):
			return

	match id:
		ACT_ACTIVATE_FROM_HAND:
			if card_activation_service != null and card_activation_service.has_method("try_activate_from_hand"):
				card_activation_service.try_activate_from_hand(card)

		ACT_ACTIVATE_ON_FIELD:
			if bm and bm.card_activation_service.has_method("try_activate_card"):
				bm.card_activation_service.try_activate_card(card)

		ACT_SET_SPELLTRAP:
			if card_play_service != null and card_play_service.has_method("try_set_from_hand"):
				card_play_service.try_set_from_hand(card)
			else:
				print("Falta card_play_service.try_set_from_hand(card)")

		ACT_PLAY_FACEDOWN:
			if not _can_fuse_now():
				return

			if card_play_service != null and card_play_service.has_method("try_play_monster_from_hand"):
				card_play_service.try_play_monster_from_hand(card, true)
			else:
				print("Falta card_play_service.try_play_monster_from_hand(card, facedown)")

		ACT_PLAY_FACEUP:
			if not _can_fuse_now():
				return

			if card_play_service != null and card_play_service.has_method("try_play_monster_from_hand"):
				card_play_service.try_play_monster_from_hand(card, false)
			else:
				print("Falta card_play_service.try_play_monster_from_hand(card, facedown)")

		ACT_TOGGLE_POSITION:
			if not _can_change_battle_state(card):
				return

			await _toggle_monster_position(card)

		ACT_FLIP_FACEUP:
			if not _can_change_battle_state(card):
				return

			if not _can_manual_flip_faceup(card):
				return

			if reveal_service != null and reveal_service.has_method("reveal_card"):
				reveal_service.reveal_card(card)

		ACT_CHANGE_GUARDIAN_STAR:
			if not _can_change_battle_state(card):
				return

			if card.has_method("toggle_guardian_star"):
				card.toggle_guardian_star()

		ACT_ATTACK:
			if cm and ("selected_monster" in cm):
				cm.selected_monster = card

		ACT_FUSION_GENERIC:
			if not _can_fuse_now():
				return

			if not _is_player_card(card):
				return

			if _card_zone(card) != "HAND":
				return

			if fm and fm.has_method("can_select_material") and fm.has_method("add_material"):
				if fm.can_select_material("generic"):
					fm.add_material(card, "generic")

		ACT_FUSION_SPECIFIC:
			if not _can_fuse_now():
				return

			if not _is_player_card(card):
				return

			if _card_zone(card) != "HAND":
				return

			if fm and fm.has_method("can_select_material") and fm.has_method("add_material"):
				if fm.can_select_material("specific"):
					fm.add_material(card, "specific")

	var m := _get_context_menu()
	if m != null:
		m.hide()
		m.set_meta("card", null)

#HELPERS:
func _battle_manager():
	return get_node_or_null("../BattleManager")


func _duel_input_locked() -> bool:
	if is_animating:
		return true

	if inputs_disabled:
		return true

	var bm = _battle_manager()
	if bm != null and bm.animation_service.has_method("is_duel_animating"):
		if bool(bm.animation_service.is_duel_animating()):
			return true

	return false


func _card_kind(card) -> String:
	if not is_instance_valid(card):
		return ""

	if "kind" in card:
		return str(card.kind).to_upper()

	if card.has_method("is_monster") and card.is_monster():
		return "MONSTER"

	return ""


func _card_zone(card) -> String:
	if not is_instance_valid(card):
		return ""

	if "current_zone" in card:
		return str(card.current_zone).to_upper()

	return ""


func _card_owner(card) -> String:
	if not is_instance_valid(card):
		return ""

	if "owner_side" in card:
		return str(card.owner_side).to_upper()

	return ""


func _is_player_card(card) -> bool:
	return is_instance_valid(card) and _card_owner(card) == "PLAYER"


func _is_monster_card(card) -> bool:
	if not is_instance_valid(card):
		return false

	if card.has_method("is_monster"):
		return bool(card.is_monster())

	return _card_kind(card) == "MONSTER"


func _is_monster_on_field(card) -> bool:
	if not _is_monster_card(card):
		return false

	if card.has_method("is_on_field"):
		return bool(card.is_on_field())

	return _card_zone(card) == "FIELD"


func _has_attacked_this_turn(card) -> bool:
	if not is_instance_valid(card):
		return false

	var bm = _battle_manager()
	if bm == null:
		return false

	if "player_cards_that_attacked_this_turn" in bm:
		return card in bm.player_cards_that_attacked_this_turn

	return false

func _toggle_monster_position(card) -> void:
	if not is_instance_valid(card):
		return

	var bm = _battle_manager()
	var new_position := "DEFENSE"

	if "in_defense" in card:
		new_position = "ATTACK" if bool(card.in_defense) else "DEFENSE"

	if bm != null:
		var combat_service = bm.get("combat_service")

		if combat_service != null and combat_service.has_method("_set_position"):
			combat_service._set_position(card, new_position)
			return

	if card.has_method("set_defense_position"):
		card.set_defense_position(not bool(card.in_defense))
	elif "in_defense" in card:
		card.in_defense = not bool(card.in_defense)

func _can_change_battle_state(card) -> bool:
	if not _is_player_card(card):
		return false

	if not _is_monster_on_field(card):
		return false

	if _has_attacked_this_turn(card):
		return false

	return true

func _fusion_input_locked() -> bool:
	if is_animating:
		return true

	var bm = _battle_manager()
	if bm != null and bm.animation_service.has_method("is_duel_animating"):
		if bool(bm.animation_service.is_duel_animating()):
			return true

	return false

func _can_fuse_now() -> bool:
	var cm := get_node_or_null("../CardManager")
	if cm == null:
		return true

	if "played_monster_card_this_turn" in cm:
		return not bool(cm.played_monster_card_this_turn)

	return true
