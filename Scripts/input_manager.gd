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

	if Input.is_action_just_pressed("activate_from_hand") and not inputs_disabled:
		if $"../BattleManager".is_opponent_turn:
			return

		var hovered_card = _get_hovered_card()
		if not is_instance_valid(hovered_card):
			print("activate_from_hand: no hovered_card")
			return

		print("activate_from_hand hovered:", hovered_card.cardname, " zone=", str(hovered_card.current_zone), " kind=", str(hovered_card.kind), " race=", str(hovered_card.race))

		var bm0 = get_node_or_null("../BattleManager")
		if bm0 and bm0.has_method("try_activate_from_hand"):
			bm0.try_activate_from_hand(hovered_card)
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not inputs_disabled:
		var card = _get_card_under_mouse_any_side()
		if not is_instance_valid(card):
			return

		# solo cartas propias
		if str(card.owner_side).to_upper() != "PLAYER":
			return

		_show_context_menu_for_card(card, get_global_mouse_position())
		return

	if Input.is_action_just_pressed("change_pos") and not inputs_disabled:
		if $"../BattleManager".is_opponent_turn:
			return
		if card_manager_reference and card_manager_reference.is_dragging():
			return

		var space_state := get_world_2d().direct_space_state
		var parameters := PhysicsPointQueryParameters2D.new()
		parameters.position = get_global_mouse_position()
		parameters.collide_with_areas = true
		parameters.collision_mask = COLLISION_MASK_CARD
		var result := space_state.intersect_point(parameters)

		if result.size() > 0:
			var picked = result[0].collider.get_parent()
			if result.size() > 1:
				var highest_card = picked
				var highest_z = picked.z_index
				for hit in result:
					var c = hit.collider.get_parent()
					if is_instance_valid(c) and c.z_index > highest_z:
						highest_card = c
						highest_z = c.z_index
				picked = highest_card

			if is_instance_valid(picked) and str(picked.kind) == "MONSTER" and picked.has_method("is_on_field") and picked.is_on_field():
				var bm = $"../BattleManager"
				if bm and (picked in bm.player_cards_that_attacked_this_turn):
					return

				if bm and bm.has_method("_set_position"):
					bm._set_position(picked, "DEFENSE" if not bool(picked.in_defense) else "ATTACK")
				else:
					if picked.has_method("set_defense_position"):
						picked.set_defense_position(not bool(picked.in_defense))
					else:
						picked.in_defense = not bool(picked.in_defense)
		return

	if Input.is_action_just_pressed("star_guardian_changer") and not inputs_disabled:
		if $"../BattleManager".is_opponent_turn:
			return

		var p := get_global_mouse_position()
		var space_state2 := get_world_2d().direct_space_state
		var query := PhysicsPointQueryParameters2D.new()
		query.position = p
		query.collide_with_areas = true
		query.collision_mask = COLLISION_MASK_CARD

		var result2 := space_state2.intersect_point(query, 1)

		if result2.size() > 0:
			var card = result2[0].collider.get_parent()
			if card and card.card_type == "Monster" and card.card_slot_card_is_in:
				var bm2 := $"../BattleManager"
				if bm2 and (card in bm2.player_cards_that_attacked_this_turn):
					return
				card.toggle_guardian_star()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			emit_signal("left_mouse_button_clicked")
			if card_manager_reference and card_manager_reference.is_dragging():
				card_manager_reference.click_to_drop()
				return
			raycast_at_cursor()
		else:
			emit_signal("left_mouse_button_released")

	var can_fuse = !$"../CardManager".played_monster_card_this_turn

	if event.is_action_pressed("activate_effect"):
		if $"../BattleManager".is_opponent_turn:
			return

		var hovered_card2 = _get_hovered_card()
		if not is_instance_valid(hovered_card2):
			return

		if str(hovered_card2.kind).to_upper() == "SPELL":
			return

		var bm3 = get_node_or_null("../BattleManager")
		if bm3 and bm3.has_method("try_activate_card"):
			bm3.try_activate_card(hovered_card2)

	if event.is_action_pressed("select_for_fusion_generic") and can_fuse:
		if $"../BattleManager".is_opponent_turn:
			return

		var hovered_card3 = _get_hovered_card()
		if hovered_card3:
			var fusion_manager = $"../FusionManager"
			if fusion_manager and fusion_manager.is_animating_fusion:
				return
			if fusion_manager.can_select_material("generic"):
				fusion_manager.add_material(hovered_card3, "generic")

	if event.is_action_pressed("select_for_fusion_specific") and can_fuse:
		if $"../BattleManager".is_opponent_turn:
			return

		var hovered_card4 = _get_hovered_card()
		if hovered_card4:
			var fusion_manager2 = $"../FusionManager"
			if fusion_manager2.can_select_material("specific"):
				fusion_manager2.add_material(hovered_card4, "specific")

	if event.is_action_pressed("try_to_fuse") and can_fuse:
		if $"../BattleManager".is_opponent_turn:
			return

		var fusion_manager3 = $"../FusionManager"
		var result3 = await fusion_manager3.try_fusion("Player")

		if not result3.success:
			print("Fusión: ", result3.message)

	if event.is_action_pressed("cancel") and not inputs_disabled:
		$"../FusionManager".clear_materials()
		var bm := get_node_or_null("../BattleManager")
		if bm and bool(bm.get("equip_targeting")) and bm.has_method("_cancel_equip_targeting"):
			bm._cancel_equip_targeting()

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
					if bm != null and bm.has_method("resolve_equip_target"):
						bm.resolve_equip_target(card_clicked)
					return
			continue

		if (layer & COLLISION_MASK_OPPONENT_CARD) != 0:
			if bm != null and bool(bm.get("spell_targeting")):
				bm.receive_spell_target(card_clicked)
			else:
				bm.enemy_card_selected(card_clicked)
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


