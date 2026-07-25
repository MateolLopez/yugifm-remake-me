extends Node

const BATTLE_POSS_OFFSET = 25
const CARD_MOVE_SPEED = 0.2
const DEFAULT_MAX_HAND_SIZE = 5
const DEFAULT_STARTING_HP = 8000
const DRAW_STEP_DURATION := 0.34

var duel_animation_lock_count: int = 0
#----- DUEL SERVICES ----
@onready var duel_services: Node = get_node_or_null("../DuelServices")

@onready var rule_service: DuelRuleService = _get_duel_service("DuelRuleService") as DuelRuleService
@onready var event_service: DuelEventService = _get_duel_service("DuelEventService") as DuelEventService
@onready var card_db_service: DuelCardDbService = _get_duel_service("DuelCardDbService") as DuelCardDbService
@onready var card_runtime_service: DuelCardRuntimeService = _get_duel_service("DuelCardRuntimeService") as DuelCardRuntimeService
@onready var zone_service: DuelZoneService = _get_duel_service("DuelZoneService") as DuelZoneService
@onready var selection_service: DuelSelectionService = _get_duel_service("DuelSelectionService") as DuelSelectionService
@onready var turn_service: DuelTurnService = _get_duel_service("DuelTurnService") as DuelTurnService
@onready var draw_service: DuelDrawService = _get_duel_service("DuelDrawService") as DuelDrawService
@onready var combat_service: DuelCombatService = _get_duel_service("DuelCombatService") as DuelCombatService
@onready var atk_state_service: DuelAttackStateService = _get_duel_service("DuelAttackStateService") as DuelAttackStateService
@onready var damage_service: DuelDamageService = _get_duel_service("DuelDamageService") as DuelDamageService
@onready var destruction_service: DuelDestructionService = _get_duel_service("DuelDestructionService") as DuelDestructionService
@onready var graveyard_service: DuelGraveyardService = _get_duel_service("DuelGraveyardService") as DuelGraveyardService
@onready var summon_service: DuelSummonService = _get_duel_service("DuelSummonService") as DuelSummonService
@onready var field_spell_service: DuelFieldSpellService = _get_duel_service("DuelFieldSpellService") as DuelFieldSpellService
@onready var card_play_service: DuelCardPlayService = _get_duel_service("DuelCardPlayService") as DuelCardPlayService
@onready var card_activation_service: DuelCardActivationService = _get_duel_service("DuelCardActivationService") as DuelCardActivationService
@onready var equip_service: DuelEquipService = _get_duel_service("DuelEquipService") as DuelEquipService
@onready var kw_service: DuelKeywordService = _get_duel_service("DuelKeywordService") as DuelKeywordService
@onready var stat_service: DuelStatService = _get_duel_service("DuelStatService") as DuelStatService
@onready var reveal_service: DuelRevealService = _get_duel_service("DuelRevealService") as DuelRevealService
@onready var animation_service: DuelAnimationService = _get_duel_service("DuelAnimationService") as DuelAnimationService
@onready var ui_service: DuelUiService = _get_duel_service("DuelUiService") as DuelUiService
@onready var fusion_replacement_service: DuelFusionReplacementService = _get_duel_service("DuelFusionReplacementService") as DuelFusionReplacementService
@onready var special_effect_service: DuelSpecialEffectService = _get_duel_service("DuelSpecialEffectService") as DuelSpecialEffectService
@onready var banish_service: DuelBanishService = _get_duel_service("DuelBanishService") as DuelBanishService

#----- ---------
signal duel_over(result: String)

var active_field_spell: Node = null
var active_field_spell_controller: String = ""
var initial_hands_drawn: bool = false
@onready var _ui_field_spell_name: RichTextLabel = get_node_or_null("../FieldSpellName")
var duel_finished = false
var duel_winner: String = ""
var duel_end_reason: String = ""
var battle_timer
var empty_monster_card_slots = []
var opponent_cards_on_battlefield = []
var player_cards_on_battlefield = []
var opponent_cards_that_attacked_this_turn = []
var player_cards_that_attacked_this_turn = []
var multi_attack_targets_this_turn: Dictionary = {}
var opponent_graveyard = []
var player_graveyard = []
var player_hp
var opponent_hp
var spell_targeting := false
var pending_spell = null
var pending_effects = []
var pending_effect: Array = []
var pending_caster := ""
var pending_required_targets := 0
var pending_targets: Array = []
var suppress_on_attack = false
var multi_mode = {}
var multi_remaining = {}
var multi_already_attacked = {}
var is_opponent_turn = false
var turn_index: int = 0
var equip_targeting: bool = false
var pending_equip_card: Node = null
var pending_equip_controller: String = ""
var reaction_set_order_counter: int = 0
var graveyard_order_counter: int = 0
var attack_count_this_turn: Dictionary = {}

