extends Node
class_name DuelCombatService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null
var kw_service: DuelKeywordService = null
var ui_service: DuelUiService = null
var reveal_service: DuelRevealService = null
var atk_state_service: DuelAttackStateService = null
var stat_service: DuelStatService = null
var damage_service: DuelDamageService = null
var turn_service: DuelTurnService = null
var animation_service: DuelAnimationService = null
var destruction_service: DuelDestructionService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service
	kw_service = bm.kw_service
	ui_service = bm.ui_service
	reveal_service = bm.reveal_service
	atk_state_service = bm.atk_state_service
	stat_service = bm.stat_service
	damage_service = bm.damage_service
	turn_service = bm.turn_service
	animation_service = bm.animation_service
	destruction_service = bm.destruction_service

func can_attack_directly(attacker_card):
	if not is_instance_valid(attacker_card):
		return
	if attacker_card.has_meta("only_direct_attack") and attacker_card.get_meta("only_direct_attack"):
		return true
	if attacker_card.has_meta("can_direct_attack") and attacker_card.get_meta("can_direct_attack"):
		return true
			
	var defenders = _live_defenders_for("Player" if zone_service._owner_of(attacker_card) == "Opponent" else "Opponent")
	return defenders.size() == 0

func attack(atk_card, defending, attacker) -> void:
	if not is_instance_valid(atk_card):
		return

	if card_runtime_service._card_kind(atk_card) != "MONSTER":
		return

	if bm.duel_finished:
		return

	var attacker_owner := card_runtime_service._norm_owner(attacker)

	if kw_service._has_kw(atk_card, "PARALYZED"):
		_release_player_input_if_needed(attacker_owner)
		return

	if not atk_state_service._can_card_declare_attack_against(
		atk_card,
		defending,
		attacker_owner
	):
		_release_player_input_if_needed(attacker_owner)
		return

	if card_runtime_service._is_card_face_down(atk_card):
		reveal_service.reveal_card(atk_card)

	var battle_ctx := {
		"battle_manager": bm,
		"source": atk_card,
		"attacker": atk_card,
		"defender": defending,
		"attacker_owner": attacker_owner,
		"controller": attacker_owner,
		"turn_owner": (
			"Opponent"
			if bm.is_opponent_turn
			else "Player"
		),
		"prevent_attack": false,
		"attack_negated": false,
		"suppress_trap_reactions": (
			atk_state_service
			._attacker_suppresses_traps(atk_card)
		)
	}

	bm.emit_signal(
		"attack_declared",
		atk_card,
		defending,
		attacker_owner
	)

	event_service._emit_duel_event(
		"ON_ATTACK_DECLARATION",
		battle_ctx
	)

	if bool(battle_ctx.get("prevent_attack", false)) \
	or bool(battle_ctx.get("attack_negated", false)):
		_release_player_input_if_needed(attacker_owner)
		return

	# Monstruos que sólo pueden atacar directamente.
	if bool(atk_card.get_meta("only_direct_attack", false)):
		if is_instance_valid(defending):
			_release_player_input_if_needed(attacker_owner)
			return

		await damage_service.direct_attack(
			atk_card,
			attacker_owner
		)

		_release_player_input_if_needed(attacker_owner)
		return

	# Ataque directo normal.
	if not is_instance_valid(defending):
		if attacker_owner == "Opponent":
			var defenders = bm.player_cards_on_battlefield.filter(
				func(card):
					return (
						is_instance_valid(card)
						and card_runtime_service._card_kind(card)
							== "MONSTER"
					)
			)

			if defenders.is_empty():
				await damage_service.direct_attack(
					atk_card,
					"Opponent"
				)
		else:
			await damage_service.direct_attack(
				atk_card,
				"Player"
			)

		_release_player_input_if_needed(attacker_owner)
		return

	# A partir de acá necesariamente hay una batalla
	# entre dos monstruos.
	reveal_service.reveal_card(defending)

	await event_service._trigger_on_attack_effects(
		atk_card,
		attacker_owner,
		battle_ctx
	)

	if not is_instance_valid(atk_card):
		_release_player_input_if_needed(attacker_owner)
		return

	# Alguna reacción eliminó al objetivo antes del cálculo.
	if not is_instance_valid(defending):
		if attacker_owner == "Opponent":
			var remaining_defenders = _live_defenders_for(
				"Player"
			)

			if remaining_defenders.is_empty():
				await damage_service.direct_attack(
					atk_card,
					"Opponent"
				)

		_release_player_input_if_needed(attacker_owner)
		return

	if bm.duel_finished:
		return

	var guardian_star_manager = $"../../GuardianStarManager"

	var attacker_star = (
		atk_card.current_guardian_star()
		if atk_card.has_method("current_guardian_star")
		else ""
	)

	var defender_star = (
		defending.current_guardian_star()
		if defending.has_method("current_guardian_star")
		else ""
	)

	var guardian_bonuses = (
		guardian_star_manager.compute_bonuses(
			attacker_star,
			defender_star
		)
		if guardian_star_manager
		else {
			"attacker_atk": 0,
			"attacker_def": 0,
			"defender_atk": 0,
			"defender_def": 0
		}
	)

	if int(guardian_bonuses.attacker_atk) > 0 \
	or int(guardian_bonuses.attacker_def) > 0:
		if atk_card.has_method(
			"play_guardian_star_bonus_animation"
		):
			await atk_card.play_guardian_star_bonus_animation(
				attacker_star
			)

	if int(guardian_bonuses.defender_atk) > 0 \
	or int(guardian_bonuses.defender_def) > 0:
		if defending.has_method(
			"play_guardian_star_bonus_animation"
		):
			await defending.play_guardian_star_bonus_animation(
				defender_star
			)

	await turn_service.action_waiter()

	if not is_instance_valid(atk_card) \
	or not is_instance_valid(defending):
		_release_player_input_if_needed(attacker_owner)
		return

	var base_attacker_atk := int(
		atk_card.get_effective_atk()
		if atk_card.has_method("get_effective_atk")
		else atk_card.atk
	)

	var base_defender_atk := int(
		defending.get_effective_atk()
		if defending.has_method("get_effective_atk")
		else defending.atk
	)

	var base_defender_def := int(
		defending.get_effective_def()
		if defending.has_method("get_effective_def")
		else defending.def
	)

	var final_attacker_atk := (
		base_attacker_atk
		+ int(guardian_bonuses.attacker_atk)
	)

	var final_defender_atk := (
		base_defender_atk
		+ int(guardian_bonuses.defender_atk)
	)

	var final_defender_def := (
		base_defender_def
		+ int(guardian_bonuses.defender_def)
	)

	await _resolve_monster_battle(
		atk_card,
		defending,
		attacker_owner,
		final_attacker_atk,
		final_defender_atk,
		final_defender_def
	)