func _get_context_menu() -> PopupMenu:
	return get_node_or_null("../UILayer/CardContextMenu") as PopupMenu

func _show_context_menu_for_card(card, mouse_pos: Vector2) -> void:
	var menu := _get_context_menu()
	if menu == null:
		print("ContextMenu: falta ../UILayer/CardContextMenu en la escena.")
		return

	menu.clear()
	menu.set_meta("card", card)

	var zone := str(card.current_zone).to_upper() if ("current_zone" in card) else ""
	var is_in_hand := (zone == "HAND")
	var is_on_field = (card.has_method("is_on_field") and card.is_on_field())

	var kind := str(card.kind).to_upper()
	var spell_subtype := str(card.race).to_upper() 

	# --- Mano ---
	if is_in_hand:
		if kind == "MONSTER":
			menu.add_item("Jugar boca abajo", ACT_PLAY_FACEDOWN)
			menu.add_item("Jugar boca arriba", ACT_PLAY_FACEUP)

		elif kind == "TRAP":
			menu.add_item("Colocar", ACT_SET_SPELLTRAP)

		elif kind == "SPELL":
			menu.add_item("Activar", ACT_ACTIVATE_FROM_HAND)
			menu.add_item("Colocar", ACT_SET_SPELLTRAP)

		menu.add_separator()
		menu.add_item("Generic Fusion", ACT_FUSION_GENERIC)
		menu.add_item("Specific Fusion", ACT_FUSION_SPECIFIC)

	# --- Campo ---
	elif is_on_field:
		if kind == "SPELL":
			menu.add_item("Activar", ACT_ACTIVATE_ON_FIELD)

		elif kind == "MONSTER":
			var facedown := bool(card.face_down) if ("face_down" in card) else false

			if facedown:
				menu.add_item("Voltear", ACT_FLIP_FACEUP)
				menu.add_item("Cambiar posición", ACT_TOGGLE_POSITION)
				menu.add_item("Cambiar Guardian Star", ACT_CHANGE_GUARDIAN_STAR)
			else:
				menu.add_item("Cambiar posición", ACT_TOGGLE_POSITION)
				menu.add_item("Cambiar Guardian Star", ACT_CHANGE_GUARDIAN_STAR)

				if card.has_method("get_effects"):
					for e in (card.get_effects() as Array):
						if e is Dictionary and str(e.get("trigger","")).to_upper() == "ON_ACTIVATE":
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

	match id:
		ACT_ACTIVATE_FROM_HAND:
			if bm and bm.has_method("try_activate_from_hand"):
				bm.try_activate_from_hand(card)

		ACT_ACTIVATE_ON_FIELD:
			if bm and bm.has_method("try_activate_card"):
				bm.try_activate_card(card)

		ACT_SET_SPELLTRAP:
			if bm and bm.has_method("try_set_from_hand"):
				bm.try_set_from_hand(card)
			else:
				print("Falta BattleManager.try_set_from_hand(card)")

		ACT_PLAY_FACEDOWN:
			if bm and bm.has_method("try_play_monster_from_hand"):
				bm.try_play_monster_from_hand(card, true)
			else:
				print("Falta BattleManager.try_play_monster_from_hand(card, facedown)")

		ACT_PLAY_FACEUP:
			if bm and bm.has_method("try_play_monster_from_hand"):
				bm.try_play_monster_from_hand(card, false)
			else:
				print("Falta BattleManager.try_play_monster_from_hand(card, facedown)")

		ACT_TOGGLE_POSITION:
			if bm and bm.has_method("_set_position"):
				bm._set_position(card, "DEFENSE" if not bool(card.in_defense) else "ATTACK")

		ACT_FLIP_FACEUP:
			if bm and bm.has_method("reveal_card"):
				bm.reveal_card(card)

		ACT_CHANGE_GUARDIAN_STAR:
			if card.has_method("toggle_guardian_star"):
				card.toggle_guardian_star()

		ACT_ATTACK:
			if cm and ("selected_monster" in cm):
				cm.selected_monster = card

		ACT_FUSION_GENERIC:
			if fm and fm.has_method("add_material"):
				fm.add_material(card, "generic")

		ACT_FUSION_SPECIFIC:
			if fm and fm.has_method("add_material"):
				fm.add_material(card, "specific")
	
	var m := _get_context_menu() #Cuestionable
	if m != null:
		m.hide()
		m.set_meta("card", null)