signal fusion_replacement_slot_ready

var fusion_replacement_mode: bool = false
var fusion_replacement_owner: String = ""
var fusion_replacement_card: Node = null
var fusion_replacement_chosen_slot: Node = null

var player_banished: Array = []
var opponent_banished: Array = []

#Card Reveal vars
var reveal_overlay_active := false
var reveal_overlay_cards: Array = []
var reveal_overlay_original_states: Array = []
var reveal_overlay_waiting_ack := false

var pending_end_turn_self_revives: Array = []

signal attack_declared(attacker, defender, attacker_owner)
signal monster_played(monster, cardowner)
signal spell_activated(spell, cardowner)
signal trap_activated(trap, cardowner)
signal turn_started(turn_owner)
signal turn_ended(turn_owner)

func _ready() -> void:
	add_to_group("battle_manager")

	_setup_duel_services()

	battle_timer = $"../BattleTimer"
	battle_timer.one_shot = true
	battle_timer.wait_time = 0.5

	var accept_btn = get_node_or_null("../RevealAckPanel/ButtonAccept")
	if accept_btn != null and reveal_service != null:
		if not accept_btn.pressed.is_connected(reveal_service._on_reveal_ack_accept_pressed):
			accept_btn.pressed.connect(reveal_service._on_reveal_ack_accept_pressed)

	empty_monster_card_slots.append($"../CardSlotsRival/CardSlot")
	empty_monster_card_slots.append($"../CardSlotsRival/CardSlot2")
	empty_monster_card_slots.append($"../CardSlotsRival/CardSlot3")
	empty_monster_card_slots.append($"../CardSlotsRival/CardSlot4")
	empty_monster_card_slots.append($"../CardSlotsRival/CardSlot5")

	player_hp = rule_service._starting_hp()
	$"../PlayerHP".text = str(player_hp)

	opponent_hp = rule_service._starting_hp()
	$"../OpponentHP".text = str(opponent_hp)

	field_spell_service._update_field_spell_name_ui()

	if draw_service != null:
		draw_service.call_deferred("_run_initial_draw_sequence")

func _get_duel_service(service_name: String) -> Node:
	var root := get_node_or_null("../DuelServices")

	if root != null:
		return root.get_node_or_null(service_name)

	# Fallback por si en algún momento los ponés como hijos del BattleManager.
	return get_node_or_null(service_name)

func _setup_duel_services() -> void:
	var services := [
rule_service,
event_service,
card_db_service,
card_runtime_service,
zone_service,
selection_service,
turn_service,
draw_service,
combat_service,
atk_state_service,
damage_service,
destruction_service,
graveyard_service,
summon_service,
field_spell_service,
card_play_service,
card_activation_service,
equip_service,
kw_service,
stat_service,
reveal_service,
animation_service,
ui_service,
fusion_replacement_service,
special_effect_service,
banish_service]

	for service in services:
		if service != null and service.has_method("setup"):
			service.setup(self)

func finish_duel_by_exodia(winner_side: String) -> void:
	if duel_finished:
		return

	winner_side = _normalize_duel_side(winner_side)

	if winner_side == "":
		return

	duel_finished = true
	duel_winner = winner_side
	duel_end_reason = "EXODIA"

	print("DUEL FINISHED BY EXODIA | winner=", winner_side)

	if animation_service != null and animation_service.has_method("play_exodia_win_fx"):
		await animation_service.play_exodia_win_fx(winner_side)

	var result := "player_victory" if winner_side == "Player" else "player_defeat"
	emit_signal("duel_over", result)

func _normalize_duel_side(side: String) -> String:
	var s := str(side).strip_edges().to_upper()

	if s == "PLAYER":
		return "Player"

	if s == "OPPONENT" or s == "RIVAL":
		return "Opponent"

	return ""