func _resolve_monster_battle(
	atk_card: Node,
	defending: Node,
	attacker: String,
	atk_power: int,
	def_atk_power: int,
	def_def_power: int
) -> void:
	var attacker_owner := card_runtime_service._norm_owner(
		attacker
	)

	var result := _calculate_monster_battle_result(
		atk_card,
		defending,
		attacker_owner,
		atk_power,
		def_atk_power,
		def_def_power
	)

	var player_hp_before = bm.player_hp
	var opponent_hp_before = bm.opponent_hp

	var attacker_is_player := attacker_owner == "Player"

	var player_destroyed := (
		bool(
			result.get(
				"attacker_destroyed_by_battle",
				false
			)
		)
		if attacker_is_player
		else bool(
			result.get(
				"defender_destroyed_by_battle",
				false
			)
		)
	)

	var opponent_destroyed := (
		bool(
			result.get(
				"defender_destroyed_by_battle",
				false
			)
		)
		if attacker_is_player
		else bool(
			result.get(
				"attacker_destroyed_by_battle",
				false
			)
		)
	)

	var presentation_request := result.duplicate(true)

	presentation_request["attacker"] = atk_card
	presentation_request["defender"] = defending
	presentation_request["player_hp_before"] = player_hp_before
	presentation_request["opponent_hp_before"] = opponent_hp_before
	presentation_request["player_destroyed_by_battle"] = \
		player_destroyed
	presentation_request["opponent_destroyed_by_battle"] = \
		opponent_destroyed

	var damage_state := {
		"applied": false
	}

	var apply_damage := func() -> void:
		if bool(damage_state.get("applied", false)):
			return

		# Se marca antes de aplicar el daño para impedir
		# cualquier segunda ejecución del callback que sino rompe los webos en el battle presentation.
		damage_state["applied"] = true

		var damage := int(
			result.get(
				"battle_damage",
				0
			)
		)

		var target_owner := str(
			result.get(
				"damage_target_owner",
				""
			)
		)

		if damage <= 0 or target_owner == "":
			return

		damage_service._apply_battle_damage_to_side(
			target_owner,
			damage,
			result.get("damage_source", null),
			result.get("damage_other_card", null)
		)

	var presentation = await \
		animation_service.begin_battle_presentation(
			presentation_request,
			apply_damage
		)

	# Fallback para el caso en que la escena no exista,
	# falle al instanciarse o no emita damage_cue.
	if not bool(damage_state.get("applied", false)):
		apply_damage.call()

	var after_ctx := _emit_after_battle_with_monster(
		atk_card,
		defending,
		attacker_owner,
		str(result["defender_owner"]),
		str(result["result"]),
		str(result["battle_position"]),
		int(result["battle_damage"]),
		bool(
			result["attacker_destroyed_by_battle"]
		),
		bool(
			result["defender_destroyed_by_battle"]
		)
	)

	if not _battle_pair_removed_after_damage(after_ctx):
		_apply_battle_destructions_without_field_animation(
			atk_card,
			defending,
			result
		)

	await animation_service.finish_battle_presentation(
		presentation
	)

	var attacker_ref: Node = (
		atk_card
		if is_instance_valid(atk_card)
		else null
	)

	var defender_ref: Node = (
		defending
		if is_instance_valid(defending)
		else null
	)

	_finish_resolved_battle(
		attacker_ref,
		defender_ref,
		attacker_owner,
		str(result["result"])
	)

