extends Node
class_name DuelSpecialEffectService

var bm: Node = null
var card_runtime_service: DuelCardRuntimeService = null
var zone_service: DuelZoneService = null
var event_service: DuelEventService = null
var summon_service: DuelSummonService = null
var graveyard_service: DuelGraveyardService = null
var selection_service: DuelSelectionService = null

func setup(battle_manager: Node) -> void:
	bm = battle_manager
	card_runtime_service = bm.card_runtime_service
	zone_service = bm.zone_service
	event_service = bm.event_service
	summon_service = bm.summon_service
	graveyard_service = bm.graveyard_service
	selection_service = bm.selection_service

func activate_elegant_egotist(source_card: Node, ctx: Dictionary, params: Dictionary) -> bool:
	if summon_service == null:
		push_warning("BattleManager: summon_service no está asignado.")
		return false

	if graveyard_service == null:
		push_warning("BattleManager: graveyard_service no está asignado.")
		return false

	var source_controller := card_runtime_service._norm_owner(ctx.get("controller", ""))

	if source_controller == "" and is_instance_valid(source_card) and ("owner_side" in source_card):
		source_controller = "Player" if str(source_card.owner_side).to_upper() == "PLAYER" else "Opponent"

	source_controller = card_runtime_service._norm_owner(source_controller)

	if source_controller == "":
		return false

	var controller_param := str(params.get("controller", "SELF")).to_upper()
	var effect_controller := source_controller

	if controller_param == "OPPONENT":
		effect_controller = card_runtime_service._opponent_of(source_controller)

	effect_controller = card_runtime_service._norm_owner(effect_controller)

	if effect_controller == "":
		return false

	var harpie_tag := str(params.get("harpie_tag", "harpie-lady")).to_lower()
	var sisters_tag := str(params.get("sisters_tag", "harpie-lady-sisters")).to_lower()
	var sisters_id := str(params.get("sisters_id", "12206212"))
	var max_harpie_level := int(params.get("max_harpie_level", 4))
	var split_max_count := int(params.get("split_max_count", 3))
	var position := str(params.get("position", "FACEUP_ATK")).to_upper()

	# Rama 1:
	# Prioridad: tributar Harpie Lady lvl 4 o menor.
	var low_harpie = selection_service._find_first_controlled_monster(
		effect_controller,
		{
			"tag": harpie_tag,
			"max_level": max_harpie_level
		},
		[sisters_tag]
	)

	if is_instance_valid(low_harpie):
		var tribute_ctx := ctx.duplicate(true)
		tribute_ctx["tribute_for"] = "Elegant Egotist"
		tribute_ctx["tribute_result_id"] = sisters_id

		if not graveyard_service.send_monster_to_graveyard_as_cost(low_harpie, effect_controller, tribute_ctx):
			return false

		var sisters_summoned = summon_service.summon_multiple_monsters_from_db(
			effect_controller,
			{
				"id": sisters_id
			},
			1,
			position,
			source_card,
			"ELEGANT_EGOTIST",
			[],
			[],
			"FIRST",
			false
		)

		return not sisters_summoned.is_empty()

	# Rama 2:
	# Solo si no había Harpie Lady lvl 4 o menor.
	var sisters = selection_service._find_first_controlled_monster(
		effect_controller,
		{
			"tag": sisters_tag
		}
	)

	if not is_instance_valid(sisters):
		return false

	var tribute_ctx_2 := ctx.duplicate(true)
	tribute_ctx_2["tribute_for"] = "Elegant Egotist"
	tribute_ctx_2["split_from_sisters"] = true

	if not graveyard_service.send_monster_to_graveyard_as_cost(sisters, effect_controller, tribute_ctx_2):
		return false

	var split_summoned = summon_service.summon_multiple_monsters_from_db(
		effect_controller,
		{
			"tag": harpie_tag,
			"max_level": max_harpie_level
		},
		split_max_count,
		position,
		source_card,
		"ELEGANT_EGOTIST_SPLIT",
		[],
		[sisters_tag],
		"RANDOM",
		true
	)

	return not split_summoned.is_empty()