func _calculate_monster_battle_result(
	atk_card: Node,
	defending: Node,
	attacker_owner: String,
	attacker_atk: int,
	defender_atk: int,
	defender_def: int
) -> Dictionary:
	attacker_owner = card_runtime_service._norm_owner(
		attacker_owner
	)

	var defender_owner := card_runtime_service._norm_owner(
		zone_service._owner_of(defending)
	)

	if defender_owner == "":
		defender_owner = (
			"Opponent"
			if attacker_owner == "Player"
			else "Player"
		)

	var result := {
		"result": "tie",
		"battle_position": (
			"DEFENSE"
			if defending.in_defense
			else "ATTACK"
		),
		"battle_damage": 0,
		"damage_target_owner": "",
		"damage_source": null,
		"damage_other_card": null,
		"attacker_destroyed_by_battle": false,
		"defender_destroyed_by_battle": false,
		"attacker_owner": attacker_owner,
		"defender_owner": defender_owner
	}

	if defending.in_defense:
		if attacker_atk > defender_def:
			result["result"] = "win"
			result["defender_destroyed_by_battle"] = true

			var has_piercing := (
				kw_service._has_kw(
					atk_card,
					"PIERCING"
				)
				or bool(
					atk_card.get_meta(
						"piercing_damage",
						false
					)
				)
			)

			if has_piercing:
				result["battle_damage"] = (
					attacker_atk - defender_def
				)

				result["damage_target_owner"] = (
					defender_owner
				)

				result["damage_source"] = atk_card
				result["damage_other_card"] = defending

		elif attacker_atk < defender_def:
			result["result"] = "lose"

			result["battle_damage"] = (
				defender_def - attacker_atk
			)

			result["damage_target_owner"] = (
				attacker_owner
			)

			result["damage_source"] = defending
			result["damage_other_card"] = atk_card

		# Si ATK == DEF:
		# no hay daño ni destrucción.

		return result

	# Ataque contra monstruo en posición de ataque.
	if attacker_atk == defender_atk:
		result["result"] = "tie"
		result["attacker_destroyed_by_battle"] = true
		result["defender_destroyed_by_battle"] = true

	elif attacker_atk > defender_atk:
		result["result"] = "win"
		result["defender_destroyed_by_battle"] = true

		result["battle_damage"] = (
			attacker_atk - defender_atk
		)

		result["damage_target_owner"] = defender_owner
		result["damage_source"] = atk_card
		result["damage_other_card"] = defending

	else:
		result["result"] = "lose"
		result["attacker_destroyed_by_battle"] = true

		result["battle_damage"] = (
			defender_atk - attacker_atk
		)

		result["damage_target_owner"] = attacker_owner
		result["damage_source"] = defending
		result["damage_other_card"] = atk_card

	return result

func _apply_battle_destructions_without_field_animation(
	atk_card: Node,
	defending: Node,
	result: Dictionary
) -> void:
	var attacker_owner := str(
		result.get("attacker_owner", "")
	)

	var defender_owner := str(
		result.get("defender_owner", "")
	)

	if bool(
		result.get(
			"attacker_destroyed_by_battle",
			false
		)
	):
		destruction_service.destroy_card(
			atk_card,
			attacker_owner,
			"DESTROY_BATTLE",
			{
				"skip_destroy_animation": true
			}
		)

	if bool(
		result.get(
			"defender_destroyed_by_battle",
			false
		)
	):
		destruction_service.destroy_card(
			defending,
			defender_owner,
			"DESTROY_BATTLE",
			{
				"skip_destroy_animation": true
			}
		)

func _finish_resolved_battle(
	atk_card: Node,
	defending: Node,
	attacker_owner: String,
	result: String
) -> void:
	var valid_attacker: Node = (
		atk_card
		if is_instance_valid(atk_card)
		else null
	)

	var valid_defender: Node = (
		defending
		if is_instance_valid(defending)
		else null
	)

	if is_instance_valid(valid_attacker):
		event_service._trigger_on_attack(
			valid_attacker,
			attacker_owner,
			{
				"phase": "after_damage",
				"attacker": valid_attacker,
				"defender": valid_defender,
				"result": result
			}
		)

	var cards_to_clear: Array = []

	if is_instance_valid(valid_attacker):
		cards_to_clear.append(valid_attacker)

	if is_instance_valid(valid_defender):
		cards_to_clear.append(valid_defender)

	if not cards_to_clear.is_empty():
		stat_service._clear_bonuses(cards_to_clear)

	if is_instance_valid(valid_attacker):
		atk_state_service._register_attack_spent(
			valid_attacker,
			attacker_owner,
			valid_defender
		)

	if attacker_owner == "Player":
		ui_service._enable_player_input()

func _live_defenders_for(attacker_side: String):
	var list = []
	if attacker_side == "Player":
		for d in bm.opponent_cards_on_battlefield:
			if is_instance_valid(d):
				list.append(d)
	else:
		for d in bm.player_cards_on_battlefield:
			if is_instance_valid(d):
				list.append(d)
	return list

func enemy_card_selected(defending_card) -> void:
	if animation_service.is_duel_animating():
		return
	if bm.duel_finished:
		return
	if bm.is_opponent_turn:
		return
	if not is_instance_valid(defending_card):
		return
	if card_runtime_service._card_kind(defending_card) != "MONSTER":
		return

	var attacker = $"../../CardManager".selected_monster
	if not is_instance_valid(attacker):
		return
	if card_runtime_service._card_kind(attacker) != "MONSTER":
		return
	if attacker.in_defense:
		return
	if kw_service._has_kw(attacker, "PARALYZED"):
		return
	if attacker in bm.player_cards_that_attacked_this_turn and not kw_service._has_kw(attacker, "MULTI_ATTACK_ALL"):
		return

	$"../../InputManager".inputs_disabled = true
	ui_service.enable_end_turn_button(false)

	var card_manager := get_node_or_null("../../CardManager")

	if card_manager != null \
	and card_manager.has_method("unselect_selected_monster"):
		card_manager.unselect_selected_monster()

	await attack(attacker, defending_card, "Player")

	$"../../InputManager".inputs_disabled = false
	ui_service.enable_end_turn_button(true)

func _set_position(card: Card, pos: String) -> bool:
	if not is_instance_valid(card):
		return false
	if not card.is_on_field():
		return false

	var cardowner := card_runtime_service._norm_owner(zone_service._owner_of(card))

	if cardowner == "Player":
		if card in bm.player_cards_that_attacked_this_turn:
			return false
	else:
		if card in bm.opponent_cards_that_attacked_this_turn:
			return false

	var want_def := (pos.to_upper() == "DEFENSE")
	if card.has_method("set_defense_position"):
		card.set_defense_position(want_def)
	else:
		card.in_defense = want_def

	event_service._emit_duel_event("ON_CHANGE_POSITION", {
		"battle_manager": bm,
		"source": card,
		"controller": cardowner,
		"to_defense": want_def,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player")
	})
	return true

func _release_player_input_if_needed(attacker: String) -> void:
	if card_runtime_service._norm_owner(attacker) != "Player":
		return
	var im := get_node_or_null("../../InputManager")
	if im != null and bool(im.get("inputs_disabled")):
		im.inputs_disabled = false
	ui_service.enable_end_turn_button(true)

func _emit_after_battle_with_monster(
	atk_card: Node,
	defending: Node,
	attacker_owner: String,
	defender_owner: String,
	result: String,
	battle_position: String,
	battle_damage: int,
	attacker_destroyed_by_battle: bool,
	defender_destroyed_by_battle: bool
) -> Dictionary:
	var ctx := {
		"battle_manager": bm,
		"source": atk_card,
		"attacker": atk_card,
		"defender": defending,
		"attacker_owner": card_runtime_service._norm_owner(attacker_owner),
		"defender_owner": card_runtime_service._norm_owner(defender_owner),
		"controller": card_runtime_service._norm_owner(attacker_owner),
		"source_owner": card_runtime_service._norm_owner(attacker_owner),
		"result": result,
		"battle_position": battle_position,
		"battle_damage": battle_damage,
		"attacker_destroyed_by_battle": attacker_destroyed_by_battle,
		"defender_destroyed_by_battle": defender_destroyed_by_battle,
		"turn_owner": ("Opponent" if bm.is_opponent_turn else "Player"),
		"turn_index": bm.turn_index,
		"battle_pair_banished_after_damage": false,
		"battle_pair_removed_after_damage": false,
		"skip_battle_destruction": false
	}

	event_service._emit_duel_event("AFTER_BATTLE_WITH_MONSTER", ctx)

	return ctx

func _battle_pair_removed_after_damage(ctx: Dictionary) -> bool:
	return bool(ctx.get("battle_pair_removed_after_damage", false)) \
		or bool(ctx.get("battle_pair_banished_after_damage", false))

func _finish_battle_after_pair_removed(atk_card: Node, defending: Node, attacker_owner: String, result: String) -> void:
	stat_service._clear_bonuses([atk_card, defending])

	if is_instance_valid(atk_card):
		atk_state_service._register_attack_spent(atk_card, attacker_owner, defending)

	if attacker_owner == "Player":
		ui_service._enable_player_input()
