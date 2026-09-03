extends RefCounted
class_name BattleController

const BattleHexGrid = preload("res://scripts/battle/battle_hex_grid.gd")
const BattleSurfaceState = preload("res://scripts/battle/battle_surface_state.gd")
const BattlePathfinder = preload("res://scripts/battle/battle_pathfinder.gd")
const BattlefieldFeatureGenerator = preload("res://scripts/battle/battlefield_feature_generator.gd")
const RangerTurnDamageBonusStatus = preload("res://scripts/status/ranger_turn_damage_bonus_status.gd")
const RangerGainMultiplierStatus = preload("res://scripts/status/ranger_gain_multiplier_status.gd")
const RangerMoveSurchargeStatus = preload("res://scripts/status/ranger_move_surcharge_status.gd")
const RangerBurnStatus = preload("res://scripts/status/ranger_burn_status.gd")
const RangerBlindStatus = preload("res://scripts/status/ranger_blind_status.gd")
const RangerCombatState = preload("res://scripts/ranger/ranger_combat_state.gd")
const MageInfusionState = preload("res://scripts/mage/mage_infusion_state.gd")
const CurseCatalog = preload("res://scripts/curses/curse_catalog.gd")

signal log_message(message: String)
signal state_changed
signal basic_attack_triggered(context: Dictionary)
signal equipment_switch_started(context: Dictionary)
signal equipment_switched_out(context: Dictionary)
signal equipment_switched_in(context: Dictionary)
signal battle_finished(result: BattleResult)

const DRUID_PREPARE_TRANSFORM_ACTION := "druid_prepare_transform"
const DRUID_PREPARE_UNTRANSFORM_ACTION := "druid_prepare_untransform"
const WARRIOR_MOMENTUM_RESOURCE := "势"
const MAX_ENEMY_DECISIONS_PER_TURN := 64
const CARD_EFFECT_CONTINUATION_PRIORITY := -100000

enum Phase {
	DEPLOYMENT,
	BATTLE,
	ENDED,
}

enum UnitFilter {
	OPPONENTS,
	ALLIES,
	ALL,
}

enum TurnFlowState {
	IDLE,
	START_PENDING,
	WARLOCK_PREP_PENDING,
	MANIFEST_PENDING,
	ACTIVE,
	END_PENDING,
}

var scenario: BattleScenario
var config: BattleConfig
var map_data: BattleMapData
var scene_prototype
var rng := RandomNumberGenerator.new()
var phase: int = Phase.DEPLOYMENT
var units: Array[BattleUnitState] = []
var player_units: Array[BattleUnitState] = []
var enemy_units: Array[BattleUnitState] = []
var battle_objects: Array[BattleObjectState] = []
var turn_order: Array[BattleUnitState] = []
var current_turn_index: int = -1
var current_unit: BattleUnitState
var turn_flow_state: int = TurnFlowState.IDLE
var enemy_decision_count: int = 0
var cards_in_flight := {}
var action_resolution_active: bool = false
var internal_action_submission_depth: int = 0
var resolution_state_notification_active: bool = false
var resolution_runner := BattleResolutionRunner.new()
var targeting := BattleTargeting.new()
var strike_resolver := BattleStrikeResolver.new()
var surface_state := BattleSurfaceState.new()
var mage_infusion_state := MageInfusionState.new()
var battle_round: int = 0
var action_phase_serial: int = 0
var active_turn_serial: int = 0
var stealth_cancelled_actions: Dictionary = {}
var runtime_character_sources: Dictionary = {}
var battle_result_committed: bool = false
var unbound_skip_enemy_pending: bool = false
var unbound_extra_unit: BattleUnitState
var unbound_extra_ap: int = 0
var unbound_extra_active: bool = false
var unbound_force_end_after_action: bool = false

func setup(new_scenario: BattleScenario) -> void:
	scenario = new_scenario
	if scenario == null:
		config = BattleConfig.new()
		scene_prototype = null
		map_data = BattleMapData.new()
		_reset_runtime_state()
		surface_state.setup(map_data)
		resolution_runner.setup(self)
		targeting.setup(self)
		strike_resolver.setup(self)
		_emit_log("战斗场景缺少 BattleScenario，已使用空白配置。")
		state_changed.emit()
		return

	config = scenario.battle_config if scenario.battle_config != null else BattleConfig.new()
	scene_prototype = scenario.scene_prototype
	var source_map_data := scenario.get_map_data()
	map_data = source_map_data.duplicate(true) if source_map_data != null else BattleMapData.new()
	if scene_prototype != null and scene_prototype.scene_texture != null:
		map_data.background_texture = scene_prototype.scene_texture
	rng.seed = scenario.seed
	_reset_runtime_state()
	surface_state.setup(map_data)
	_load_authored_battle_objects()
	if scenario.generate_battlefield_features:
		var battlefield_seed := scenario.feature_seed if scenario.feature_seed != 0 else scenario.seed
		var generated_objects: Array[BattleObjectState] = BattlefieldFeatureGenerator.generate(
			map_data,
			surface_state,
			scenario.feature_chapter,
			scenario.feature_encounter_tier,
			battlefield_seed,
			scenario.force_abyss_features,
			battle_objects.size(),
			battle_objects
		)
		battle_objects.append_array(generated_objects)
	resolution_runner.setup(self)
	targeting.setup(self)
	strike_resolver.setup(self)

	var id := 0
	for character_template in scenario.get_player_states():
		if character_template == null:
			continue
		character_template.ensure_initialized()
		if character_template.is_curse_overloaded():
			_emit_log("%s 的诅咒负荷超出上限，无法参加战斗。" % character_template.get_character_name())
			continue
		var character_state := _create_runtime_character_state(character_template)
		if character_state == null:
			continue
		var unit := BattleUnitState.new()
		unit.setup_player(id, character_state, config.default_token_radius)
		unit.battle_controller = self
		runtime_character_sources[character_state] = character_template
		id += 1
		units.append(unit)
		player_units.append(unit)

	for enemy_template in scenario.get_enemy_states():
		if enemy_template == null:
			continue
		var enemy_state := _create_runtime_enemy_state(enemy_template)
		if enemy_state == null:
			continue
		enemy_state.ensure_initialized(rng.randi())
		enemy_state.current_health = enemy_state.get_max_health()
		enemy_state.generate_deck(rng.randi())
		var spawn_cell_value: Variant = _find_enemy_spawn_cell_for_enemy(enemy_state)
		if not (spawn_cell_value is Vector2i):
			_emit_log("敌方出生区已满，跳过 %s。" % enemy_state.get_enemy_name())
			continue
		var spawn_cell: Vector2i = spawn_cell_value
		var unit := BattleUnitState.new()
		unit.setup_enemy(id, enemy_state, config.default_token_radius)
		unit.battle_controller = self
		unit.set_hex_cell(spawn_cell, map_data)
		id += 1
		units.append(unit)
		enemy_units.append(unit)

	_queue_global_effects("on_battle_setup")
	resolve_effect_queue()
	if scene_prototype != null:
		_emit_log("载入场景原型：%s。" % scene_prototype.get_display_title())
	_emit_log("进入部署阶段。请选择玩家单位并点击部署区。")
	state_changed.emit()


func _load_authored_battle_objects() -> void:
	if map_data == null:
		return
	for placement in map_data.object_placements:
		if placement == null or not map_data.is_valid_cell(placement.cell):
			continue
		spawn_battle_object(
			placement.object_kind,
			placement.cell,
			placement.fall_direction
		)


func _reset_runtime_state() -> void:
	phase = Phase.DEPLOYMENT
	units.clear()
	player_units.clear()
	enemy_units.clear()
	battle_objects.clear()
	turn_order.clear()
	current_turn_index = -1
	current_unit = null
	turn_flow_state = TurnFlowState.IDLE
	enemy_decision_count = 0
	cards_in_flight.clear()
	action_resolution_active = false
	internal_action_submission_depth = 0
	resolution_state_notification_active = false
	battle_round = 0
	action_phase_serial = 0
	active_turn_serial = 0
	mage_infusion_state.reset()
	stealth_cancelled_actions.clear()
	runtime_character_sources.clear()
	battle_result_committed = false
	unbound_skip_enemy_pending = false
	unbound_extra_unit = null
	unbound_extra_ap = 0
	unbound_extra_active = false
	unbound_force_end_after_action = false


func _create_runtime_character_state(template: CharacterState) -> CharacterState:
	if template == null:
		return null

	var state := template.duplicate(true) as CharacterState
	if state == null:
		return null

	state.ensure_initialized()
	state.reset_class_resources()
	state.current_health = clampi(template.current_health, 0, state.get_max_health())
	return state


func _create_runtime_enemy_state(template: EnemyState) -> EnemyState:
	if template == null:
		return null

	var state := template.duplicate(true) as EnemyState
	if state == null:
		return null

	if state.enemy_data != null:
		var runtime_enemy_data := state.enemy_data.duplicate(true) as EnemyData
		if runtime_enemy_data != null:
			if runtime_enemy_data.behavior != null:
				runtime_enemy_data.behavior = runtime_enemy_data.behavior.duplicate(true) as EnemyBehavior
			state.enemy_data = runtime_enemy_data
	return state


func deploy_player_unit_at_cell(unit: BattleUnitState, cell: Vector2i) -> bool:
	if is_resolving_actions():
		return false
	if phase != Phase.DEPLOYMENT:
		_emit_log("当前不是部署阶段。")
		return false

	if unit == null or unit.faction != BattleUnitState.Faction.PLAYER:
		_emit_log("只能部署玩家单位。")
		return false

	if not _is_cell_valid_for_unit(unit, cell, true):
		return false

	unit.set_hex_cell(cell, map_data)
	unit.is_deployed = true
	_emit_log("%s 部署到格 (%d, %d)。" % [unit.get_display_name(), unit.cell.x, unit.cell.y])
	state_changed.emit()
	return true


func can_start_battle() -> bool:
	if is_resolving_actions():
		return false

	for unit in player_units:
		if not unit.is_deployed:
			return false
		if not unit.is_equipment_setup_ready({"controller": self, "phase": "deployment"}):
			return false

	return not player_units.is_empty() and not enemy_units.is_empty()


func start_battle() -> bool:
	if is_resolving_actions():
		return false
	if phase != Phase.DEPLOYMENT:
		return false

	if not can_start_battle():
		_emit_log("仍有玩家单位未部署，或缺少参战单位。")
		return false

	for unit in units:
		unit.ensure_initialized(config, rng)
		var mage_opening_gains := unit.initialize_mage_opening_hand()
		if not mage_opening_gains.is_empty():
			_emit_log("%s 根据起手牌获得了四系法术力。" % unit.get_display_name())

	phase = Phase.BATTLE
	turn_flow_state = TurnFlowState.IDLE
	for unit in units:
		unit.notify_equipment_battle_started({"controller": self, "phase": "battle_start"})
		unit.notify_curse_battle_started({"controller": self, "phase": "battle_start"})
	EnemyRuleDispatcher.on_battle_started(self)
	_rebuild_turn_order()
	_lock_all_enemy_intents()
	_emit_log("战斗开始。")
	current_turn_index = -1
	advance_turn()
	return true


func advance_turn() -> void:
	if phase != Phase.BATTLE or turn_flow_state != TurnFlowState.IDLE:
		return

	if _check_battle_end():
		return

	if turn_order.is_empty() or current_turn_index < 0 or current_turn_index >= turn_order.size() - 1:
		battle_round += 1
		if battle_round > 1:
			surface_state.advance_round(battle_round)
		_rebuild_turn_order()
		current_turn_index = 0
	else:
		current_turn_index += 1

	for _i in range(turn_order.size()):
		current_unit = turn_order[current_turn_index]
		if current_unit.is_alive():
			turn_flow_state = TurnFlowState.START_PENDING
			if not push_action_frame(BattleActionFrame.create(
				Callable(self, "_resolve_turn_start_action"),
				[current_unit],
				0,
				"%s 回合开始" % current_unit.get_display_name(),
				{"unit": current_unit, "phase": "turn_start"},
				Callable(self, "_finish_turn_start_action"),
				[current_unit]
			)):
				turn_flow_state = TurnFlowState.IDLE
			return
		current_turn_index = (current_turn_index + 1) % turn_order.size()

	_check_battle_end()


func end_current_turn() -> void:
	if is_resolving_actions() or resolution_state_notification_active:
		return
	_request_turn_end(current_unit)


func _request_turn_end(unit: BattleUnitState) -> void:
	if phase != Phase.BATTLE or unit == null or current_unit != unit or turn_flow_state != TurnFlowState.ACTIVE:
		return
	if unit.has_pending_curse_choice({"controller": self, "phase": "turn_end_request"}):
		_emit_log("%s 必须先在诅咒区处理超出贪欲手牌上限的牌。" % unit.get_display_name())
		state_changed.emit()
		return
	if unbound_extra_active:
		unit.current_ap = 0
		unbound_extra_active = false
		turn_flow_state = TurnFlowState.IDLE
		_emit_log("%s 的无羁额外行动阶段结束。" % unit.get_display_name())
		advance_turn()
		return

	turn_flow_state = TurnFlowState.END_PENDING
	if not push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_turn_end_action"),
		[unit],
		0,
		"%s 回合结束" % unit.get_display_name(),
		{"unit": unit, "phase": "turn_end"},
		Callable(self, "_finish_turn_end_action"),
		[unit]
	)):
		turn_flow_state = TurnFlowState.ACTIVE


func _resolve_turn_start_action(unit: BattleUnitState) -> void:
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return

	active_turn_serial += 1
	unit.start_turn(config)
	EnemyRuleDispatcher.on_turn_started(self, unit)
	for battle_unit in units:
		if battle_unit != null:
			battle_unit.remove_expired_statuses()
			battle_unit.notify_observed_unit_turn_start(unit, {"controller": self, "phase": "turn_start"})
	_queue_unit_status_effects("on_turn_start", unit)
	_queue_global_effects("on_turn_start", unit)
	unit.notify_equipment_turn_start({"controller": self, "phase": "turn_start"})
	_apply_surface_turn_start(unit)
	enqueue_effect(
		Callable(unit, "resolve_distortion_turn_start"),
		[],
		-70,
		"%s 畸变回合开始" % unit.get_display_name(),
		{"unit": unit, "phase": "distortion_turn_start"}
	)
	if not (unbound_skip_enemy_pending and unit.faction == BattleUnitState.Faction.ENEMY):
		enqueue_effect(
			Callable(unit, "notify_draw_phase_before"),
			[{"controller": self, "phase": "draw_phase_before", "draw_source": "draw_phase"}],
			-80,
			"%s 抽牌阶段前" % unit.get_display_name()
		)
		enqueue_effect(
			Callable(self, "_resolve_draw_phase"),
			[unit],
			-90,
			"%s 抽牌阶段" % unit.get_display_name()
		)
		enqueue_effect(
			Callable(self, "_resolve_warlock_corruption"),
			[unit],
			-95,
			"%s 腐化" % unit.get_display_name()
		)
		enqueue_effect(
			Callable(self, "_resolve_distortion_post_draw"),
			[unit],
			-100,
			"%s 畸变衰退" % unit.get_display_name()
		)


func _resolve_draw_phase(unit: BattleUnitState) -> void:
	if phase != Phase.BATTLE or unit == null or current_unit != unit or not unit.is_alive():
		return
	var draw_count := unit.get_distortion_draw_count()
	var drawn := unit.draw_cards(draw_count, rng, {
		"controller": self,
		"reason": "draw_phase",
		"draw_source": "draw_phase",
		"phase": "draw_phase",
	})
	_emit_log("%s 在抽牌阶段抽取 %d 张牌。" % [unit.get_display_name(), drawn])


func _resolve_distortion_post_draw(unit: BattleUnitState) -> void:
	if phase != Phase.BATTLE or unit == null or current_unit != unit or not unit.is_alive():
		return
	var decayed := unit.decay_turn_start_manifestations({
		"controller": self,
		"phase": "mutation_decay",
	})
	if decayed > 0:
		var decay_life_loss := decayed * (2 if unit.is_warlock_adventurer() else 1)
		lose_life(unit, unit, decay_life_loss, "畸变衰退", {
			"distortion_decay": true,
		})
		_emit_log("%s 的 %d 张显化牌衰退。" % [unit.get_display_name(), decayed])
	if unit.is_alive() and not unit.get_manifestable_hand_cards().is_empty():
		unit.distortion_state.pending_manual_manifest = true


func _finish_turn_start_action(unit: BattleUnitState) -> void:
	if phase != Phase.BATTLE:
		turn_flow_state = TurnFlowState.IDLE
		return
	if unit == null or current_unit != unit or not unit.is_alive():
		turn_flow_state = TurnFlowState.IDLE
		advance_turn()
		return

	unit.remove_expired_statuses()
	if unbound_skip_enemy_pending and unit.faction == BattleUnitState.Faction.ENEMY:
		unbound_skip_enemy_pending = false
		_emit_log("%s 的抽牌与行动阶段被无羁跳过。" % unit.get_display_name())
		_begin_unbound_extra_phase()
		return
	_continue_turn_start_interactions(unit)


func _resolve_warlock_corruption(unit: BattleUnitState) -> void:
	if phase != Phase.BATTLE or unit == null or current_unit != unit or not unit.is_alive() \
			or not unit.is_warlock_adventurer():
		return
	var changed_types := unit.corrupt_existing_indicators(1)
	if changed_types > 0:
		_emit_log("%s 腐化了 %d 种已有指示物。" % [unit.get_display_name(), changed_types])


func _continue_turn_start_interactions(unit: BattleUnitState) -> void:
	if unit == null or current_unit != unit or not unit.is_alive():
		turn_flow_state = TurnFlowState.IDLE
		advance_turn()
		return
	if unit.is_warlock_adventurer() and not unit.warlock_state.preparation_resolved:
		if unit.curse_zone.is_empty() or unit.faction == BattleUnitState.Faction.ENEMY:
			unit.warlock_state.preparation_resolved = true
		else:
			turn_flow_state = TurnFlowState.WARLOCK_PREP_PENDING
			_emit_log("%s 可以批量翻转诅咒；翻至背面时获得 1 点术士法力。" % unit.get_display_name())
			state_changed.emit()
			return
	if unit.distortion_state.pending_manual_manifest:
		if unit.faction == BattleUnitState.Faction.ENEMY:
			_manifest_enemy_planned_cards(unit)
		else:
			turn_flow_state = TurnFlowState.MANIFEST_PENDING
			_emit_log("%s 可以从手牌显化至多 2 张畸变牌。" % unit.get_display_name())
			state_changed.emit()
			return
	_activate_action_phase(unit)


func submit_warlock_curse_faces(unit: BattleUnitState, curses_to_flip: Array[CurseInstance]) -> bool:
	if phase != Phase.BATTLE or turn_flow_state != TurnFlowState.WARLOCK_PREP_PENDING \
			or unit == null or current_unit != unit or unit.faction != BattleUnitState.Faction.PLAYER \
			or not unit.is_warlock_adventurer() or unit.warlock_state.preparation_resolved:
		return false
	var unique_curses: Array[CurseInstance] = []
	for curse in curses_to_flip:
		if curse == null or unique_curses.has(curse) or not unit.curse_zone.has(curse):
			return false
		unique_curses.append(curse)
	for curse in unique_curses:
		unit.set_warlock_curse_face_down(
			curse,
			not unit.warlock_state.is_face_down(curse),
			{"controller": self, "reason": "warlock_prepare"}
		)
	unit.warlock_state.preparation_resolved = true
	if not unique_curses.is_empty():
		_emit_log("%s 翻转了 %d 张诅咒。" % [unit.get_display_name(), unique_curses.size()])
	_continue_turn_start_interactions(unit)
	state_changed.emit()
	return true


func submit_manifestation_selection(unit: BattleUnitState, cards: Array[CardData]) -> bool:
	if phase != Phase.BATTLE or turn_flow_state != TurnFlowState.MANIFEST_PENDING \
			or unit == null or current_unit != unit or unit.faction != BattleUnitState.Faction.PLAYER:
		return false
	if cards.size() > 2:
		return false
	var manifested := unit.manifest_cards_from_hand(cards, {
		"controller": self,
		"phase": "manual_manifest",
	})
	if manifested != cards.size():
		return false
	if manifested > 0:
		_emit_log("%s 显化了 %d 张畸变牌。" % [unit.get_display_name(), manifested])
	_continue_turn_start_interactions(unit)
	return true


func _manifest_enemy_planned_cards(unit: BattleUnitState) -> void:
	if unit == null:
		return
	var selected: Array[CardData] = []
	var planned_ids := PackedInt64Array()
	if unit.enemy_state != null and unit.enemy_state.intent_plan != null:
		planned_ids = unit.enemy_state.intent_plan.planned_manifest_card_ids
	for card_id in planned_ids:
		for card in unit.hand:
			if card != null and card.get_instance_id() == card_id and unit.distortion_state.card_adds_new_field(card):
				selected.append(card)
				break
		if selected.size() >= 2:
			break
	unit.manifest_cards_from_hand(selected, {
		"controller": self,
		"phase": "enemy_manifest",
	})
	unit.distortion_state.pending_manual_manifest = false


func _activate_action_phase(unit: BattleUnitState) -> void:
	if unit == null or current_unit != unit or not unit.is_alive():
		turn_flow_state = TurnFlowState.IDLE
		advance_turn()
		return
	turn_flow_state = TurnFlowState.ACTIVE
	action_phase_serial += 1
	if unit.is_mage_adventurer():
		unit.mage_state.start_action_phase()
	unit.notify_action_phase_started({"controller": self, "phase": "action_phase_start"})
	_emit_log("轮到 %s，AP：%d。" % [unit.get_display_name(), unit.current_ap])
	state_changed.emit()
	if current_unit == unit and unit.faction == BattleUnitState.Faction.ENEMY:
		_begin_enemy_turn(unit)


func _resolve_turn_end_action(unit: BattleUnitState) -> void:
	if phase != Phase.BATTLE or unit == null or current_unit != unit:
		return

	var draw_count := 0
	if config.ap_per_end_turn_draw > 0:
		draw_count = floori(float(unit.current_ap) / float(config.ap_per_end_turn_draw))

	if draw_count > 0:
		var drawn := unit.draw_cards(draw_count, rng, {
			"controller": self,
			"reason": "end_turn_ap",
		})
		_emit_log("%s 保留 %d AP，抽取 %d 张牌。" % [unit.get_display_name(), unit.current_ap, drawn])

	unit.current_ap = 0
	_queue_unit_status_effects("on_turn_end", unit)
	_queue_global_effects("on_turn_end", unit)
	enqueue_effect(
		Callable(unit, "notify_zone_turn_end"),
		[{"controller": self, "unit": unit, "phase": "turn_end"}],
		-90,
		"回合结束附魔区触发"
	)
	unit.notify_equipment_turn_end({"controller": self, "phase": "turn_end"})
	_resolve_ranger_turn_end(unit)
	enqueue_effect(
		Callable(unit, "exile_expiring_temporary_cards"),
		[self],
		-100,
		"回合结束临时牌放逐",
		{"controller": self, "unit": unit, "phase": "turn_end"}
	)


func _finish_turn_end_action(unit: BattleUnitState) -> void:
	EnemyRuleDispatcher.on_turn_ended(self, unit)
	if unit != null and unit.faction == BattleUnitState.Faction.ENEMY:
		_lock_enemy_intent(unit)
	if current_unit == unit:
		turn_flow_state = TurnFlowState.IDLE
	if phase == Phase.BATTLE and current_unit == unit:
		advance_turn()


func move_current_unit_to_cell(cell: Vector2i) -> bool:
	return move_unit_to_cell(current_unit, cell)


func move_unit_to_cell(unit: BattleUnitState, cell: Vector2i) -> bool:
	if not _can_submit_turn_action(unit, "移动"):
		return false
	if not unit.can_use_action_category(CardEnums.ActionCategory.MOVE, {"controller": self, "phase": "action"}):
		_emit_log("%s 本行动阶段不能移动。" % unit.get_display_name())
		return false
	if not unit.can_start_voluntary_movement():
		_emit_log("%s 当前无法主动移动。" % unit.get_display_name())
		return false

	if not _is_cell_valid_for_unit(unit, cell, false):
		return false

	var path := get_movement_path(unit, cell)
	if path.is_empty():
		_emit_log("没有通往目标格的合法路径。")
		return false
	var movement_cost: int = _get_path_movement_cost(unit, path)
	var ap_cost := unit.get_move_ap_cost(movement_cost, config)
	if movement_cost <= 0:
		return true

	if unit.current_ap < ap_cost:
		_emit_log("%s AP不足，移动需要 %d AP。" % [unit.get_display_name(), ap_cost])
		return false

	return push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_direct_move_action"),
		[unit, cell],
		0,
		"%s 直接移动" % unit.get_display_name(),
		{"unit": unit, "cell": cell, "ap_cost": ap_cost}
	))


func _resolve_direct_move_action(unit: BattleUnitState, cell: Vector2i) -> void:
	if not _is_turn_action_execution_valid(unit):
		return
	if not unit.can_start_voluntary_movement():
		return
	if not _is_cell_valid_for_unit(unit, cell, false):
		return

	var path := get_movement_path(unit, cell)
	if path.is_empty():
		return
	var movement_cost: int = _get_path_movement_cost(unit, path)
	if movement_cost <= 0:
		return

	var ap_cost := unit.get_move_ap_cost(movement_cost, config)
	if unit.current_ap < ap_cost:
		_emit_log("%s AP不足，移动需要 %d AP。" % [unit.get_display_name(), ap_cost])
		return

	_close_ranger_combo_window(unit)
	unit.current_ap -= ap_cost
	unit.notify_move_ap_cost_paid({
		"controller": self,
		"cell": cell,
		"distance": movement_cost,
		"path": path,
		"ap_cost": ap_cost,
	})
	var start_cell := unit.cell
	for index in range(1, path.size()):
		unit.set_hex_cell(path[index], map_data)
		if process_surface_entry(unit, path[index]):
			break
	_notify_opponents_movement_completed(unit)
	unit.notify_movement_completed({
		"controller": self,
		"start_cell": start_cell,
		"end_cell": unit.cell,
		"distance": BattleHexGrid.distance(start_cell, unit.cell),
		"forced": false,
		"card_movement": false,
	})
	_emit_log("%s 移动到格 (%d, %d)，消耗 %d AP。" % [unit.get_display_name(), unit.cell.x, unit.cell.y, ap_cost])
	state_changed.emit()


func get_movement_path(unit: BattleUnitState, cell: Vector2i) -> Array[Vector2i]:
	if unit == null or map_data == null:
		return []
	if unit.is_flying():
		if not map_data.is_valid_cell(cell) or not targeting.is_unit_cell_clear(unit, cell, false):
			return []
		return map_data.get_line(unit.cell, cell)
	return BattlePathfinder.find_path(
		map_data,
		surface_state,
		unit.cell,
		cell,
		func(candidate: Vector2i) -> bool: return candidate == unit.cell or targeting.is_unit_cell_clear(unit, candidate, false)
	)


func _get_path_movement_cost(unit: BattleUnitState, path: Array[Vector2i]) -> int:
	if unit != null and unit.is_flying():
		return maxi(0, path.size() - 1)
	return BattlePathfinder.get_path_cost(path, surface_state)


func play_card(user: BattleUnitState, card: CardData, targets: Array, strike_context: Dictionary = {}, play_mode: int = CardEnums.CardPlayMode.NORMAL) -> bool:
	var context := _build_card_play_context(user, card, targets, strike_context, play_mode, true)
	if context == null:
		return false

	var frame := BattleCardFrame.create(user, card, targets, context)
	var priority := card.effect.effect_priority if card.effect != null else 0
	var card_instance_id := card.get_instance_id()
	var was_resolving := is_resolving_actions()
	cards_in_flight[card_instance_id] = true
	var accepted := push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_card_play_frame"),
		[frame],
		priority,
		"%s 卡牌行动" % card.card_name,
		context,
		Callable(self, "_finish_card_play_frame"),
		[frame]
	))
	if not accepted:
		cards_in_flight.erase(card_instance_id)
	if not accepted or was_resolving:
		return accepted
	return frame.resolved_successfully


func play_mage_primordial_card(user: BattleUnitState, card: CardData, targets: Array, strike_context: Dictionary = {}, play_mode: int = CardEnums.CardPlayMode.NORMAL) -> bool:
	if not can_use_mage_primordial(user) or card == null or not user.draw_pile.has(card) \
			or play_mode == CardEnums.CardPlayMode.MOMENTUM:
		return false
	var primordial_context := strike_context.duplicate()
	primordial_context["mage_primordial"] = true
	primordial_context["source_zone"] = CardEnums.CardZone.DRAW
	primordial_context["ap_cost_override"] = 0
	var context := _build_card_play_context(user, card, targets, primordial_context, play_mode, true)
	if context == null:
		return false
	var frame := BattleCardFrame.create(user, card, targets, context)
	var priority := card.effect.effect_priority if card.effect != null else 0
	var card_instance_id := card.get_instance_id()
	var was_resolving := is_resolving_actions()
	cards_in_flight[card_instance_id] = true
	var accepted := push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_card_play_frame"),
		[frame],
		priority,
		"%s 初态元素卡牌行动" % card.card_name,
		context,
		Callable(self, "_finish_card_play_frame"),
		[frame]
	))
	if not accepted:
		cards_in_flight.erase(card_instance_id)
	if not accepted or was_resolving:
		return accepted
	return frame.resolved_successfully


func _build_card_play_context(user: BattleUnitState, card: CardData, targets: Array, strike_context: Dictionary, play_mode: int, write_log: bool, allow_during_resolution: bool = false) -> CardPlayContext:
	if card == null or not _can_submit_turn_action(user, "出牌", write_log, allow_during_resolution):
		if write_log:
			if card == null:
				_emit_log("没有可打出的卡牌。")
		return null
	var action_category := CardEnums.action_category_for_card(card.card_type)
	if not user.can_use_action_category(action_category, {"controller": self, "card": card, "phase": "action"}):
		if write_log:
			_emit_log("%s 本行动阶段不能使用%s。" % [user.get_display_name(), CardEnums.action_category_label(action_category)])
		return null
	if not allow_during_resolution and cards_in_flight.has(card.get_instance_id()):
		if write_log:
			_emit_log("%s 已在结算队列中。" % card.card_name)
		return null

	if not _card_source_is_valid(user, card, play_mode, write_log, strike_context):
		return null
	var ranger_universal_combo := _is_ranger_universal_combo(user, play_mode)
	if not _card_supports_play_mode_for_user(user, card, play_mode):
		if write_log:
			_emit_log("%s 不能以%s方式打出。" % [card.card_name, CardEnums.play_mode_label(play_mode)])
		return null
	if not _is_druid_card_play_state_valid(user, card, write_log):
		return null

	var druid_orientation := _get_druid_orientation_for_card(user, card)
	var card_context_seed := {
		"controller": self,
		"user": user,
		"card": card,
		"play_mode": play_mode,
		"druid_orientation": druid_orientation,
		"ranger_universal_combo": ranger_universal_combo,
	}

	var condition_context := _build_special_play_condition_context(user, card, play_mode)
	condition_context.merge(strike_context, true)
	condition_context["druid_orientation"] = druid_orientation
	condition_context["ranger_universal_combo"] = ranger_universal_combo
	if not ranger_universal_combo and not card.can_pay_special_conditions(condition_context, play_mode):
		if write_log:
			_emit_log("%s 的%s条件不足：%s。" % [card.card_name, CardEnums.play_mode_label(play_mode), card.get_special_condition_text(play_mode)])
		return null
	if not card.can_pay_play_cost(condition_context):
		if write_log:
			_emit_log("%s 的额外费用无法支付。" % card.card_name)
		return null

	var effective_ap_cost := get_card_ap_cost_for_mode(user, card, play_mode, card_context_seed)
	if strike_context.has("ap_cost_override"):
		effective_ap_cost = maxi(0, int(strike_context["ap_cost_override"]))
	if user.current_ap < effective_ap_cost:
		if write_log:
			_emit_log("%s AP不足，%s 需要 %d AP。" % [user.get_display_name(), card.card_name, effective_ap_cost])
		return null

	var equipment_slot := str(strike_context.get("equipment_slot", ""))
	var target_context := strike_context.duplicate()
	target_context["druid_orientation"] = druid_orientation
	if not _targets_are_valid(user, card, targets, write_log, equipment_slot, play_mode, target_context):
		return null

	var extra_context := strike_context.duplicate()
	extra_context.erase("equipment_slot")
	extra_context["actual_ap_cost"] = effective_ap_cost
	extra_context["play_mode"] = play_mode
	extra_context["druid_orientation"] = druid_orientation
	extra_context["ranger_universal_combo"] = ranger_universal_combo
	if not extra_context.has("adventure_infusion_cell"):
		extra_context["adventure_infusion_cell"] = _resolve_card_primary_cell(user, targets)
	var context := CardPlayContext.create(self, user, card, equipment_slot, extra_context, play_mode)
	var context_dict := context.to_dict()
	if not card.can_play(context_dict):
		if write_log:
			_emit_log("%s 当前不能打出。" % card.card_name)
		return null
	return context


func _resolve_card_play_frame(frame: BattleCardFrame) -> void:
	if frame == null or frame.user == null or frame.card == null or frame.context == null:
		return

	var strike_context := frame.context.extra.duplicate()
	strike_context["equipment_slot"] = frame.context.equipment_slot
	var refreshed_context := _build_card_play_context(
		frame.user,
		frame.card,
		frame.targets,
		strike_context,
		frame.context.play_mode,
		true,
		true
	)
	if refreshed_context == null:
		return
	frame.context = refreshed_context
	var context_dict := refreshed_context.to_dict()
	var effective_ap_cost := int(refreshed_context.extra.get("actual_ap_cost", frame.card.ap_cost))
	var play_mode := refreshed_context.play_mode
	var druid_orientation := int(refreshed_context.extra.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT))
	var condition_context := _build_special_play_condition_context(frame.user, frame.card, play_mode)
	condition_context.merge(refreshed_context.extra, true)
	condition_context["druid_orientation"] = druid_orientation
	var ranger_universal_combo := bool(refreshed_context.extra.get("ranger_universal_combo", false))
	condition_context["ranger_universal_combo"] = ranger_universal_combo

	var payment_snapshot := _snapshot_card_payment_state(frame.user)
	var payment_queue_size := resolution_runner.get_current_effect_queue_size()
	frame.user.current_ap -= effective_ap_cost
	if not frame.card.pay_play_cost(condition_context):
		_rollback_card_payment(frame.user, payment_snapshot, payment_queue_size)
		_emit_log("%s 的额外费用支付失败。" % frame.card.card_name)
		return
	if not _try_pay_druid_resonance(frame.user, frame.card, refreshed_context):
		_rollback_card_payment(frame.user, payment_snapshot, payment_queue_size)
		return
	if not ranger_universal_combo and not frame.card.pay_special_conditions(condition_context, play_mode):
		_rollback_card_payment(frame.user, payment_snapshot, payment_queue_size)
		_emit_log("%s 的%s条件支付失败。" % [frame.card.card_name, CardEnums.play_mode_label(play_mode)])
		return
	if play_mode == CardEnums.CardPlayMode.COMBO and frame.user.is_ranger():
		frame.user.ranger_state.combo_window_open = false
		if ranger_universal_combo:
			frame.user.ranger_state.universal_combo_ready = false
			frame.user.ranger_state.universal_combo_expires_turn_serial = -1

	if play_mode == CardEnums.CardPlayMode.MOMENTUM:
		if not frame.user.banish_discard_card(frame.card):
			_rollback_card_payment(frame.user, payment_snapshot, payment_queue_size)
			_emit_log("%s 不在弃牌堆，无法余势打出。" % frame.card.card_name)
			return
		frame.discard_after_play = false
		_emit_log("%s 放逐弃牌堆中的 %s。" % [frame.user.get_display_name(), frame.card.card_name])
	if bool(refreshed_context.extra.get("mage_primordial", false)):
		var draw_index := frame.user.draw_pile.find(frame.card)
		if draw_index < 0:
			_rollback_card_payment(frame.user, payment_snapshot, payment_queue_size)
			_emit_log("%s 的初态元素调用失效。" % frame.card.card_name)
			return
		frame.user.draw_pile.remove_at(draw_index)
		frame.user.shuffle_draw_pile(rng)
		if not mage_infusion_state.consume_primordial(frame.user.faction, frame.user.cell):
			_rollback_card_payment(frame.user, payment_snapshot, payment_queue_size)
			_emit_log("%s 的初态元素调用失效。" % frame.card.card_name)
			return
		frame.user.hand.append(frame.card)

	frame.user.notify_card_ap_cost_paid(frame.card, {
		"controller": self,
		"card": frame.card,
		"ap_cost": effective_ap_cost,
		"play_mode": play_mode,
		"druid_orientation": druid_orientation,
	})
	if _is_abyss_card_surcharge_pending(frame.user, frame.card):
		frame.user.battle_action_flags["abyss_card_surcharge_turn"] = frame.user.turn_serial
	frame.user.bind_next_card_damage_bonus(frame.card)

	frame.resolved_successfully = true
	enqueue_effect(
		Callable(self, "_resolve_paid_card_effect"),
		[frame, context_dict],
		CARD_EFFECT_CONTINUATION_PRIORITY,
		"%s 支付后效果" % frame.card.card_name,
		context_dict
	)


func _resolve_paid_card_effect(frame: BattleCardFrame, context_dict: Dictionary) -> void:
	if frame == null or not frame.resolved_successfully or frame.user == null or frame.card == null:
		return
	if not frame.user.is_alive():
		_emit_log("%s 在支付触发结算后已无法行动，%s 的效果未执行。" % [frame.user.get_display_name(), frame.card.card_name])
		return
	var source_is_valid := frame.user.has_card_in_hand(frame.card)
	if frame.context.play_mode == CardEnums.CardPlayMode.MOMENTUM:
		source_is_valid = frame.user.has_card_in_exile(frame.card)
	if not source_is_valid:
		_emit_log("%s 已不在预期区域，效果未执行。" % frame.card.card_name)
		return
	for target_value in frame.targets:
		if not (target_value is BattleUnitState):
			continue
		var target := target_value as BattleUnitState
		if should_cancel_hostile_effect(frame.user, target, frame.card.card_name, frame.card):
			return
	var duplicate_targets := frame.user.get_equipment_card_duplicate_targets(frame.card, frame.targets, context_dict)
	frame.card.play(context_dict, frame.targets)
	for duplicate_target in duplicate_targets:
		var duplicate_context := context_dict.duplicate(true)
		duplicate_context["equipment_duplicate"] = true
		enqueue_effect(
			Callable(frame.card, "play"),
			[duplicate_context, [duplicate_target]],
			(frame.card.effect.effect_priority if frame.card.effect != null else 0) - 100,
			"%s：装备复制" % frame.card.card_name,
			duplicate_context
		)


func _finish_card_play_frame(frame: BattleCardFrame) -> void:
	if frame == null or frame.card == null:
		return
	cards_in_flight.erase(frame.card.get_instance_id())
	if not frame.resolved_successfully or frame.user == null:
		return

	if frame.discard_after_play:
		if should_card_enter_curse_after_play(frame):
			finish_core_curse_to_zone(frame)
		elif should_card_exile_after_play(frame):
			finish_card_to_exile(frame)
		elif should_card_enter_mana_after_play(frame):
			finish_druid_card_to_mana(frame)
		else:
			frame.user.discard_card(frame.card, {
				"controller": self,
				"reason": "card_after_play",
				"source": frame.user,
				"source_card": frame.card,
				"card_context": frame.context,
			})
	frame.user.finish_next_card_damage_bonus(frame.card)
	var actual_ap_cost := int(frame.context.extra.get("actual_ap_cost", frame.card.ap_cost))
	frame.user.notify_after_card_played(frame.card, {
		"controller": self,
		"card": frame.card,
		"source": frame.user,
		"play_mode": frame.context.play_mode,
		"equipment_slot": frame.context.equipment_slot,
		"ap_cost": actual_ap_cost,
		"action_id": get_current_action_id(),
		"targets": frame.targets,
	})
	EnemyRuleDispatcher.on_card_played(self, frame.user, frame.card)
	_apply_adventure_card_infusion(frame.user, frame.card, frame.context.extra)
	_notify_opponents_card_completed(frame.user, frame.card)
	if frame.user.is_ranger():
		frame.user.ranger_state.cards_played_this_turn += 1
		if frame.context.play_mode == CardEnums.CardPlayMode.COMBO and frame.card.is_available_to_class(CardEnums.CardClass.RANGER):
			gain_ranger_combo(frame.user, 1, {
				"card": frame.card,
				"play_mode": frame.context.play_mode,
				"equipment_slot": frame.context.equipment_slot,
			})
		frame.user.ranger_state.combo_window_open = true
		_resolve_ranger_no_place_recall(frame.user)
	_emit_log("%s 打出 %s，消耗 %d AP。" % [frame.user.get_display_name(), frame.card.card_name, actual_ap_cost])
	state_changed.emit()
	_check_battle_end()


func _resolve_card_primary_cell(user: BattleUnitState, targets: Array) -> Vector2i:
	if not targets.is_empty():
		if targets[0] is Vector2i:
			return targets[0] as Vector2i
		var target := targets[0] as BattleUnitState
		if target != null:
			return target.cell
	return user.cell if user != null else BattleHexGrid.INVALID_CELL


func _apply_adventure_card_infusion(user: BattleUnitState, card: CardData, extra_context: Dictionary) -> void:
	if user == null or card == null:
		return
	var runtime_state := user.get_card_runtime_state(card, false)
	if runtime_state.is_empty() or not runtime_state.has("adventure_element_infusion") \
		or bool(runtime_state.get("adventure_element_infusion_used", false)):
		return
	runtime_state["adventure_element_infusion_used"] = true
	var cell := extra_context.get("adventure_infusion_cell", user.cell) as Vector2i
	apply_base_surface_element(cell, int(runtime_state["adventure_element_infusion"]))


func should_card_enter_curse_after_play(frame: BattleCardFrame) -> bool:
	return frame != null and frame.card != null and frame.card.is_curse_card() \
		and frame.card.bound_curse_instance != null \
		and frame.card.bound_curse_instance.state == CurseInstance.State.INDUSTRY


func finish_core_curse_to_zone(frame: BattleCardFrame) -> void:
	if frame == null or frame.user == null or frame.card == null:
		return
	var curse := frame.card.bound_curse_instance
	if curse == null or not curse.transform_to_report():
		return
	var index := frame.user.hand.find(frame.card)
	if index >= 0:
		frame.user.hand.remove_at(index)
	frame.user.clear_card_runtime_state(frame.card)
	var curse_owner := _find_report_interceptor(frame.user, curse)
	if curse_owner != frame.user and frame.user.character_state != null and curse_owner.character_state != null:
		frame.user.character_state.curse_instances.erase(curse)
		curse_owner.character_state.curse_instances.append(curse)
	curse_owner.add_curse_to_zone(curse, {
		"controller": self,
		"reason": "industry_resolved",
		"source_card": frame.card,
	})
	_emit_log("%s 的诅咒“%s”由业转化为报并进入%s的诅咒区。" % [frame.user.get_display_name(), curse.get_display_name(), curse_owner.get_display_name()])


func _find_report_interceptor(original_owner: BattleUnitState, incoming: CurseInstance) -> BattleUnitState:
	for candidate in player_units:
		if candidate == null or candidate == original_owner or not candidate.is_alive():
			continue
		for active_curse in candidate.curse_zone:
			if not candidate.is_curse_effect_active(active_curse) or active_curse.definition == null or active_curse.definition.effect == null:
				continue
			if active_curse.definition.effect.can_intercept_report(candidate, active_curse, original_owner, incoming, {"controller": self}):
				return candidate
	return original_owner


func _snapshot_card_payment_state(user: BattleUnitState) -> Dictionary:
	if user == null:
		return {}

	var snapshot := {
		"current_ap": user.current_ap,
		"current_health": user.get_current_health(),
		"draw_pile": user.draw_pile.duplicate(),
		"hand": user.hand.duplicate(),
		"discard_pile": user.discard_pile.duplicate(),
		"exiled_pile": user.exiled_pile.duplicate(),
		"mana_zone": user.mana_zone.duplicate(),
		"enchant_zone": user.enchant_zone.duplicate(),
		"curse_zone": user.curse_zone.duplicate(),
		"curse_wave": user.curse_wave,
		"curse_runtime_states": user.curse_runtime_states.duplicate(true),
		"card_runtime_states": user.card_runtime_states.duplicate(true),
		"equipment_runtime_states": user.snapshot_equipment_runtime_states(),
		"pending_next_card_damage_bonus": user.pending_next_card_damage_bonus,
		"active_card_damage_bonuses": user.active_card_damage_bonuses.duplicate(true),
		"pending_next_attack_damage_bonus": user.pending_next_attack_damage_bonus,
		"active_attack_lifesteal_cards": user.active_attack_lifesteal_cards.duplicate(true),
		"distortion_state": user.distortion_state.snapshot(),
		"statuses": _duplicate_resources(user.statuses),
		"druid_transformed": user.druid_transformed,
		"druid_prepare_used": user.druid_prepare_used,
		"druid_spent_mana": user.druid_spent_mana,
		"druid_temporary_mana": user.druid_temporary_mana,
		"druid_max_health_loss": user.druid_max_health_loss,
		"ranger_elements": user.ranger_state.element_inventory.duplicate(true),
		"ranger_prepared_blend": user.ranger_state.prepared_blend,
		"ranger_prepared_weapon_slot": user.ranger_state.prepared_weapon_slot,
		"mage_state": user.mage_state.snapshot(),
		"warlock_state": user.warlock_state.snapshot(),
		"mage_infusion_state": mage_infusion_state.snapshot(),
		"rng_state": rng.state,
	}
	if user.character_state != null:
		snapshot["class_resources"] = _duplicate_resources(user.character_state.class_resources)
		snapshot["inventory"] = _duplicate_resources(user.character_state.inventory)
		snapshot["weapon_equipment"] = user.character_state.weapon_equipment
		snapshot["weapon_face"] = user.character_state.weapon_face
		snapshot["reserve_weapon_equipment"] = user.character_state.reserve_weapon_equipment
		snapshot["reserve_weapon_face"] = user.character_state.reserve_weapon_face
		snapshot["equipment_instance_ids"] = user.character_state.equipment_instance_ids.duplicate(true)
		snapshot["armor_equipment"] = user.character_state.armor_equipment
		snapshot["accessory_equipment_1"] = user.character_state.accessory_equipment_1
		snapshot["accessory_equipment_2"] = user.character_state.accessory_equipment_2
	return snapshot


func _restore_card_payment_state(user: BattleUnitState, snapshot: Dictionary) -> void:
	if user == null or snapshot.is_empty():
		return

	user.current_ap = int(snapshot.get("current_ap", user.current_ap))
	user.set_current_health(int(snapshot.get("current_health", user.get_current_health())))

	var draw_snapshot: Array = snapshot.get("draw_pile", []) as Array
	var hand_snapshot: Array = snapshot.get("hand", []) as Array
	var discard_snapshot: Array = snapshot.get("discard_pile", []) as Array
	var exile_snapshot: Array = snapshot.get("exiled_pile", []) as Array
	var mana_snapshot: Array = snapshot.get("mana_zone", []) as Array
	var enchant_snapshot: Array = snapshot.get("enchant_zone", []) as Array
	var curse_snapshot: Array = snapshot.get("curse_zone", []) as Array
	var runtime_snapshot: Dictionary = snapshot.get("card_runtime_states", {}) as Dictionary
	user.draw_pile.assign(draw_snapshot)
	user.hand.assign(hand_snapshot)
	user.discard_pile.assign(discard_snapshot)
	user.exiled_pile.assign(exile_snapshot)
	user.mana_zone.assign(mana_snapshot)
	user.enchant_zone.assign(enchant_snapshot)
	user.curse_zone.assign(curse_snapshot)
	user.curse_wave = int(snapshot.get("curse_wave", user.curse_wave))
	user.curse_runtime_states = (snapshot.get("curse_runtime_states", {}) as Dictionary).duplicate(true)
	user.card_runtime_states = runtime_snapshot.duplicate(true)
	user.restore_equipment_runtime_states(snapshot.get("equipment_runtime_states", {}) as Dictionary)
	user.pending_next_card_damage_bonus = int(snapshot.get("pending_next_card_damage_bonus", 0))
	user.active_card_damage_bonuses = (snapshot.get("active_card_damage_bonuses", {}) as Dictionary).duplicate(true)
	user.pending_next_attack_damage_bonus = int(snapshot.get("pending_next_attack_damage_bonus", 0))
	user.active_attack_lifesteal_cards = (snapshot.get("active_attack_lifesteal_cards", {}) as Dictionary).duplicate(true)
	user.distortion_state.restore(snapshot.get("distortion_state", {}) as Dictionary)
	var status_snapshot: Array = snapshot.get("statuses", []) as Array
	user.statuses.assign(status_snapshot)
	user.druid_transformed = bool(snapshot.get("druid_transformed", user.druid_transformed))
	user.druid_prepare_used = bool(snapshot.get("druid_prepare_used", user.druid_prepare_used))
	user.druid_spent_mana = int(snapshot.get("druid_spent_mana", user.druid_spent_mana))
	user.druid_temporary_mana = int(snapshot.get("druid_temporary_mana", user.druid_temporary_mana))
	user.druid_max_health_loss = int(snapshot.get("druid_max_health_loss", user.druid_max_health_loss))
	user.ranger_state.element_inventory = (snapshot.get("ranger_elements", {}) as Dictionary).duplicate(true)
	user.ranger_state.prepared_blend = int(snapshot.get("ranger_prepared_blend", user.ranger_state.prepared_blend))
	user.ranger_state.prepared_weapon_slot = str(snapshot.get("ranger_prepared_weapon_slot", user.ranger_state.prepared_weapon_slot))
	user.mage_state.restore(snapshot.get("mage_state", {}) as Dictionary)
	user.warlock_state.restore(snapshot.get("warlock_state", {}) as Dictionary)
	mage_infusion_state.restore(snapshot.get("mage_infusion_state", {}) as Dictionary)
	rng.state = int(snapshot.get("rng_state", rng.state))
	if user.character_state != null:
		var resource_snapshot: Array = snapshot.get("class_resources", []) as Array
		var inventory_snapshot: Array = snapshot.get("inventory", []) as Array
		user.character_state.class_resources.assign(resource_snapshot)
		user.character_state.inventory.assign(inventory_snapshot)
		user.character_state.weapon_equipment = snapshot.get("weapon_equipment") as EquipmentData
		user.character_state.weapon_face = int(snapshot.get("weapon_face", user.character_state.weapon_face))
		user.character_state.reserve_weapon_equipment = snapshot.get("reserve_weapon_equipment") as EquipmentData
		user.character_state.reserve_weapon_face = int(snapshot.get("reserve_weapon_face", user.character_state.reserve_weapon_face))
		user.character_state.equipment_instance_ids = (
			snapshot.get("equipment_instance_ids", user.character_state.equipment_instance_ids) as Dictionary
		).duplicate(true)
		user.character_state.armor_equipment = snapshot.get("armor_equipment") as EquipmentData
		user.character_state.accessory_equipment_1 = snapshot.get("accessory_equipment_1") as EquipmentData
		user.character_state.accessory_equipment_2 = snapshot.get("accessory_equipment_2") as EquipmentData
		user.sync_ranger_element_inventory()


func _rollback_card_payment(user: BattleUnitState, snapshot: Dictionary, effect_queue_size: int) -> void:
	_restore_card_payment_state(user, snapshot)
	resolution_runner.truncate_current_effect_queue(effect_queue_size)


func _duplicate_resources(source: Array) -> Array:
	var result: Array = []
	for value in source:
		if value is Resource:
			result.append((value as Resource).duplicate(false))
		else:
			result.append(value)
	return result


func basic_attack(attacker: BattleUnitState, target: BattleUnitState, equipment_slot: String = "") -> bool:
	if not _can_submit_turn_action(attacker, "普通攻击"):
		return false
	if target == null or not target.is_alive():
		_emit_log("攻击目标无效。")
		return false
	if attacker.faction != target.faction and is_unit_concealed(target):
		_emit_log("%s 位于隐蔽地表，不能被单体攻击指定。" % target.get_display_name())
		return false

	if attacker.current_ap < config.basic_attack_ap_cost:
		_emit_log("%s AP不足，普通攻击需要 %d AP。" % [attacker.get_display_name(), config.basic_attack_ap_cost])
		return false

	var attack_range := get_effective_attack_range_against(attacker, target, equipment_slot)
	var distance := attacker.get_range_distance_to(target, {"controller": self, "equipment_slot": equipment_slot})
	if distance > attack_range:
		_emit_log("距离 %.0f 超出 %s 的攻击距离 %.0f。" % [distance, attacker.get_display_name(), attack_range])
		return false
	var profile := attacker.build_strike_profile_object(equipment_slot)
	if profile.primary_range_type == EquipmentData.WeaponRangeType.RANGED \
			and not targeting.has_line_of_sight_between_units(attacker, target):
		_emit_log("攻击路径被战场对象阻挡。")
		return false

	return push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_basic_attack_action"),
		[attacker, target, equipment_slot],
		0,
		"%s 普通攻击" % attacker.get_display_name(),
		{"attacker": attacker, "target": target, "equipment_slot": equipment_slot}
	))


func _resolve_basic_attack_action(attacker: BattleUnitState, target: BattleUnitState, equipment_slot: String = "") -> void:
	if not _is_turn_action_execution_valid(attacker):
		return
	if target == null or not target.is_alive():
		_emit_log("攻击目标无效。")
		return
	if attacker.faction != target.faction and is_unit_concealed(target):
		_emit_log("%s 位于隐蔽地表，不能被单体攻击指定。" % target.get_display_name())
		return
	if attacker.current_ap < config.basic_attack_ap_cost:
		_emit_log("%s AP不足，普通攻击需要 %d AP。" % [attacker.get_display_name(), config.basic_attack_ap_cost])
		return

	var attack_range := get_effective_attack_range_against(attacker, target, equipment_slot)
	var distance := attacker.get_range_distance_to(target, {"controller": self, "equipment_slot": equipment_slot})
	if distance > attack_range:
		_emit_log("距离 %.0f 超出 %s 的攻击距离 %.0f。" % [distance, attacker.get_display_name(), attack_range])
		return
	var profile := attacker.build_strike_profile_object(equipment_slot)
	if profile.primary_range_type == EquipmentData.WeaponRangeType.RANGED \
			and not targeting.has_line_of_sight_between_units(attacker, target):
		_emit_log("攻击路径被战场对象阻挡。")
		return

	_close_ranger_combo_window(attacker)
	attacker.current_ap -= config.basic_attack_ap_cost
	perform_strike(attacker, target, null, "普通攻击", equipment_slot)
	state_changed.emit()
	_check_battle_end()


func basic_attack_object(
	attacker: BattleUnitState,
	target: BattleObjectState,
	equipment_slot: String = ""
) -> bool:
	if not _can_submit_turn_action(attacker, "\u666e\u901a\u653b\u51fb"):
		return false
	if target == null or not target.is_targetable():
		_emit_log("\u6218\u573a\u5bf9\u8c61\u76ee\u6807\u65e0\u6548\u3002")
		return false
	if attacker.current_ap < config.basic_attack_ap_cost:
		return false
	var attack_range := get_effective_attack_range_at_cell(attacker, target.cell, equipment_slot)
	var distance := map_data.get_distance(attacker.cell, target.cell)
	if distance > attack_range:
		return false
	var profile := attacker.build_strike_profile_object(equipment_slot)
	if profile.primary_range_type == EquipmentData.WeaponRangeType.RANGED \
			and not targeting.has_line_of_sight(attacker.cell, target.cell):
		_emit_log("\u653b\u51fb\u8def\u5f84\u88ab\u6218\u573a\u5bf9\u8c61\u963b\u6321\u3002")
		return false
	return push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_basic_attack_object_action"),
		[attacker, target, equipment_slot],
		0,
		"%s \u653b\u51fb %s" % [attacker.get_display_name(), target.get_display_name()],
		{"attacker": attacker, "target_object": target, "equipment_slot": equipment_slot}
	))


func _resolve_basic_attack_object_action(
	attacker: BattleUnitState,
	target: BattleObjectState,
	equipment_slot: String
) -> void:
	if not _is_turn_action_execution_valid(attacker) or target == null \
			or not target.is_targetable() or not target.can_be_damaged():
		return
	var attack_range := get_effective_attack_range_at_cell(attacker, target.cell, equipment_slot)
	if map_data.get_distance(attacker.cell, target.cell) > attack_range:
		return
	var profile := attacker.build_strike_profile_object(equipment_slot)
	if profile.primary_range_type == EquipmentData.WeaponRangeType.RANGED \
			and not targeting.has_line_of_sight(attacker.cell, target.cell):
		return
	if attacker.current_ap < config.basic_attack_ap_cost:
		return
	_close_ranger_combo_window(attacker)
	attacker.current_ap -= config.basic_attack_ap_cost
	perform_object_strike_with_modifier(
		attacker,
		target,
		null,
		0,
		"\u666e\u901a\u653b\u51fb",
		equipment_slot
	)
	state_changed.emit()


func perform_strike(attacker: BattleUnitState, target: BattleUnitState, source = null, label: String = "打击", equipment_slot: String = "") -> int:
	return strike_resolver.perform_strike(attacker, target, source, label, equipment_slot)


func perform_strike_with_modifier(attacker: BattleUnitState, target: BattleUnitState, source = null, damage_modifier: int = 0, label: String = "打击", equipment_slot: String = "") -> int:
	return strike_resolver.perform_strike_with_modifier(attacker, target, source, damage_modifier, label, equipment_slot)


func perform_strike_with_multiplier(attacker: BattleUnitState, target: BattleUnitState, source = null, damage_multiplier: float = 1.0, label: String = "打击", equipment_slot: String = "") -> int:
	return strike_resolver.perform_strike_with_multiplier(attacker, target, source, damage_multiplier, label, equipment_slot)


func perform_strike_with_modifier_and_multiplier(attacker: BattleUnitState, target: BattleUnitState, source = null, damage_modifier: int = 0, damage_multiplier: float = 1.0, label: String = "打击", equipment_slot: String = "") -> int:
	return strike_resolver.perform_strike_with_modifier_and_multiplier(attacker, target, source, damage_modifier, damage_multiplier, label, equipment_slot)


func perform_strike_with_options(attacker: BattleUnitState, target: BattleUnitState, source = null, damage_modifier: int = 0, damage_multiplier: float = 1.0, label: String = "打击", equipment_slot: String = "", options: Dictionary = {}) -> int:
	return strike_resolver.perform_strike_with_modifier_and_multiplier(attacker, target, source, damage_modifier, damage_multiplier, label, equipment_slot, options)


func get_card_ap_cost(user: BattleUnitState, card: CardData, context: Dictionary = {}) -> int:
	if user == null or card == null:
		return 0

	var cost_context := context.duplicate()
	cost_context["controller"] = self
	cost_context["user"] = user
	cost_context["card"] = card
	if not cost_context.has("druid_orientation"):
		cost_context["druid_orientation"] = _get_druid_orientation_for_card(user, card)
	var result := user.get_card_ap_cost(card, cost_context)
	if _is_abyss_card_surcharge_pending(user, card):
		result += 1
	return result


func _is_abyss_card_surcharge_pending(user: BattleUnitState, card: CardData) -> bool:
	if user == null or card == null or card.card_type == CardEnums.CardType.CURSE:
		return false
	if not surface_state.is_terrain_effective(user.cell, BattleSurfaceState.Terrain.ABYSS):
		return false
	return int(user.battle_action_flags.get("abyss_card_surcharge_turn", -1)) != user.turn_serial


func get_card_ap_cost_for_mode(user: BattleUnitState, card: CardData, play_mode: int, context: Dictionary = {}) -> int:
	if play_mode == CardEnums.CardPlayMode.NORMAL:
		return get_card_ap_cost(user, card, context)

	return 0


func can_play_card_with_mode(user: BattleUnitState, card: CardData, play_mode: int) -> bool:
	if card == null or not _can_submit_turn_action(user, "出牌", false):
		return false
	if not _card_source_is_valid(user, card, play_mode, false):
		return false
	if not _card_supports_play_mode_for_user(user, card, play_mode):
		return false
	if not _is_druid_card_play_state_valid(user, card, false):
		return false
	var context := {
		"controller": self,
		"user": user,
		"card": card,
		"play_mode": play_mode,
		"druid_orientation": _get_druid_orientation_for_card(user, card),
	}
	if user.current_ap < get_card_ap_cost_for_mode(user, card, play_mode, context):
		return false
	if not card.can_play(context):
		return false

	if _is_ranger_universal_combo(user, play_mode):
		return true
	return card.can_pay_special_conditions(_build_special_play_condition_context(user, card, play_mode), play_mode)


func can_preview_card_targets(user: BattleUnitState, card: CardData, targets: Array, equipment_slot: String = "", play_mode: int = CardEnums.CardPlayMode.NORMAL, extra_context: Dictionary = {}) -> bool:
	if card == null or not _can_submit_turn_action(user, "选择目标", false):
		return false

	return _targets_are_valid(user, card, targets, false, equipment_slot, play_mode, extra_context)


func can_activate_exiled_card(user: BattleUnitState, card: CardData) -> bool:
	if phase != Phase.BATTLE or turn_flow_state != TurnFlowState.ACTIVE or is_resolving_actions() or resolution_state_notification_active:
		return false
	if user == null or card == null or not user.is_alive():
		return false
	if current_unit != user or user.faction != BattleUnitState.Faction.PLAYER:
		return false
	if not user.has_card_in_exile(card):
		return false

	return card.can_activate_from_exile(_build_exiled_card_action_context(user, card))


func can_activate_discard_card(user: BattleUnitState, card: CardData) -> bool:
	if phase != Phase.BATTLE or turn_flow_state != TurnFlowState.ACTIVE or is_resolving_actions():
		return false
	if user == null or card == null or current_unit != user or not user.has_card_in_discard(card):
		return false
	return card.can_activate_from_discard({"controller": self, "user": user, "card": card, "ranger_discard_activation": true})


func activate_discard_card(user: BattleUnitState, card: CardData, extra_context: Dictionary = {}) -> bool:
	var context := extra_context.duplicate()
	context["controller"] = self
	context["user"] = user
	context["card"] = card
	context["ranger_discard_activation"] = true
	if not can_activate_discard_card(user, card):
		return false
	var activated := card.activate_from_discard(context)
	if activated:
		_close_ranger_combo_window(user)
	return activated


func can_activate_enchant_card(user: BattleUnitState, card: CardData) -> bool:
	if phase != Phase.BATTLE or turn_flow_state != TurnFlowState.ACTIVE or is_resolving_actions() or resolution_state_notification_active:
		return false
	if user == null or card == null or not user.is_alive():
		return false
	if current_unit != user or user.faction != BattleUnitState.Faction.PLAYER:
		return false
	if not user.has_card_in_enchant(card):
		return false
	return card.can_activate_from_enchant(_build_enchant_card_action_context(user, card))


func activate_exiled_card(user: BattleUnitState, card: CardData) -> bool:
	if not can_activate_exiled_card(user, card):
		_emit_log("当前无法发动这张放逐区卡牌。")
		return false

	return push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_exiled_card_action"),
		[user, card],
		0,
		"%s 发动放逐区卡牌" % user.get_display_name(),
		_build_exiled_card_action_context(user, card)
	))


func activate_enchant_card(user: BattleUnitState, card: CardData) -> bool:
	if not can_activate_enchant_card(user, card):
		_emit_log("当前无法发动这张附魔区卡牌。")
		return false

	return push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_enchant_card_action"),
		[user, card],
		0,
		"%s 发动附魔区卡牌" % user.get_display_name(),
		_build_enchant_card_action_context(user, card)
	))


func _resolve_exiled_card_action(user: BattleUnitState, card: CardData) -> void:
	if user == null or card == null or not user.is_alive():
		return
	if not user.has_card_in_exile(card):
		return

	var context := _build_exiled_card_action_context(user, card)
	if not card.can_activate_from_exile(context):
		return

	card.activate_from_exile(context)
	state_changed.emit()


func _resolve_enchant_card_action(user: BattleUnitState, card: CardData) -> void:
	if user == null or card == null or not user.is_alive():
		return
	if not user.has_card_in_enchant(card):
		return

	var context := _build_enchant_card_action_context(user, card)
	if not card.can_activate_from_enchant(context):
		return
	card.activate_from_enchant(context)
	state_changed.emit()


func _build_exiled_card_action_context(user: BattleUnitState, card: CardData) -> Dictionary:
	return {
		"controller": self,
		"user": user,
		"card": card,
	}


func _build_enchant_card_action_context(user: BattleUnitState, card: CardData) -> Dictionary:
	return {
		"controller": self,
		"user": user,
		"card": card,
		"zone_name": "enchant",
		"action_id": get_current_action_id(),
	}


func _build_special_play_condition_context(user: BattleUnitState, card: CardData, play_mode: int) -> Dictionary:
	return {
		"controller": self,
		"user": user,
		"card": card,
		"play_mode": play_mode,
		"play_mode_label": CardEnums.play_mode_label(play_mode),
		"druid_orientation": _get_druid_orientation_for_card(user, card),
	}


func _card_supports_play_mode_for_user(user: BattleUnitState, card: CardData, play_mode: int) -> bool:
	if card == null:
		return false
	if play_mode != CardEnums.CardPlayMode.COMBO:
		return card.supports_play_mode(play_mode)
	if user == null:
		return false
	if not user.is_ranger():
		return card.supports_play_mode(play_mode)
	if not user.ranger_state.combo_window_open:
		return false
	return card.supports_play_mode(play_mode) or user.ranger_state.universal_combo_ready


func _is_ranger_universal_combo(user: BattleUnitState, play_mode: int) -> bool:
	return (
		play_mode == CardEnums.CardPlayMode.COMBO
		and user != null
		and user.is_ranger()
		and user.ranger_state.combo_window_open
		and user.ranger_state.universal_combo_ready
	)


func _resolve_ranger_no_place_recall(unit: BattleUnitState) -> void:
	if unit == null or not unit.is_ranger() or unit.ranger_state.no_place_recall_charges <= 0:
		return
	var candidate: CardData
	if unit.hand.is_empty():
		for card in unit.discard_pile:
			if card != null and card.effect is RangerNoPlaceToHuntCardEffect:
				candidate = card
				break
		if candidate != null and unit.move_discard_card_to_hand(candidate):
			unit.ranger_state.no_place_recall_charges -= 1
	if candidate == null and unit.ranger_state.cards_played_this_turn == 3:
		for card in unit.draw_pile:
			if card != null and card.effect is RangerNoPlaceToHuntCardEffect:
				candidate = card
				break
		if candidate != null and unit.move_draw_card_to_hand(candidate):
			unit.ranger_state.no_place_recall_charges -= 1
	if candidate != null:
		_emit_log("%s 自动将无处不猎移回手牌，本场剩余 %d 次。" % [
			unit.get_display_name(),
			unit.ranger_state.no_place_recall_charges,
		])


func _card_source_is_valid(user: BattleUnitState, card: CardData, play_mode: int, write_log: bool, source_context: Dictionary = {}) -> bool:
	if bool(source_context.get("mage_primordial", false)) \
			and int(source_context.get("source_zone", CardEnums.CardZone.NONE)) == CardEnums.CardZone.DRAW:
		if user.draw_pile.has(card):
			return true
		if write_log:
			_emit_log("%s 不在牌库中。" % card.card_name)
		return false
	match play_mode:
		CardEnums.CardPlayMode.NORMAL, CardEnums.CardPlayMode.COMBO:
			if user.has_card_in_hand(card):
				return true
			if write_log:
				_emit_log("%s 不在手牌中。" % card.card_name)
			return false
		CardEnums.CardPlayMode.MOMENTUM:
			if user.has_card_in_discard(card):
				return true
			if write_log:
				_emit_log("%s 不在弃牌堆中。" % card.card_name)
			return false
		_:
			return false


func can_unit_reach_cell_with_ap(unit: BattleUnitState, cell: Vector2i, max_ap: int = 1, write_log: bool = false, apply_ap_cost_modifiers: bool = true) -> bool:
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return false
	if not _is_cell_valid_for_unit(unit, cell, false, write_log):
		return false

	var path := get_movement_path(unit, cell)
	if path.is_empty():
		return false
	var movement_cost := _get_path_movement_cost(unit, path)
	var ap_cost := unit.get_move_ap_cost(movement_cost, config) if apply_ap_cost_modifiers else ceili(float(movement_cost) / float(unit.get_move_distance_per_ap(config)))
	if ap_cost > max_ap:
		if write_log:
			_emit_log("%s 无法以 %d AP 移动到目标位置。" % [unit.get_display_name(), max_ap])
		return false

	return true


func can_unit_reach_cell_with_ap_and_agility_modifier(unit: BattleUnitState, cell: Vector2i, max_ap: int = 1, agility_modifier: int = 0, write_log: bool = false) -> bool:
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return false

	var max_distance := get_ap_movement_distance(unit, max_ap, agility_modifier)
	return can_unit_reach_cell_with_distance(unit, cell, max_distance, write_log)


func can_unit_reach_cell_with_agility_modifier(unit: BattleUnitState, cell: Vector2i, agility_modifier: int = 0, write_log: bool = false) -> bool:
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return false

	var max_distance := get_agility_movement_distance(unit, agility_modifier)
	return can_unit_reach_cell_with_distance(unit, cell, max_distance, write_log)


func can_unit_reach_cell_with_distance(unit: BattleUnitState, cell: Vector2i, max_distance: int, write_log: bool = false) -> bool:
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return false
	if not _is_cell_valid_for_unit(unit, cell, false, write_log):
		return false

	var path := get_movement_path(unit, cell)
	if path.is_empty():
		return false
	var movement_cost := _get_path_movement_cost(unit, path)
	if movement_cost > max_distance:
		if write_log:
			_emit_log("%s 无法移动到目标位置，距离 %.0f 超出可移动距离 %.0f。" % [
				unit.get_display_name(),
				movement_cost,
				max_distance,
			])
		return false

	return true


func get_agility_movement_distance(unit: BattleUnitState, agility_modifier: int = 0) -> int:
	if unit == null:
		return 0

	if config.agility_per_move_cell <= 0:
		return 0
	return maxi(0, floori(float(unit.get_agility() + agility_modifier) / float(config.agility_per_move_cell)))


func get_ap_movement_distance(unit: BattleUnitState, ap_budget: int, agility_modifier: int = 0) -> int:
	if unit == null:
		return 0

	var base_distance := maxi(0, ap_budget) * unit.get_move_distance_per_ap(config, agility_modifier)
	return base_distance + (unit.get_next_move_distance_bonus({"controller": self, "ap_budget": ap_budget}) if ap_budget > 0 else 0)


func get_reachable_cells(unit: BattleUnitState, ap_budget: int = -1) -> Array[Vector2i]:
	var available_ap := unit.current_ap if unit != null and ap_budget < 0 else ap_budget
	return get_reachable_cells_for_ap(unit, available_ap, true)


func get_reachable_cells_for_ap(unit: BattleUnitState, ap_budget: int, apply_ap_cost_modifiers: bool = true, agility_modifier: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if unit == null or map_data == null or not map_data.is_valid_cell(unit.cell):
		return result
	var available_ap := maxi(0, ap_budget)
	var blocked_cells := _get_blocked_movement_cells(unit)
	if unit.is_flying():
		for cell in map_data.get_all_cells():
			if blocked_cells.has(cell):
				continue
			var movement_cost := BattleHexGrid.distance(unit.cell, cell)
			if _get_budgeted_movement_ap_cost(unit, movement_cost, apply_ap_cost_modifiers, agility_modifier) <= available_ap:
				result.append(cell)
		return result
	var movement_costs := BattlePathfinder.find_reachable_costs(
		map_data,
		surface_state,
		unit.cell,
		func(candidate: Vector2i) -> bool: return not blocked_cells.has(candidate)
	)
	for cell in map_data.get_all_cells():
		if not movement_costs.has(cell):
			continue
		var movement_cost := int(movement_costs[cell])
		if _get_budgeted_movement_ap_cost(unit, movement_cost, apply_ap_cost_modifiers, agility_modifier) > available_ap:
			continue
		result.append(cell)
	return result


func _get_budgeted_movement_ap_cost(unit: BattleUnitState, movement_cost: int, apply_ap_cost_modifiers: bool, agility_modifier: int = 0) -> int:
	if apply_ap_cost_modifiers:
		return unit.get_move_ap_cost(movement_cost, config)
	var move_distance := maxi(1, unit.get_move_distance_per_ap(config, agility_modifier))
	return ceili(float(movement_cost) / float(move_distance))


func _get_blocked_movement_cells(unit: BattleUnitState) -> Dictionary:
	var blocked := {}
	if unit == null:
		return blocked
	for occupied_cell in unit.get_occupied_cells():
		if occupied_cell != unit.cell:
			blocked[occupied_cell] = true
	for other in units:
		if other == null or other == unit or not other.is_deployed or not other.is_alive():
			continue
		for occupied_cell in other.get_occupied_cells():
			blocked[occupied_cell] = true
	for battle_object in battle_objects:
		if battle_object != null and battle_object.blocks_movement():
			blocked[battle_object.cell] = true
	return blocked


func apply_card_movement_to_cell(unit: BattleUnitState, cell: Vector2i, label: String = "卡牌移动") -> bool:
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return false
	if not _is_cell_valid_for_unit(unit, cell, false):
		return false
	if not unit.can_start_voluntary_movement():
		return false

	var start_cell := unit.cell
	unit.set_hex_cell(cell, map_data)
	if not unit.is_flying():
		process_surface_entry(unit, cell)
	_complete_card_movement(unit, start_cell, label)
	return true


func apply_card_path_movement_to_cell(
	unit: BattleUnitState,
	cell: Vector2i,
	max_ap: int = -1,
	apply_ap_cost_modifiers: bool = true,
	label: String = "卡牌移动"
	) -> bool:
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return false
	if not unit.can_start_voluntary_movement() or not _is_cell_valid_for_unit(unit, cell, false):
		return false
	var path := get_movement_path(unit, cell)
	if path.is_empty():
		return false
	var movement_cost := _get_path_movement_cost(unit, path)
	if max_ap >= 0 and _get_budgeted_movement_ap_cost(unit, movement_cost, apply_ap_cost_modifiers) > max_ap:
		return false

	var start_cell := unit.cell
	for index in range(1, path.size()):
		unit.set_hex_cell(path[index], map_data)
		if process_surface_entry(unit, path[index]):
			break
	_complete_card_movement(unit, start_cell, label)
	return true


func _complete_card_movement(unit: BattleUnitState, start_cell: Vector2i, label: String) -> void:
	_notify_opponents_movement_completed(unit)
	unit.notify_movement_completed({
		"controller": self,
		"start_cell": start_cell,
		"end_cell": unit.cell,
		"distance": BattleHexGrid.distance(start_cell, unit.cell),
		"forced": false,
		"card_movement": true,
	})
	_emit_log("%s 移动到格 (%d, %d)（%s）。" % [unit.get_display_name(), unit.cell.x, unit.cell.y, label])
	state_changed.emit()


func apply_movement_effect(unit: BattleUnitState, target_cell: Vector2i, agility_modifier: int = 0, truncate_to_range: bool = true, ap_budget: int = -1) -> Dictionary:
	var result := {
		"success": false,
		"start_cell": BattleHexGrid.INVALID_CELL,
		"end_cell": BattleHexGrid.INVALID_CELL,
		"requested_cell": target_cell,
		"max_distance": 0,
	}
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return result
	if not unit.can_start_voluntary_movement():
		return result

	var start_cell := unit.cell
	var end_cell := target_cell
	result["start_cell"] = start_cell

	if not map_data.is_valid_cell(end_cell):
		return result

	var max_distance := get_agility_movement_distance(unit, agility_modifier)
	if ap_budget >= 0:
		max_distance = get_ap_movement_distance(unit, ap_budget, agility_modifier)
	result["max_distance"] = max_distance
	var distance := map_data.get_distance(start_cell, end_cell)
	if not truncate_to_range and distance > max_distance:
		return result
	if truncate_to_range and distance > max_distance:
		var path := map_data.get_line(start_cell, end_cell)
		end_cell = path[mini(max_distance, path.size() - 1)]

	end_cell = targeting.find_clear_endpoint_along_hex_line(unit, start_cell, end_cell)
	if end_cell == start_cell or not map_data.is_valid_cell(end_cell) or not targeting.is_unit_cell_clear(unit, end_cell, true):
		return result

	unit.set_hex_cell(end_cell, map_data)
	result["success"] = true
	result["end_cell"] = end_cell
	_notify_opponents_movement_completed(unit)
	unit.notify_movement_completed({
		"controller": self,
		"start_cell": start_cell,
		"end_cell": end_cell,
		"distance": BattleHexGrid.distance(start_cell, end_cell),
		"forced": false,
		"card_movement": true,
	})
	_emit_log("%s 移动到格 (%d, %d)。" % [unit.get_display_name(), unit.cell.x, unit.cell.y])
	state_changed.emit()
	return result


func get_units_by_filter(source: BattleUnitState, filter: int) -> Array[BattleUnitState]:
	return targeting.get_units_by_filter(source, filter)


func get_units_along_hex_line(source: BattleUnitState, start_cell: Vector2i, end_cell: Vector2i, filter: int) -> Array[BattleUnitState]:
	return targeting.get_units_along_hex_line(source, start_cell, end_cell, filter)


func get_units_in_range(source: BattleUnitState, range_distance: int, filter: int) -> Array[BattleUnitState]:
	return targeting.get_units_in_range(source, range_distance, filter)


func get_units_in_attack_range(source: BattleUnitState, range_bonus: int = 0, filter: int = UnitFilter.OPPONENTS, equipment_slot: String = "") -> Array[BattleUnitState]:
	return targeting.get_units_in_attack_range(source, range_bonus, filter, equipment_slot)


func switch_equipment_from_inventory(unit: BattleUnitState, preferred_equipment: EquipmentData = null) -> Dictionary:
	var result := {"success": false}
	if unit == null or unit.character_state == null:
		return result

	var before_context := {
		"controller": self,
		"unit": unit,
		"preferred_equipment": preferred_equipment,
	}
	var preview := CharacterEquipmentModel.preview_equipment_switch(unit.character_state, preferred_equipment)
	if not bool(preview.get("success", false)):
		_emit_log("%s 没有可切换的背包装备。" % unit.get_display_name())
		return result
	var preview_old := preview.get("old_equipment") as EquipmentData
	var incoming_equipment := preview.get("equipment") as EquipmentData
	return _resolve_equipment_switch(
		unit,
		preview_old,
		int(preview.get("old_face", 0)),
		before_context,
		func() -> Dictionary:
			return unit.character_state.switch_equipment_from_inventory(preferred_equipment),
		"%s 没有可切换的背包装备。" % unit.get_display_name(),
		"%s 切换装备：%s 装备到%s。" % [
			unit.get_display_name(),
			incoming_equipment.item_name,
			_equipment_slot_label(str(preview.get("slot", ""))),
		]
	)


func can_switch_prepared_weapon(unit: BattleUnitState) -> bool:
	return unit != null \
		and unit.character_state != null \
		and unit.get_character_class() == CardEnums.CardClass.WARRIOR \
		and unit.character_state.reserve_weapon_equipment != null


func switch_prepared_weapon(unit: BattleUnitState) -> Dictionary:
	var result := {
		"success": false,
		"controller": self,
		"unit": unit,
		"slot": CharacterEquipmentModel.SLOT_WEAPON,
	}
	if not can_switch_prepared_weapon(unit):
		if unit != null and unit.character_state != null \
				and unit.get_character_class() == CardEnums.CardClass.WARRIOR:
			_emit_log("%s 的备战武器槽为空。" % unit.get_display_name())
		return result

	var before_context := {
		"controller": self,
		"unit": unit,
	}
	var old_equipment := unit.character_state.weapon_equipment
	var old_face := unit.character_state.weapon_face
	var incoming_equipment := unit.character_state.reserve_weapon_equipment
	return _resolve_equipment_switch(
		unit,
		old_equipment,
		old_face,
		before_context,
		func() -> Dictionary:
			return CharacterEquipmentModel.swap_active_and_reserve_weapons(unit.character_state),
		"%s 的备战武器切换失败。" % unit.get_display_name(),
		"%s 切换备战武器：%s 成为当前武器。" % [
			unit.get_display_name(),
			incoming_equipment.item_name,
		]
	)


func _resolve_equipment_switch(
	unit: BattleUnitState,
	old_equipment: EquipmentData,
	old_face: int,
	before_context: Dictionary,
	apply_switch: Callable,
	failure_message: String,
	success_message: String
) -> Dictionary:
	_emit_equipment_switch_started(before_context)
	if old_equipment != null:
		unit.notify_equipment_before_switch_out(old_equipment, old_face, before_context)

	var result: Dictionary = apply_switch.call()
	result["controller"] = self
	result["unit"] = unit
	if not bool(result.get("success", false)):
		_emit_log(failure_message)
		return result

	old_equipment = result.get("old_equipment") as EquipmentData
	var new_equipment := result.get("new_equipment") as EquipmentData
	var switch_context := {
		"controller": self,
		"switch_result": result,
		"action_id": get_current_action_id(),
	}
	if old_equipment != null:
		unit.notify_equipment_switched_out(old_equipment, int(result.get("old_face", 0)), switch_context)
	if new_equipment != null:
		unit.notify_equipment_switched_in(new_equipment, int(result.get("new_face", 0)), switch_context)
	if old_equipment != null:
		enqueue_trigger(Callable(self, "_emit_equipment_switched_out"), [result], 0, "切换掉当前装备", result)
	if new_equipment != null:
		enqueue_trigger(Callable(self, "_emit_equipment_switched_in"), [result], 0, "切换出新的装备", result)
	unit.notify_equipment_switched(result, {
		"controller": self,
		"action_id": get_current_action_id(),
	})
	_emit_log(success_message)
	state_changed.emit()
	return result


func can_switch_weapon_from_inventory(unit: BattleUnitState) -> bool:
	# Legacy compatibility. Warrior gameplay code uses can_switch_prepared_weapon().
	if unit != null and unit.get_character_class() == CardEnums.CardClass.WARRIOR:
		return can_switch_prepared_weapon(unit)
	return _find_inventory_weapon(unit) != null


func switch_weapon_from_inventory(unit: BattleUnitState) -> Dictionary:
	# Legacy compatibility. Warrior gameplay code uses switch_prepared_weapon().
	if unit != null and unit.get_character_class() == CardEnums.CardClass.WARRIOR:
		return switch_prepared_weapon(unit)
	var weapon := _find_inventory_weapon(unit)
	if weapon == null:
		var result := {"success": false, "controller": self, "unit": unit, "slot": "weapon"}
		if unit != null:
			_emit_log("%s 没有可切换的背包武器。" % unit.get_display_name())
		return result
	return switch_equipment_from_inventory(unit, weapon)


func _find_inventory_weapon(unit: BattleUnitState) -> EquipmentData:
	if unit == null or unit.character_state == null:
		return null
	for stack in unit.character_state.inventory:
		if stack == null or stack.count <= 0 or not (stack.item_data is EquipmentData):
			continue
		var equipment := stack.item_data as EquipmentData
		if equipment.is_weapon():
			return equipment
	return null


func can_activate_equipment_action(unit: BattleUnitState, effect: EquipmentEffect, action_id: String = "default") -> bool:
	var deployment_action := phase == Phase.DEPLOYMENT
	if deployment_action and (unit == null or not player_units.has(unit)):
		return false
	if not deployment_action and (phase != Phase.BATTLE or turn_flow_state != TurnFlowState.ACTIVE or unit == null or current_unit != unit):
		return false
	if unit == null or is_resolving_actions() or resolution_state_notification_active or not unit.is_equipment_action_active(effect):
		return false
	var context := {"controller": self, "unit": unit, "phase": "deployment" if deployment_action else "battle"}
	for action in unit.get_equipment_actions(context):
		if action.get("effect") != effect or str(action.get("action_id", "default")) != action_id:
			continue
		var cost := int(action.get("momentum_cost", 0))
		return bool(action.get("enabled", false)) and unit.get_class_resource_value(WARRIOR_MOMENTUM_RESOURCE) >= cost
	return false


func activate_equipment_action(unit: BattleUnitState, effect: EquipmentEffect, action_id: String = "default") -> bool:
	if not can_activate_equipment_action(unit, effect, action_id):
		return false
	if phase == Phase.DEPLOYMENT:
		_resolve_equipment_action(unit, effect, action_id, true)
		return true
	return push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_equipment_action"),
		[unit, effect, action_id, false],
		0,
		"%s 使用武器行动" % unit.get_display_name(),
		{"unit": unit, "equipment_effect": effect}
	))


func _resolve_equipment_action(unit: BattleUnitState, effect: EquipmentEffect, action_id: String = "default", deployment_action: bool = false) -> void:
	if unit == null or effect == null or not unit.is_equipment_action_active(effect):
		return
	var context := {
		"controller": self,
		"unit": unit,
		"action_id": get_current_action_id(),
		"equipment_action_id": action_id,
		"phase": "deployment" if deployment_action else "battle",
	}
	for action in unit.get_equipment_actions(context):
		if action.get("effect") != effect or str(action.get("action_id", "default")) != action_id:
			continue
		var cost := int(action.get("momentum_cost", 0))
		if not bool(action.get("enabled", false)):
			return
		if cost > 0 and not unit.consume_class_resource(WARRIOR_MOMENTUM_RESOURCE, cost):
			return
		if effect.activate(unit, action.get("root") as EquipmentData, action.get("component") as EquipmentData, action.get("runtime") as EquipmentRuntimeState, context):
			if not deployment_action:
				_close_ranger_combo_window(unit)
			_emit_log("%s 使用 %s。" % [unit.get_display_name(), str(action.get("label", "武器行动"))])
			state_changed.emit()
		return

func can_use_druid_prepare_transform(unit: BattleUnitState) -> bool:
	if phase != Phase.BATTLE or turn_flow_state != TurnFlowState.ACTIVE or unit == null or current_unit != unit:
		return false
	if unit.faction != BattleUnitState.Faction.PLAYER:
		return false
	if not unit.is_druid() or unit.druid_transformed or unit.druid_prepare_used:
		return false
	if unit.hand.is_empty() and not unit.can_replace_druid_form_change(true, {"controller": self, "reason": "druid_prepare_transform"}):
		return false

	return true


func use_druid_prepare_transform(unit: BattleUnitState, selected_card: CardData = null) -> bool:
	if is_resolving_actions() or resolution_state_notification_active:
		return false
	if not can_use_druid_prepare_transform(unit):
		return false
	if selected_card != null and not unit.has_card_in_hand(selected_card):
		_emit_log("%s 不在手牌中，无法逆置置入法力区。" % selected_card.card_name)
		return false

	return push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_druid_prepare_transform"),
		[unit, selected_card],
		0,
		"%s 准备变身" % unit.get_display_name(),
		{"unit": unit, "selected_card": selected_card}
	))


func _resolve_druid_prepare_transform(unit: BattleUnitState, selected_card: CardData = null) -> void:
	if not can_use_druid_prepare_transform(unit):
		return

	var form_context := {
		"controller": self,
		"reason": "druid_prepare_transform",
		"source": unit,
		"consume_prepare": true,
	}
	var replacement := unit.try_replace_druid_form_change(true, form_context)
	if bool(replacement.get("handled", false)):
		unit.druid_prepare_used = true
		_emit_log(str(replacement.get("log", "%s 的变身被武器效果替代。" % unit.get_display_name())))
		state_changed.emit()
		return

	var card := selected_card
	if card == null and not unit.hand.is_empty():
		card = unit.hand[0] as CardData
	if card != null and not unit.has_card_in_hand(card):
		_emit_log("%s 不在手牌中，无法逆置置入法力区。" % card.card_name)
		return
	if card == null or not unit.move_hand_card_to_mana(card, {
		"controller": self,
		"reason": "druid_prepare_transform",
		"source": unit,
		"source_card": card,
	}):
		return
	unit.set_druid_transformed(true, form_context)
	unit.druid_prepare_used = true
	_emit_log("%s 将 %s 逆置置入法力区，并进入变身状态。" % [unit.get_display_name(), card.card_name])
	state_changed.emit()


func can_use_druid_prepare_untransform(unit: BattleUnitState) -> bool:
	if phase != Phase.BATTLE or turn_flow_state != TurnFlowState.ACTIVE or unit == null or current_unit != unit:
		return false
	if unit.faction != BattleUnitState.Faction.PLAYER:
		return false
	if not unit.is_druid() or not unit.druid_transformed or unit.druid_prepare_used:
		return false
	if not unit.can_pay_mana(1):
		return false

	return true


func use_druid_prepare_untransform(unit: BattleUnitState) -> bool:
	if is_resolving_actions() or resolution_state_notification_active:
		return false
	if not can_use_druid_prepare_untransform(unit):
		return false

	return push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_druid_prepare_untransform"),
		[unit],
		0,
		"%s 解除变身" % unit.get_display_name(),
		{"unit": unit}
	))


func _resolve_druid_prepare_untransform(unit: BattleUnitState) -> void:
	if not can_use_druid_prepare_untransform(unit):
		return
	if not unit.pay_mana(1):
		return

	unit.set_druid_transformed(false, {"controller": self, "reason": "druid_prepare_restore", "source": unit})
	unit.druid_prepare_used = true
	_emit_log("%s 支付 1 点法力，解除变身状态。" % unit.get_display_name())
	state_changed.emit()


func request_druid_form_change(unit: BattleUnitState, transformed: bool, context: Dictionary = {}) -> Dictionary:
	if unit == null or not unit.is_druid() or unit.druid_transformed == transformed:
		return {"success": false, "changed": false}
	var merged := context.merged({"controller": self, "source": context.get("source", unit)})
	unit.notify_druid_form_change_requested(transformed, merged)
	var replacement := unit.try_replace_druid_form_change(transformed, merged)
	if bool(replacement.get("handled", false)):
		return {"success": bool(replacement.get("success", true)), "changed": false, "replaced": true}
	unit.set_druid_transformed(transformed, merged)
	return {"success": true, "changed": true, "replaced": false}


func should_card_enter_mana_after_play(frame: BattleCardFrame) -> bool:
	if frame == null or frame.user == null or frame.card == null:
		return false
	if not frame.user.is_druid() or not frame.card.is_druid_dual_card:
		return false
	if frame.context != null and bool(frame.context.extra.get("druid_send_to_mana_after_play", false)):
		return frame.user.should_druid_card_enter_mana_after_play(frame.card, true, {"controller": self, "card_context": frame.context})
	if frame.context != null:
		var orientation := int(frame.context.extra.get("druid_orientation", _get_druid_orientation_for_card(frame.user, frame.card)))
		return frame.user.should_druid_card_enter_mana_after_play(frame.card, orientation == CardEnums.DruidOrientation.INVERTED, {"controller": self, "card_context": frame.context})

	return frame.user.should_druid_card_enter_mana_after_play(frame.card, frame.user.get_druid_card_orientation(frame.card) == CardEnums.DruidOrientation.INVERTED, {"controller": self})


func should_card_exile_after_play(frame: BattleCardFrame) -> bool:
	return frame != null and frame.user != null and frame.card != null and frame.user.should_exile_card_after_play(frame.card)


func finish_card_to_exile(frame: BattleCardFrame) -> void:
	if frame == null or frame.user == null or frame.card == null:
		return
	if frame.user.move_card_to_exile(frame.card):
		_emit_log("%s 打出的临时牌 %s 进入放逐区。" % [frame.user.get_display_name(), frame.card.card_name])


func finish_druid_card_to_mana(frame: BattleCardFrame) -> void:
	if frame == null or frame.user == null or frame.card == null:
		return
	var context := {
		"controller": self,
		"reason": "druid_inverted_card_played",
		"source": frame.user,
		"source_card": frame.card,
		"card_context": frame.context,
	}
	if frame.context != null:
		context["druid_orientation"] = int(frame.context.extra.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT))
	if not frame.user.move_hand_card_to_mana(frame.card, context):
		frame.user.add_card_to_mana_zone(frame.card, context)
	_emit_log("%s 逆位打出的 %s 进入法力区。" % [frame.user.get_display_name(), frame.card.card_name])


func mark_played_card_to_mana(context: Dictionary = {}) -> void:
	var card_context: CardPlayContext = context.get("card_context") as CardPlayContext
	if card_context != null:
		card_context.extra["druid_send_to_mana_after_play"] = true


func _get_druid_orientation_for_card(user: BattleUnitState, card: CardData) -> int:
	if user != null and user.has_method("get_druid_card_orientation"):
		return int(user.get_druid_card_orientation(card))

	return CardEnums.DruidOrientation.UPRIGHT


func _is_druid_card_play_state_valid(user: BattleUnitState, card: CardData, write_log: bool) -> bool:
	if user == null or card == null or not card.is_druid_dual_card:
		return true
	if not user.is_druid():
		return true

	var orientation := _get_druid_orientation_for_card(user, card)
	if orientation == CardEnums.DruidOrientation.INVERTED:
		if card.is_twin_spell:
			if write_log:
				_emit_log("%s 是双生法术，不能以逆位打出。" % card.card_name)
			return false
		if not card.allow_inverted_play:
			if write_log:
				_emit_log("%s 当前不能逆位打出。" % card.card_name)
			return false
	else:
		if not card.allow_upright_play:
			if write_log:
				_emit_log("%s 当前不能正位打出。" % card.card_name)
			return false

	return true


func _try_pay_druid_resonance(user: BattleUnitState, card: CardData, context: CardPlayContext) -> bool:
	if user == null or card == null or context == null:
		return true
	if not user.is_druid():
		return true
	var resonance_cost := user.get_card_resonance_cost(card, {"controller": self, "card": card})
	if resonance_cost <= 0 or not card.auto_pay_resonance:
		return true
	if not user.can_pay_mana(resonance_cost):
		context.extra["druid_resonance_paid"] = false
		return true
	if not user.pay_mana(resonance_cost, {"controller": self, "card": card, "reason": "resonance"}):
		_emit_log("%s 共鸣支付失败。" % card.card_name)
		return false

	context.extra["druid_resonance_paid"] = true
	_emit_log("%s 支付 %d 点法力触发共鸣。" % [user.get_display_name(), resonance_cost])
	return true


func gain_class_resource(unit: BattleUnitState, resource_name: String, amount: int) -> void:
	if unit == null or resource_name.is_empty() or amount <= 0:
		return

	var gained := unit.gain_class_resource(resource_name, amount)
	if gained > 0:
		_emit_log("%s 获得 %d 点%s。" % [unit.get_display_name(), gained, resource_name])
	state_changed.emit()


func enter_ranger_stealth(unit: BattleUnitState, label: String = "潜行") -> bool:
	if unit == null or not unit.enter_stealth():
		return false
	_emit_log("%s 进入%s。" % [unit.get_display_name(), label])
	state_changed.emit()
	return true


func consume_ranger_stealth_for_attack(unit: BattleUnitState, override_multiplier: float = 0.0, context: Dictionary = {}) -> float:
	if unit == null or not unit.is_stealthed():
		return 1.0
	unit.leave_stealth()
	var multiplier := unit.modify_ranger_ambush_multiplier(1.5, context)
	if override_multiplier > 0.0:
		multiplier = maxf(multiplier, override_multiplier)
	_emit_log("%s 主动破隐，本次完整攻击伤害 x%.1f。" % [unit.get_display_name(), multiplier])
	state_changed.emit()
	return multiplier


func should_cancel_hostile_effect(source: BattleUnitState, target: BattleUnitState, effect_kind: String = "效果", source_card: CardData = null) -> bool:
	if source == null or target == null or source.faction == target.faction:
		return false
	if source_card != null and target.should_counter_hostile_card(source, source_card, {"controller": self, "source": source, "card": source_card}):
		if target.consume_empty_eye_counter_flag():
			_emit_log("%s 的空目反制了%s。" % [target.get_display_name(), effect_kind])
			var backlash := _get_card_attribute_value(source, source_card) + source.get_damage_bonus({
				"controller": self,
				"card": source_card,
				"damage_type": source_card.damage_type,
				"distortion_field": "empty_eye",
			})
			enqueue_effect(
				Callable(self, "apply_damage"),
				[source, target, maxi(0, backlash), "空目反噬", {
					"source_card": source_card,
					"distortion_field": "empty_eye",
				}],
				-10,
				"空目反噬"
			)
		else:
			_emit_log("%s 的守成之果反制了%s。" % [target.get_display_name(), effect_kind])
		state_changed.emit()
		return true
	if not target.is_ranger():
		return false
	var action_id := get_current_action_id()
	var key := "%d:%d" % [action_id, target.unit_id]
	if action_id > 0 and stealth_cancelled_actions.has(key):
		return true
	if not target.is_stealthed():
		return false
	target.leave_stealth()
	if action_id > 0:
		stealth_cancelled_actions[key] = true
	target.notify_ranger_stealth_cancelled({
		"controller": self,
		"source": source,
		"effect_kind": effect_kind,
		"action_id": action_id,
	})
	_emit_log("%s 的潜行抵消了来自 %s 的整次%s。" % [target.get_display_name(), source.get_display_name(), effect_kind])
	state_changed.emit()
	return true


func _get_card_attribute_value(source: BattleUnitState, card: CardData) -> int:
	if source == null or card == null:
		return 0
	match card.damage_type:
		CardEnums.DamageType.STRENGTH:
			return source.get_strength()
		CardEnums.DamageType.AGILITY:
			return source.get_agility()
		CardEnums.DamageType.INTELLIGENCE:
			return source.get_intelligence()
		_:
			var profile := source.build_strike_profile_object()
			return profile.primary_base_damage


func is_unit_concealed(unit: BattleUnitState) -> bool:
	return unit != null and (unit.is_stealthed() or surface_state.is_concealing(unit.cell))


func gain_ranger_combo(unit: BattleUnitState, amount: int, context: Dictionary = {}) -> int:
	if unit == null or not unit.is_ranger() or amount <= 0:
		return 0
	var current: int = unit.ranger_state.combo_points
	for _point in range(amount):
		current += 1
		if current == 2 or current == 4 or current == 6 or current == 8:
			_queue_ranger_combo_reward(unit, current)
			unit.notify_ranger_combo_milestone(current, context.merged({"controller": self}))
		elif current >= 10:
			_queue_ranger_combo_reward(unit, 10)
			unit.notify_ranger_combo_milestone(10, context.merged({"controller": self}))
			current -= 10
	unit.ranger_state.combo_points = current
	_emit_log("%s 获得 %d 点连击，当前为 %d。" % [unit.get_display_name(), amount, current])
	state_changed.emit()
	return amount


func _close_ranger_combo_window(unit: BattleUnitState) -> void:
	if unit != null and unit.is_ranger():
		unit.ranger_state.combo_window_open = false


func collect_surface_elements(unit: BattleUnitState, cell: Vector2i, label: String = "采集", context: Dictionary = {}) -> int:
	if unit == null or not unit.is_ranger():
		return 0
	var collector_id := "unit:%d" % unit.unit_id
	var entries: Array[Dictionary] = surface_state.get_collectible_entries(cell, collector_id)
	var components: Array[int] = []
	for entry in entries:
		if entry.has("components"):
			for component_value in entry.get("components", []) as Array:
				var component := int(component_value)
				if BattleSurfaceState.BASE_ELEMENTS.has(component) and not components.has(component):
					components.append(component)
		else:
			var element := int(entry.get("element", BattleSurfaceState.Element.NONE))
			if BattleSurfaceState.BASE_ELEMENTS.has(element) and not components.has(element):
				components.append(element)
	components.sort_custom(func(left: int, right: int) -> bool:
		return BattleSurfaceState.BASE_ELEMENTS.find(left) < BattleSurfaceState.BASE_ELEMENTS.find(right)
	)
	var added := 0
	var successful_elements: Array[int] = []
	for element in components:
		var collection_context := context.merged({
			"controller": self,
			"cell": cell,
			"element": element,
			"label": label,
		})
		var amount := unit.modify_ranger_element_collection(1, collection_context)
		var actual_added := unit.collect_ranger_element(element, amount)
		added += actual_added
		if actual_added > 0:
			successful_elements.append(element)
	surface_state.commit_collection(cell, collector_id, entries, successful_elements)
	if added > 0:
		unit.notify_ranger_elements_collected(added, context.merged({"controller": self, "cell": cell, "label": label}))
		_emit_log("%s 从%s格采集 %d 枚元素。" % [unit.get_display_name(), label, added])
		state_changed.emit()
	return added


func prepare_ranger_blend(unit: BattleUnitState, blend: int, equipment_slot: String, catalyst: int = BattleSurfaceState.Element.NONE) -> bool:
	if phase != Phase.BATTLE or turn_flow_state != TurnFlowState.ACTIVE or is_resolving_actions():
		return false
	if unit == null or unit != current_unit or not unit.is_ranger() or not unit.is_stealthed():
		return false
	if unit.ranger_state.prepared_blend != BattleSurfaceState.Element.NONE:
		return false
	var ingredients: Array[int] = surface_state.get_component_elements(blend)
	if ingredients.size() != 2:
		return false
	if catalyst != BattleSurfaceState.Element.NONE:
		ingredients.append(catalyst)
	if not unit.ranger_state.pay_elements(ingredients):
		return false
	unit.sync_ranger_element_inventory()
	unit.ranger_state.prepared_blend = blend
	unit.ranger_state.prepared_weapon_slot = equipment_slot
	_close_ranger_combo_window(unit)
	_emit_log("%s 调配%s，并装填至%s。" % [unit.get_display_name(), BattleSurfaceState.label(blend), equipment_slot])
	state_changed.emit()
	return true


func resolve_ranger_after_strike(context: Dictionary) -> void:
	var attacker: BattleUnitState = context.get("attacker") as BattleUnitState
	var target: BattleUnitState = context.get("target") as BattleUnitState
	var profile: StrikeProfile = context.get("strike_profile_object") as StrikeProfile
	if attacker == null or target == null or profile == null or not attacker.is_ranger():
		return
	var actual_damage := int(context.get("actual_damage", 0))
	var is_melee := profile.primary_range_type == EquipmentData.WeaponRangeType.MELEE
	if is_melee and actual_damage > 0:
		collect_surface_elements(attacker, target.cell, "目标", {"from_melee_strike": true, "strike_context": context})
	var state: RangerCombatState = attacker.ranger_state
	var payloads: Array[Dictionary] = []
	var preloaded := attacker.consume_equipment_preloaded_payload(context)
	if preloaded != BattleSurfaceState.Element.NONE:
		payloads.append({"blend": preloaded, "source": "preloaded"})
	if state.prepared_blend != BattleSurfaceState.Element.NONE and state.prepared_weapon_slot == profile.primary_slot:
		payloads.append({"blend": state.prepared_blend, "source": "prepared"})
		state.prepared_blend = BattleSurfaceState.Element.NONE
		state.prepared_weapon_slot = ""
	for index in range(payloads.size()):
		var payload: Dictionary = payloads[index]
		var blend := int(payload.get("blend", BattleSurfaceState.Element.NONE))
		_apply_ranger_blend_payload(attacker, target, blend, is_melee)
		attacker.notify_ranger_payload_completed({
			"controller": self,
			"target": target,
			"blend": blend,
			"ingredients": surface_state.get_component_elements(blend),
			"equipment_slot": profile.primary_slot,
			"is_melee": is_melee,
			"payload_source": payload.get("source", ""),
			"final_for_strike": index == payloads.size() - 1,
		})


func apply_base_surface_element(cell: Vector2i, element: int, source_context: Dictionary = {}) -> int:
	if map_data == null or not map_data.is_valid_cell(cell) or not BattleSurfaceState.BASE_ELEMENTS.has(element):
		return BattleSurfaceState.Element.NONE
	var battle_object := get_battle_object_at_cell(cell)
	if element == BattleSurfaceState.Element.FIRE and battle_object != null \
			and battle_object.definition.kind == BattleObjectDefinition.Kind.EXPLOSIVE_BARREL:
		apply_object_damage(
			source_context.get("source") as BattleUnitState,
			battle_object,
			battle_object.current_health,
			"\u70b9\u71c3",
			{"environmental": true, "source_cell": source_context.get("source_cell", cell)}
		)
	var result: Dictionary = surface_state.apply_base_element(cell, element, battle_round)
	var reactions: Array = result.get("reactions", []) as Array
	for reaction_value in reactions:
		var reaction_context := source_context.duplicate()
		reaction_context["source_element"] = element
		if not reaction_context.has("source_cell"):
			reaction_context["source_cell"] = current_unit.cell if current_unit != null else cell
		_resolve_surface_reaction(cell, int(reaction_value), reaction_context)
	state_changed.emit()
	return int(reactions.back()) if not reactions.is_empty() else element


func apply_advanced_surface(
	cell: Vector2i,
	element: int,
	source_context: Dictionary = {}
) -> bool:
	if map_data == null or not map_data.is_valid_cell(cell) \
			or not BattleSurfaceState.ADVANCED_ELEMENTS.has(element):
		return false
	surface_state.create_advanced_surface(cell, element, battle_round)
	var reaction_context := source_context.duplicate()
	if not reaction_context.has("source_cell"):
		reaction_context["source_cell"] = current_unit.cell if current_unit != null else cell
	_resolve_surface_reaction(cell, element, reaction_context)
	state_changed.emit()
	return true


func submit_mage_discard_conversion(unit: BattleUnitState, cards: Array[CardData], surface_choices: Array[int]) -> bool:
	if not _can_submit_turn_action(unit, "法师弃牌转化") or not unit.is_mage_adventurer() \
			or unit.mage_state.discard_conversion_used or cards.is_empty() or cards.size() != surface_choices.size():
		return false
	var unique_cards: Array[CardData] = []
	var locked_elements: Array = []
	var foot_elements := surface_state.get_readable_elements(unit.cell)
	for index in range(cards.size()):
		var card := cards[index]
		var surface_choice := surface_choices[index]
		if card == null or unique_cards.has(card) or not unit.hand.has(card):
			return false
		if (foot_elements.is_empty() and surface_choice != BattleSurfaceState.Element.NONE) \
				or (not foot_elements.is_empty() and not foot_elements.has(surface_choice)):
			return false
		unique_cards.append(card)
		locked_elements.append(unit.get_effective_card_elements(card).duplicate())
	return push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_mage_discard_conversion"),
		[unit, unique_cards, locked_elements, surface_choices.duplicate()],
		0,
		"%s 法师弃牌转化" % unit.get_display_name(),
		{"unit": unit, "phase": "mage_discard_conversion"}
	))


func _resolve_mage_discard_conversion(unit: BattleUnitState, cards: Array[CardData], locked_elements: Array, surface_choices: Array[int]) -> void:
	if not _is_turn_action_execution_valid(unit) or not unit.is_mage_adventurer() \
			or unit.mage_state.discard_conversion_used:
		return
	for card in cards:
		if card == null or not unit.hand.has(card):
			return
	unit.mage_state.discard_conversion_used = true
	var gains: Dictionary = {}
	for index in range(cards.size()):
		var card := cards[index]
		if not unit.discard_card(card, {
			"controller": self,
			"reason": "mage_discard_conversion",
			"source": unit,
		}):
			continue
		for element in locked_elements[index]:
			gains[element] = int(gains.get(element, 0)) + 1
		var surface_choice := surface_choices[index]
		if BattleSurfaceState.BASE_ELEMENTS.has(surface_choice):
			gains[surface_choice] = int(gains.get(surface_choice, 0)) + 1
	unit.mage_state.gain_mana_batch(gains)
	_emit_log("%s 将 %d 张手牌转化为法术力。" % [unit.get_display_name(), cards.size()])
	state_changed.emit()


func submit_mage_active_infusion(unit: BattleUnitState, equipment_slot: String, target_cell: Vector2i, element: int) -> bool:
	if not _can_submit_turn_action(unit, "法师主动灌注") or not _can_use_mage_active_infusion(
		unit,
		equipment_slot,
		target_cell,
		element
	):
		return false
	return push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_mage_active_infusion"),
		[unit, equipment_slot, target_cell, element],
		0,
		"%s 主动灌注" % unit.get_display_name(),
		{"unit": unit, "phase": "mage_active_infusion"}
	))


func _can_use_mage_active_infusion(unit: BattleUnitState, equipment_slot: String, target_cell: Vector2i, element: int) -> bool:
	if unit == null or not unit.is_mage_adventurer() or unit.mage_state.active_infusion_used \
			or not BattleSurfaceState.BASE_ELEMENTS.has(element) or not unit.mage_state.can_pay_mana(element):
		return false
	if map_data == null or not map_data.is_valid_cell(target_cell):
		return false
	var option_found := false
	for option_value in unit.get_attack_weapon_options():
		var option := option_value as Dictionary
		if str(option.get("slot", "")) == equipment_slot:
			option_found = true
			break
	if not option_found:
		return false
	var attack_range := get_effective_attack_range_at_cell(unit, target_cell, equipment_slot)
	return BattleHexGrid.distance(unit.cell, target_cell) <= attack_range


func _resolve_mage_active_infusion(unit: BattleUnitState, equipment_slot: String, target_cell: Vector2i, element: int) -> void:
	if not _is_turn_action_execution_valid(unit) or not _can_use_mage_active_infusion(
		unit,
		equipment_slot,
		target_cell,
		element
	):
		return
	if not unit.mage_state.pay_mana(element):
		return
	unit.mage_state.active_infusion_used = true
	place_mage_infusion(unit, target_cell, element)
	_emit_log("%s 在格 (%d, %d) 灌注%s。" % [
		unit.get_display_name(),
		target_cell.x,
		target_cell.y,
		BattleSurfaceState.label(element),
	])


func place_mage_infusion(source: BattleUnitState, cell: Vector2i, element: int) -> bool:
	if source == null or map_data == null or not map_data.is_valid_cell(cell) \
			or not BattleSurfaceState.BASE_ELEMENTS.has(element):
		return false
	var placed := mage_infusion_state.place_stone(source.faction, cell, element, active_turn_serial)
	apply_base_surface_element(cell, element)
	state_changed.emit()
	return placed


func reverse_mage_infusion(unit: BattleUnitState, cell: Vector2i, element: int) -> bool:
	if unit == null or not unit.is_mage_adventurer() \
			or not mage_infusion_state.remove_stone(unit.faction, cell, element):
		return false
	unit.mage_state.gain_mana(element, 1)
	state_changed.emit()
	return true


func can_use_mage_primordial(unit: BattleUnitState) -> bool:
	return unit != null and unit.is_alive() and current_unit == unit \
		and turn_flow_state == TurnFlowState.ACTIVE and not is_resolving_actions() \
		and mage_infusion_state.is_primordial_available(unit.faction, unit.cell, active_turn_serial)


func consume_mage_primordial(unit: BattleUnitState) -> bool:
	if not can_use_mage_primordial(unit) or not mage_infusion_state.consume_primordial(unit.faction, unit.cell):
		return false
	state_changed.emit()
	return true


func force_move_toward(unit: BattleUnitState, destination: Vector2i, max_steps: int, source: BattleUnitState = null) -> int:
	if unit == null or map_data == null or max_steps <= 0:
		return 0
	if should_cancel_hostile_effect(source, unit, "强制移动"):
		return 0
	var start_cell := unit.cell
	var path := map_data.get_line(unit.cell, destination)
	var moved := 0
	for index in range(1, mini(path.size(), max_steps + 1)):
		var next_cell: Vector2i = path[index]
		if not map_data.is_valid_cell(next_cell) or not targeting.is_unit_cell_clear(unit, next_cell, false):
			break
		unit.set_hex_cell(next_cell, map_data)
		moved += 1
		if process_surface_entry(unit, next_cell):
			break
	if moved > 0:
		_notify_opponents_movement_completed(unit)
		unit.notify_movement_completed({"controller": self, "start_cell": start_cell, "end_cell": unit.cell, "distance": moved, "forced": true})
		_emit_log("%s 被强制移动 %d 格。" % [unit.get_display_name(), moved])
		state_changed.emit()
	return moved


func force_move_away(unit: BattleUnitState, origin: Vector2i, max_steps: int, source: BattleUnitState = null) -> int:
	if unit == null or max_steps <= 0 or map_data == null:
		return 0
	var start_cell := unit.cell
	var moved := 0
	for _step in range(max_steps):
		var best := BattleHexGrid.INVALID_CELL
		var best_distance := map_data.get_distance(unit.cell, origin)
		for neighbor in BattleHexGrid.neighbors(unit.cell):
			if not map_data.is_valid_cell(neighbor) or not targeting.is_unit_cell_clear(unit, neighbor, false):
				continue
			var distance := map_data.get_distance(neighbor, origin)
			if distance > best_distance:
				best = neighbor
				best_distance = distance
		if best == BattleHexGrid.INVALID_CELL:
			break
		if should_cancel_hostile_effect(source, unit, "强制移动"):
			break
		unit.set_hex_cell(best, map_data)
		moved += 1
		if process_surface_entry(unit, best):
			break
	if moved > 0:
		_notify_opponents_movement_completed(unit)
		unit.notify_movement_completed({"controller": self, "start_cell": start_cell, "end_cell": unit.cell, "distance": moved, "forced": true})
		state_changed.emit()
	return moved


func _notify_opponents_movement_completed(moved_unit: BattleUnitState) -> void:
	if moved_unit == null:
		return
	for observer in get_opposing_units(moved_unit):
		observer.notify_enemy_movement_completed(moved_unit, {"controller": self, "source": moved_unit})


func _notify_opponents_card_completed(card_user: BattleUnitState, card: CardData) -> void:
	if card_user == null or card == null:
		return
	for observer in get_opposing_units(card_user):
		observer.notify_enemy_card_completed(card_user, card, {"controller": self, "source": card_user})


func _apply_ranger_blend_payload(attacker: BattleUnitState, target: BattleUnitState, blend: int, is_melee: bool) -> void:
	var target_valid := target != null and target.is_alive()
	match blend:
		BattleSurfaceState.Element.STEAM:
			if is_melee:
				enter_ranger_stealth(attacker, "雾隐回身")
			elif target_valid:
				force_move_away(target, attacker.cell, 1, attacker)
		BattleSurfaceState.Element.LAVA:
			if is_melee:
				if target_valid:
					_apply_burn(target, 2, 2)
			else:
				if target_valid:
					_apply_burn(target, 1, 2)
					for other in get_units_in_range(target, 1, UnitFilter.ALL):
						if other.faction != attacker.faction:
							_apply_burn(other, 1, 2)
		BattleSurfaceState.Element.BLAZE:
			if is_melee:
				gain_ranger_combo(attacker, 2)
			elif target_valid:
				var breach := BreachStatus.new()
				breach.applied_by = attacker
				breach.expires_on_source_turn = attacker.turn_serial + 1
				target.remove_status("breach")
				target.add_status(breach)
		BattleSurfaceState.Element.POISON_BOG:
			if not target_valid:
				return
			var gain_status := RangerGainMultiplierStatus.new()
			gain_status.status_id = "ranger_bad_blood" if is_melee else "ranger_corrosion"
			gain_status.display_name = "坏血" if is_melee else "蚀甲"
			gain_status.gain_kind = RangerGainMultiplierStatus.GainKind.HEALING if is_melee else RangerGainMultiplierStatus.GainKind.ARMOR
			target.remove_status(gain_status.status_id)
			target.add_status(gain_status)
		BattleSurfaceState.Element.ICE:
			if is_melee:
				var discount := NextMoveApDiscountStatus.new()
				discount.discount_amount = 1
				attacker.add_status(discount)
			elif target_valid:
				var surcharge := RangerMoveSurchargeStatus.new()
				target.remove_status(surcharge.status_id)
				target.add_status(surcharge)
		BattleSurfaceState.Element.SANDSTORM:
			if is_melee:
				attacker.gain_armor(3, {"controller": self, "reason": "ranger_stone_skin"})
			elif target_valid:
				var blind := RangerBlindStatus.new()
				target.remove_status(blind.status_id)
				target.add_status(blind)


func _apply_burn(target: BattleUnitState, damage: int, turns: int) -> void:
	if target == null:
		return
	var burn := RangerBurnStatus.new()
	burn.damage_per_turn = damage
	burn.remaining_turns = turns
	target.remove_status(burn.status_id)
	target.add_status(burn)


func get_surface_damage_bonus(unit: BattleUnitState) -> int:
	if unit == null:
		return 0
	return surface_state.get_damage_bonus(unit.cell)


func get_surface_damage_reduction(unit: BattleUnitState, context: Dictionary = {}) -> int:
	if unit == null:
		return 0
	var damage_context: DamageContext = context.get("damage_context") as DamageContext
	var is_ranged := damage_context != null \
		and not bool(damage_context.metadata.get("ignore_ranged_surface_reduction", false)) \
		and int(damage_context.metadata.get("range_type", -1)) == EquipmentData.WeaponRangeType.RANGED
	return surface_state.get_damage_reduction(unit.cell, is_ranged)


func modify_attack_range_for_surface(unit: BattleUnitState, base_range: int, equipment_slot: String = "") -> int:
	return base_range


func get_effective_attack_range_against(attacker: BattleUnitState, target: BattleUnitState, equipment_slot: String = "") -> int:
	if attacker == null:
		return 0
	if target == null:
		return attacker.get_attack_range(equipment_slot, {"controller": self})
	return get_effective_attack_range_at_cell(attacker, target.cell, equipment_slot, target)


func get_effective_attack_range_at_cell(attacker: BattleUnitState, target_cell: Vector2i, equipment_slot: String = "", target: BattleUnitState = null) -> int:
	if attacker == null:
		return 0
	var attack_range := attacker.get_attack_range(equipment_slot, {
		"controller": self,
		"target": target,
		"target_cell": target_cell,
	})
	var profile := attacker.build_strike_profile_object(equipment_slot)
	if profile.primary_range_type == EquipmentData.WeaponRangeType.RANGED:
		if surface_state.is_ranged_range_capped(attacker.cell) \
				or surface_state.is_ranged_range_capped(target_cell):
			attack_range = mini(attack_range, 2)
	return attack_range


func process_surface_entry(unit: BattleUnitState, cell: Vector2i) -> bool:
	if unit == null or not unit.is_alive():
		return false
	if unit.is_flying():
		return false
	if surface_state.is_terrain_effective(cell, BattleSurfaceState.Terrain.MAGMA_FISSURE):
		apply_environment_damage(unit, 3, "\u5ca9\u6d46\u88c2\u9699")
	if surface_state.get_ground_effect(cell) == BattleSurfaceState.Element.LAVA:
		apply_environment_damage(unit, 3, "\u7194\u5ca9")
	return surface_state.stops_movement_on_entry(cell)


func _apply_surface_turn_start(unit: BattleUnitState) -> void:
	if unit == null or not unit.is_alive():
		return
	if unit.is_flying():
		return
	if surface_state.is_terrain_effective(unit.cell, BattleSurfaceState.Terrain.MAGMA_FISSURE):
		apply_environment_damage(unit, 3, "\u5ca9\u6d46\u88c2\u9699")
	if surface_state.get_ground_effect(unit.cell) == BattleSurfaceState.Element.LAVA:
		apply_environment_damage(unit, 3, "\u7194\u5ca9")


func _resolve_surface_reaction(cell: Vector2i, reaction: int, context: Dictionary) -> void:
	var unit := get_unit_at_cell(cell)
	var battle_object := get_battle_object_at_cell(cell)
	match reaction:
		BattleSurfaceState.Element.STEAM:
			if unit != null and not unit.is_flying():
				force_move_away(
					unit,
					context.get("source_cell", cell) as Vector2i,
					1,
					context.get("source") as BattleUnitState
				)
		BattleSurfaceState.Element.LAVA:
			if unit != null and not unit.is_flying():
				apply_environment_damage(unit, 3, "\u7194\u5ca9\u751f\u6210")
			if battle_object != null:
				apply_object_damage(null, battle_object, 3, "\u7194\u5ca9\u751f\u6210", {"environmental": true})
		BattleSurfaceState.Element.BLAZE:
			if unit != null and not unit.is_flying():
				apply_environment_damage(unit, 2, "\u70c8\u7130\u751f\u6210")
			if battle_object != null:
				apply_object_damage(null, battle_object, 2, "\u70c8\u7130\u751f\u6210", {"environmental": true})
		BattleSurfaceState.Element.ICE:
			if unit != null and not unit.is_flying():
				var surcharge := RangerMoveSurchargeStatus.new()
				surcharge.stacks = 1
				surcharge.surcharge = 1
				unit.remove_status(surcharge.status_id)
				unit.add_status(surcharge)
		BattleSurfaceState.Element.SANDSTORM:
			if unit != null and not unit.is_flying():
				var blind := RangerBlindStatus.new()
				blind.stacks = 1
				blind.maximum_range = 2
				blind.remaining_turn_ends = 1
				unit.remove_status(blind.status_id)
				unit.add_status(blind)


func apply_environment_damage(
	target: BattleUnitState,
	amount: int,
	label: String,
	metadata: Dictionary = {}
) -> int:
	var environment_metadata := metadata.duplicate()
	environment_metadata["environmental"] = true
	environment_metadata["fixed_damage"] = true
	return apply_damage(null, target, amount, label, environment_metadata)


func apply_object_damage(
	source: BattleUnitState,
	target: BattleObjectState,
	amount: int,
	label: String = "\u4f24\u5bb3",
	metadata: Dictionary = {}
) -> int:
	if target == null or not target.can_be_damaged() or amount <= 0:
		return 0
	var before := target.current_health
	target.current_health = maxi(0, target.current_health - amount)
	var actual := before - target.current_health
	if actual <= 0:
		return 0
	var source_name := source.get_display_name() if source != null else "\u73af\u5883"
	_emit_log("%s \u5bf9 %s \u9020\u6210 %d \u70b9%s\u3002" % [
		source_name,
		target.get_display_name(),
		actual,
		label,
	])
	if target.current_health <= 0 and not target.destruction_queued:
		target.destruction_queued = true
		target.destroyed = true
		if target.definition.persistent_element != BattleSurfaceState.Element.NONE:
			surface_state.remove_persistent_source(target.cell, "object:%d" % target.object_id)
		var source_cell: Vector2i = metadata.get(
			"source_cell",
			source.cell if source != null else target.cell
		)
		var action_id := get_current_action_id()
		if action_id <= 0:
			action_id = -target.object_id - 1
		enqueue_effect(
			Callable(self, "_resolve_battle_object_destruction"),
			[target, source_cell, action_id],
			-30,
			"%s \u9500\u6bc1" % target.get_display_name()
		)
		if get_current_action_id() <= 0:
			resolve_effect_queue()
	state_changed.emit()
	return actual


func _resolve_battle_object_destruction(
	target: BattleObjectState,
	source_cell: Vector2i,
	action_id: int
) -> void:
	if target == null or not target.destruction_queued or not target.mark_triggered(action_id):
		return
	target.destruction_queued = false
	_emit_log("%s \u88ab\u6467\u6bc1\u3002" % target.get_display_name())
	match target.definition.kind:
		BattleObjectDefinition.Kind.EXPLOSIVE_BARREL:
			_resolve_explosive_barrel(target.cell, action_id)
		BattleObjectDefinition.Kind.WATER_CISTERN:
			_apply_element_to_area(target.cell, 1, BattleSurfaceState.Element.WATER, action_id)
		BattleObjectDefinition.Kind.WIND_TOTEM:
			_resolve_wind_totem(target.cell, action_id)
		BattleObjectDefinition.Kind.UNSTABLE_PILLAR:
			_resolve_falling_pillar(target, source_cell, action_id)
	state_changed.emit()


func _resolve_explosive_barrel(origin: Vector2i, action_id: int) -> void:
	var cells: Array[Vector2i] = map_data.get_cells_in_range(origin, 1)
	_sort_cells_stably(cells)
	for cell in cells:
		var unit := get_unit_at_cell(cell)
		if unit != null:
			apply_environment_damage(unit, 4, "\u7206\u70b8")
		var battle_object := get_battle_object_at_cell(cell)
		if battle_object != null:
			apply_object_damage(null, battle_object, 4, "\u7206\u70b8", {
				"environmental": true,
				"source_cell": origin,
				"action_id": action_id,
			})
		apply_base_surface_element(cell, BattleSurfaceState.Element.FIRE, {
			"source_cell": origin,
			"action_id": action_id,
		})


func _resolve_wind_totem(origin: Vector2i, action_id: int) -> void:
	var cells: Array[Vector2i] = map_data.get_cells_in_range(origin, 1)
	_sort_cells_stably(cells)
	for cell in cells:
		if cell != origin:
			var unit := get_unit_at_cell(cell)
			if unit != null:
				force_move_away(unit, origin, 1)
		apply_base_surface_element(cell, BattleSurfaceState.Element.AIR, {
			"source_cell": origin,
			"action_id": action_id,
		})


func _resolve_falling_pillar(
	pillar: BattleObjectState,
	source_cell: Vector2i,
	action_id: int
) -> void:
	var direction_index := BattleHexGrid.direction_index(source_cell, pillar.cell)
	var axial_direction := pillar.fall_direction
	if direction_index >= 0:
		axial_direction = BattleHexGrid.AXIAL_DIRECTIONS[direction_index]
	elif not BattleHexGrid.AXIAL_DIRECTIONS.has(axial_direction):
		axial_direction = BattleHexGrid.AXIAL_DIRECTIONS[0]
	var axial := BattleHexGrid.offset_to_axial(pillar.cell)
	var fall_cells: Array[Vector2i] = []
	for step in range(1, 3):
		var cell := BattleHexGrid.axial_to_offset(axial + axial_direction * step)
		if not map_data.is_valid_cell(cell):
			break
		fall_cells.append(cell)
	var initial_units: Dictionary = {}
	var initial_objects: Dictionary = {}
	for cell in fall_cells:
		initial_units[cell] = get_unit_at_cell(cell)
		initial_objects[cell] = get_battle_object_at_cell(cell)
	for cell in fall_cells:
		var unit := initial_units.get(cell) as BattleUnitState
		if unit != null:
			apply_environment_damage(unit, 4, "\u5899\u67f1\u5012\u584c")
			if unit.is_alive():
				force_move_away(unit, pillar.cell, 1)
		var battle_object := initial_objects.get(cell) as BattleObjectState
		if battle_object != null:
			apply_object_damage(null, battle_object, 4, "\u5899\u67f1\u5012\u584c", {
				"environmental": true,
				"source_cell": pillar.cell,
				"action_id": action_id,
			})
	for cell in fall_cells:
		if get_unit_at_cell(cell) == null and get_battle_object_at_cell(cell) == null:
			spawn_battle_object(BattleObjectDefinition.Kind.RUBBLE, cell)


func _apply_element_to_area(origin: Vector2i, radius: int, element: int, action_id: int) -> void:
	var cells: Array[Vector2i] = map_data.get_cells_in_range(origin, radius)
	_sort_cells_stably(cells)
	for cell in cells:
		apply_base_surface_element(cell, element, {
			"source_cell": origin,
			"action_id": action_id,
		})


func spawn_battle_object(
	object_kind: int,
	cell: Vector2i,
	fall_direction: Vector2i = Vector2i.ZERO
) -> BattleObjectState:
	if map_data == null or not map_data.is_valid_cell(cell) \
			or get_unit_at_cell(cell) != null or get_battle_object_at_cell(cell) != null:
		return null
	var next_id := 0
	for existing in battle_objects:
		if existing != null:
			next_id = maxi(next_id, existing.object_id + 1)
	var battle_object := BattleObjectState.create(next_id, object_kind, cell, fall_direction)
	battle_objects.append(battle_object)
	if battle_object.definition.persistent_element != BattleSurfaceState.Element.NONE:
		surface_state.add_persistent_source(
			cell,
			battle_object.definition.persistent_element,
			"object:%d" % battle_object.object_id,
			"battle_object"
		)
	state_changed.emit()
	return battle_object


func _sort_cells_stably(cells: Array[Vector2i]) -> void:
	cells.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		return left.y < right.y or (left.y == right.y and left.x < right.x)
	)


func _resolve_ranger_turn_end(unit: BattleUnitState) -> void:
	if unit == null or not unit.is_ranger():
		return
	collect_surface_elements(unit, unit.cell, "回合结束", {"reason": "ranger_turn_end"})
	if unit.ranger_state.stealth_active and unit.turn_serial >= unit.ranger_state.stealth_expires_turn_serial:
		unit.leave_stealth()
		_emit_log("%s 的潜行自然结束。" % unit.get_display_name())
	unit.ranger_state.universal_combo_ready = false
	unit.ranger_state.universal_combo_expires_turn_serial = -1


func _queue_ranger_combo_reward(unit: BattleUnitState, threshold: int) -> void:
	match threshold:
		2:
			enqueue_effect(Callable(unit, "draw_cards"), [1, rng, {"controller": self, "reason": "ranger_combo_2"}], 0, "连击2：抽牌")
		4:
			var existing := unit.get_status("ranger_turn_damage_bonus")
			if existing != null:
				existing.stacks = maxi(existing.stacks, 2)
			else:
				var status := RangerTurnDamageBonusStatus.new()
				status.stacks = 2
				unit.add_status(status)
		6:
			var move_status := NextMoveApDiscountStatus.new()
			move_status.discount_amount = 1
			unit.add_status(move_status)
		8:
			enqueue_effect(Callable(self, "enter_ranger_stealth"), [unit, "连击潜行"], 0, "连击8：潜行")
		10:
			enqueue_effect(Callable(self, "_grant_ranger_finisher"), [unit], 0, "连击10：猎杀时刻")


func _grant_ranger_finisher(unit: BattleUnitState) -> void:
	var template := load("res://resources/cards/ranger_hunt_moment.tres") as CardData
	if unit == null or template == null:
		return
	var card := template.duplicate(true) as CardData
	unit.hand.append(card)
	unit.mark_temporary_card(card, 0, true, true)
	_emit_log("%s 获得衍生牌“猎杀时刻”。" % unit.get_display_name())
	state_changed.emit()


func apply_damage(source: BattleUnitState, target: BattleUnitState, amount: int, label: String = "伤害", metadata: Dictionary = {}) -> int:
	if target == null or not target.is_alive():
		return 0
	if amount <= 0:
		return 0

	var source_card := metadata.get("source_card") as CardData
	if should_cancel_hostile_effect(source, target, label, source_card):
		return 0
	var redirect := _find_curse_damage_redirect(target, source, metadata)
	if not redirect.is_empty():
		var redirected_target := redirect.get("target") as BattleUnitState
		if redirected_target != null and redirected_target.is_alive():
			_emit_log("%s 代替 %s 承受本段伤害。" % [redirected_target.get_display_name(), target.get_display_name()])
			target = redirected_target
			amount = maxi(0, amount - int(redirect.get("reduction", 0)))
			if amount <= 0:
				return 0
	var adjusted_amount := amount
	var damage_context := DamageContext.create(self, source, target, adjusted_amount, label)
	damage_context.metadata["action_id"] = get_current_action_id()
	for key in metadata:
		damage_context.metadata[key] = metadata[key]
	target.modify_incoming_damage(damage_context)
	if damage_context.prevented:
		return 0
	if target.has_method("get_damage_reduction"):
		var reduction := target.get_damage_reduction({
			"controller": self,
			"source": source,
			"target": target,
			"label": label,
			"amount": damage_context.amount,
			"damage_context": damage_context,
			"action_id": get_current_action_id(),
		})
		if reduction >= 0:
			damage_context.reduce_amount(reduction)
		else:
			damage_context.amount += -reduction
		if damage_context.prevented:
			return 0
	_process_before_damage(target, damage_context)
	if damage_context.prevented:
		return 0
	var is_environmental := bool(metadata.get("environmental", false))
	if source != null and not bool(metadata.get("fixed_damage", false)) and not is_environmental:
		source.modify_outgoing_damage(damage_context)
	if bool(damage_context.metadata.get("converted_to_status", false)):
		return 0

	var health_before := target.get_current_health()
	var lethal_context := {
		"controller": self,
		"source": source,
		"target": target,
		"label": label,
		"is_damage": true,
		"damage_context": damage_context,
		"action_id": get_current_action_id(),
	}
	var health_floor := target.get_lethal_health_floor(lethal_context)
	target.set_current_health(maxi(health_floor, health_before - damage_context.amount))
	var actual := health_before - target.get_current_health()
	if actual > 0 and target.is_curse_proxy and target.curse_proxy_mirrors_damage and target.curse_proxy_owner != null:
		lose_life(target, target.curse_proxy_owner, actual, "活根伤害转移", {"curse_source": true})
	var source_name := "效果"
	if source != null:
		source_name = source.get_display_name()
	_emit_log("%s 对 %s 造成 %d 点%s。" % [source_name, target.get_display_name(), actual, label])
	var event_context := {
		"controller": self,
		"source": source,
		"target": target,
		"amount": actual,
		"requested_amount": amount,
		"label": label,
		"damage_context": damage_context,
		"action_id": get_current_action_id(),
	}
	if source != null and actual > 0 and not is_environmental:
		source.notify_after_damage_dealt(event_context)
		if source.card_has_active_lifesteal(source_card):
			heal_unit(source, source, actual, "吸血")
		if surface_state.get_air_effect(source.cell) == BattleSurfaceState.Element.BLAZE:
			var backlash_key := "ranger_blaze_backlash_%d" % get_current_action_id()
			if not source.battle_action_flags.has(backlash_key):
				source.battle_action_flags[backlash_key] = true
				enqueue_effect(Callable(self, "apply_damage"), [null, source, 1, "烈焰反噬", {"environmental": true}], -10, "烈焰反噬")
	if actual > 0:
		target.notify_life_lost(actual, event_context.merged({"is_damage": true}))
		target.notify_after_damage_taken(event_context)
	if health_before > 0 and not target.is_alive():
		_notify_unit_death(source, target, event_context)
	return actual


func _find_curse_damage_redirect(original_target: BattleUnitState, source: BattleUnitState, metadata: Dictionary) -> Dictionary:
	if original_target == null:
		return {}
	for candidate in units:
		if candidate == null or candidate.faction != original_target.faction or not candidate.is_alive():
			continue
		for curse in candidate.curse_zone:
			if not candidate.is_curse_effect_active(curse) or curse.definition == null or curse.definition.effect == null:
				continue
			var result := curse.definition.effect.get_damage_redirect(candidate, curse, original_target, {
				"controller": self,
				"source": source,
				"metadata": metadata,
			})
			if not result.is_empty():
				return result
	return {}


func lose_life(source: BattleUnitState, target: BattleUnitState, amount: int, label: String = "生命损失", metadata: Dictionary = {}) -> int:
	if target == null or not target.is_alive() or amount <= 0:
		return 0
	var before := target.get_current_health()
	var event_context := {
		"controller": self,
		"source": source,
		"target": target,
		"amount": amount,
		"label": label,
		"is_damage": false,
		"action_id": get_current_action_id(),
	}
	for key in metadata:
		event_context[key] = metadata[key]
	var floor := target.get_lethal_health_floor(event_context)
	target.set_current_health(maxi(floor, before - amount))
	var actual := before - target.get_current_health()
	if actual <= 0:
		return 0
	_emit_log("%s 失去 %d 点生命（%s）。" % [target.get_display_name(), actual, label])
	event_context["amount"] = actual
	target.notify_life_lost(actual, event_context)
	if before > 0 and not target.is_alive():
		_notify_unit_death(source, target, event_context)
	return actual


func _notify_unit_death(source: BattleUnitState, target: BattleUnitState, context: Dictionary = {}) -> void:
	if target == null or bool(target.battle_action_flags.get("death_notified", false)):
		return
	if EnemyRuleDispatcher.try_handle_lethal(self, source, target, context):
		return
	target.battle_action_flags["death_notified"] = true
	target.notify_death(context)
	if source != null and source != target:
		source.notify_kill(target, context)
	_emit_log("%s 已死亡。" % target.get_display_name())


func heal_unit(source: BattleUnitState, target: BattleUnitState, amount: int, label: String = "治疗") -> int:
	if target == null or not target.is_alive() or amount <= 0:
		return 0

	var adjusted_amount := amount
	var heal_context := {
		"controller": self,
		"source": source,
		"target": target,
		"label": label,
		"action_id": get_current_action_id(),
	}
	adjusted_amount = target.modify_healing_received(adjusted_amount, heal_context)
	for status in target.statuses:
		if status != null:
			adjusted_amount = status.modify_healing_received(target, adjusted_amount, heal_context)
	if target.is_warlock_adventurer():
		if adjusted_amount > 0:
			lose_life(source, target, adjusted_amount, "%s（受咒者）" % label, {
				"warlock_healing_replaced": true,
				"requested_healing": amount,
			})
		return 0
	var before := target.get_current_health()
	target.set_current_health(before + adjusted_amount)
	var actual := target.get_current_health() - before
	if actual <= 0:
		return 0

	var source_name := "效果"
	if source != null:
		source_name = source.get_display_name()
	_emit_log("%s 为 %s 恢复 %d 点%s。" % [source_name, target.get_display_name(), actual, label])
	var event_context := {
		"controller": self,
		"source": source,
		"target": target,
		"amount": actual,
		"requested_amount": amount,
		"label": label,
		"action_id": get_current_action_id(),
	}
	if source != null:
		source.notify_after_heal_given(event_context)
	target.notify_after_heal_received(event_context)
	return actual


func gain_life(source: BattleUnitState, target: BattleUnitState, amount: int, label: String = "获得生命") -> Dictionary:
	var result := {
		"gained": 0,
		"overflow": 0,
		"max_health_lost": 0,
	}
	if target == null or not target.is_alive() or amount <= 0:
		return result
	var previous_health := target.get_current_health()
	var previous_max_health := target.get_max_health()
	var room := maxi(0, previous_max_health - previous_health)
	var overflow := maxi(0, amount - room)
	target.set_current_health(previous_health + mini(amount, room))
	if target.is_warlock_adventurer() and target.character_state != null and overflow > 0:
		var max_health_lost := mini(overflow, maxi(0, previous_max_health - 1))
		target.character_state.persistent_max_health_modifier -= max_health_lost
		target.set_current_health(target.get_current_health())
		result["max_health_lost"] = max_health_lost
	result["gained"] = maxi(0, target.get_current_health() - previous_health)
	result["overflow"] = overflow
	var event_context := {
		"controller": self,
		"source": source,
		"target": target,
		"amount": amount,
		"actual_health_change": int(result["gained"]),
		"overflow": overflow,
		"max_health_lost": int(result["max_health_lost"]),
		"label": label,
		"action_id": get_current_action_id(),
	}
	target.notify_after_life_gained(event_context)
	_emit_log("%s 获得 %d 点生命（%s）。" % [target.get_display_name(), amount, label])
	if int(result["max_health_lost"]) > 0:
		_emit_log("%s 因生命溢出永久失去 %d 点本次冒险最大生命。" % [
			target.get_display_name(),
			int(result["max_health_lost"]),
		])
	state_changed.emit()
	return result


func can_resolve_rebirth(unit: BattleUnitState) -> bool:
	return unit != null and unit.is_alive() and unit.character_state != null \
		and not CurseCatalog.get_rebirth_candidates(unit.character_state).is_empty()


func resolve_rebirth(unit: BattleUnitState) -> CurseInstance:
	if not can_resolve_rebirth(unit):
		return null
	var candidates := CurseCatalog.get_rebirth_candidates(unit.character_state)
	var definition := candidates[rng.randi_range(0, candidates.size() - 1)]
	var existing := unit.character_state.get_curse(definition.curse_id)
	gain_life(unit, unit, 20 if unit.is_warlock_adventurer() else 10, "往生")
	var acquired := unit.character_state.acquire_curse(definition)
	if acquired == null:
		return null
	if existing == null and definition.industry_card != null:
		var industry_card := definition.industry_card.duplicate(true) as CardData
		if industry_card != null:
			industry_card.bound_curse_instance = acquired
			unit.draw_pile.append(industry_card)
			unit.shuffle_draw_pile(rng)
	_emit_log("%s 通过往生获得了诅咒“%s”。" % [unit.get_display_name(), acquired.get_display_name()])
	state_changed.emit()
	return acquired


func get_opposing_units(unit: BattleUnitState) -> Array[BattleUnitState]:
	var result: Array[BattleUnitState] = []
	if unit == null:
		return result

	var source := enemy_units
	if unit.faction == BattleUnitState.Faction.ENEMY:
		source = player_units

	for other in source:
		if other.is_alive():
			result.append(other)

	return result


func get_nearest_opponent(unit: BattleUnitState) -> BattleUnitState:
	var nearest: BattleUnitState = null
	var nearest_distance := INF
	for other in get_opposing_units(unit):
		var distance := unit.cell_distance_to(other)
		if distance < nearest_distance:
			nearest = other
			nearest_distance = distance

	return nearest


func find_playable_card_against(user: BattleUnitState, target: BattleUnitState) -> CardData:
	if user == null or target == null:
		return null

	for card in user.hand:
		if card == null:
			continue
		if not can_play_card_with_mode(user, card, CardEnums.CardPlayMode.NORMAL):
			continue
		if can_preview_card_targets(user, card, [target]):
			return card

	return null


func get_alive_units() -> Array[BattleUnitState]:
	var result: Array[BattleUnitState] = []
	for unit in units:
		if unit.is_alive():
			result.append(unit)

	return result


func get_unit_at_cell(selected_cell: Vector2i) -> BattleUnitState:
	for unit in units:
		if not unit.is_deployed or not unit.is_alive():
			continue
		if unit.get_occupied_cells().has(selected_cell):
			return unit

	return null


func get_battle_object_at_cell(selected_cell: Vector2i) -> BattleObjectState:
	for battle_object in battle_objects:
		if battle_object != null and battle_object.is_active() and battle_object.cell == selected_cell:
			return battle_object
	return null


func get_battle_objects_in_range(
	origin: Vector2i,
	range_distance: int
) -> Array[BattleObjectState]:
	var result: Array[BattleObjectState] = []
	for battle_object in battle_objects:
		if battle_object != null and battle_object.can_be_damaged() \
				and map_data.get_distance(origin, battle_object.cell) <= maxi(0, range_distance):
			result.append(battle_object)
	result.sort_custom(func(left: BattleObjectState, right: BattleObjectState) -> bool:
		var left_distance := map_data.get_distance(origin, left.cell)
		var right_distance := map_data.get_distance(origin, right.cell)
		return left_distance < right_distance \
			or (left_distance == right_distance and left.object_id < right.object_id)
	)
	return result


func perform_object_strike_with_modifier(
	attacker: BattleUnitState,
	target: BattleObjectState,
	source = null,
	damage_modifier: int = 0,
	label: String = "\u6253\u51fb",
	equipment_slot: String = ""
) -> int:
	return strike_resolver.perform_object_strike_with_modifier(
		attacker,
		target,
		source,
		damage_modifier,
		label,
		equipment_slot
	)


func get_cell_detail_text(cell: Vector2i) -> String:
	if map_data == null or not map_data.is_valid_cell(cell):
		return ""
	var snapshot := surface_state.get_cell_snapshot(cell)
	var lines: Array[String] = []
	lines.append("(%d, %d)" % [cell.x, cell.y])
	var terrain := int(snapshot.get("terrain", BattleSurfaceState.Terrain.NONE))
	lines.append("\u5730\u5f62\uff1a%s" % BattleSurfaceState.terrain_label(terrain))
	lines.append("效果：%s" % BattleSurfaceState.terrain_description(terrain))
	var ground := int(snapshot.get("ground_effect", BattleSurfaceState.Element.NONE))
	if ground != BattleSurfaceState.Element.NONE:
		var ground_state := snapshot.get("ground_effect_state", {}) as Dictionary
		var ground_rounds := maxi(
			0,
			int(ground_state.get("expires_round", battle_round)) - battle_round
		)
		lines.append("\u5730\u9762\u6548\u679c\uff1a%s\uff08%d \u8f6e\uff09" % [
			BattleSurfaceState.label(ground),
			ground_rounds,
		])
		lines.append("  %s" % BattleSurfaceState.element_description(ground))
	var air := int(snapshot.get("air_effect", BattleSurfaceState.Element.NONE))
	if air != BattleSurfaceState.Element.NONE:
		var air_state := snapshot.get("air_effect_state", {}) as Dictionary
		var air_rounds := maxi(
			0,
			int(air_state.get("expires_round", battle_round)) - battle_round
		)
		lines.append("\u7a7a\u6c14\u6548\u679c\uff1a%s\uff08%d \u8f6e\uff09" % [
			BattleSurfaceState.label(air),
			air_rounds,
		])
		lines.append("  %s" % BattleSurfaceState.element_description(air))
	var persistent_sources := snapshot.get("persistent_sources", []) as Array
	if not persistent_sources.is_empty():
		var source_labels: Array[String] = []
		for source_value in persistent_sources:
			var source_entry := source_value as Dictionary
			source_labels.append("%s[%s]" % [
				BattleSurfaceState.label(int(source_entry.get("element", BattleSurfaceState.Element.NONE))),
				str(source_entry.get("kind", "\u6548\u679c")),
			])
		lines.append("\u6c38\u4e45\u5143\u7d20\u6e90\uff1a%s" % "\u3001".join(source_labels))
	var residues := snapshot.get("residues", {}) as Dictionary
	if not residues.is_empty():
		var residue_labels: Array[String] = []
		for element in BattleSurfaceState.BASE_ELEMENTS:
			if not residues.has(element):
				continue
			var residue := residues.get(element, {}) as Dictionary
			var remaining := maxi(
				0,
				int(residue.get("expires_round", battle_round)) - battle_round
			)
			residue_labels.append("%s\uff08%d \u8f6e\uff09" % [
				BattleSurfaceState.label(element),
				remaining,
			])
		lines.append("\u4e34\u65f6\u5143\u7d20\u6b8b\u7559\uff1a%s" % "\u3001".join(residue_labels))
	var readable: Array = snapshot.get("readable_elements", []) as Array
	if not readable.is_empty():
		var labels: Array[String] = []
		for element_value in readable:
			labels.append(BattleSurfaceState.label(int(element_value)))
		lines.append("\u53ef\u8bfb\u5143\u7d20\uff1a%s" % "\u3001".join(labels))
	var battle_object := get_battle_object_at_cell(cell)
	if battle_object != null:
		lines.append("%s\uff1a%d/%d \u751f\u547d" % [
			battle_object.get_display_name(),
			battle_object.current_health,
			battle_object.get_max_health(),
		])
		var blocking: Array[String] = []
		if battle_object.blocks_movement():
			blocking.append("\u963b\u6321\u79fb\u52a8")
		if battle_object.blocks_line_of_sight():
			blocking.append("\u963b\u6321\u89c6\u7ebf")
		if not blocking.is_empty():
			lines.append("\u7279\u6027\uff1a%s" % "\u3001".join(blocking))
		if battle_object.definition != null and not battle_object.definition.description.is_empty():
			lines.append("效果：%s" % battle_object.definition.description)
	return "\n".join(lines)


func get_first_undeployed_player() -> BattleUnitState:
	for unit in player_units:
		if not unit.is_deployed:
			return unit

	return null


func _begin_enemy_turn(unit: BattleUnitState) -> void:
	if not _is_active_enemy_turn(unit):
		return
	enemy_decision_count = 0
	var behavior := _get_enemy_behavior(unit)
	if behavior == null:
		_emit_log("%s 没有战斗逻辑，结束回合。" % unit.get_display_name())
		_complete_enemy_turn(unit)
		return

	behavior.on_turn_start({"controller": self}, unit)
	_queue_enemy_decision(unit)


func _queue_enemy_decision(unit: BattleUnitState) -> void:
	if not _is_active_enemy_turn(unit):
		return
	if enemy_decision_count >= MAX_ENEMY_DECISIONS_PER_TURN:
		_emit_log("%s 的行动次数达到 %d，强制结束回合。" % [unit.get_display_name(), MAX_ENEMY_DECISIONS_PER_TURN])
		_complete_enemy_turn(unit)
		return

	var decision_result := {"action_started": false}
	if not push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_enemy_decision_action"),
		[unit, decision_result],
		0,
		"%s 敌方决策" % unit.get_display_name(),
		{"unit": unit, "decision_index": enemy_decision_count},
		Callable(self, "_finish_enemy_decision_action"),
		[unit, decision_result]
	)):
		_complete_enemy_turn(unit)


func _resolve_enemy_decision_action(unit: BattleUnitState, decision_result: Dictionary) -> void:
	decision_result["action_started"] = false
	if not _is_active_enemy_turn(unit):
		return

	var behavior := _get_enemy_behavior(unit)
	if behavior == null:
		return
	enemy_decision_count += 1
	internal_action_submission_depth += 1
	var result := behavior.choose_action({"controller": self}, unit)
	internal_action_submission_depth = maxi(0, internal_action_submission_depth - 1)
	decision_result["action_started"] = bool(result.get("action_started", false))


func _finish_enemy_decision_action(unit: BattleUnitState, decision_result: Dictionary) -> void:
	if not _is_active_enemy_turn(unit):
		return
	if bool(decision_result.get("action_started", false)):
		_queue_enemy_decision(unit)
	else:
		_complete_enemy_turn(unit)


func _complete_enemy_turn(unit: BattleUnitState) -> void:
	if not _is_active_enemy_turn(unit):
		return
	var behavior := _get_enemy_behavior(unit)
	if behavior != null:
		behavior.on_turn_end({"controller": self}, unit)
	_request_turn_end(unit)


func _is_active_enemy_turn(unit: BattleUnitState) -> bool:
	return phase == Phase.BATTLE \
		and turn_flow_state == TurnFlowState.ACTIVE \
		and unit != null \
		and current_unit == unit \
		and unit.faction == BattleUnitState.Faction.ENEMY \
		and unit.is_alive()


func _get_enemy_behavior(unit: BattleUnitState) -> EnemyBehavior:
	if unit == null or unit.enemy_state == null or unit.enemy_state.enemy_data == null:
		return null
	return unit.enemy_state.enemy_data.behavior


func _lock_all_enemy_intents() -> void:
	for unit in enemy_units:
		_lock_enemy_intent(unit)


func _lock_enemy_intent(unit: BattleUnitState) -> void:
	var behavior := _get_enemy_behavior(unit)
	if behavior != null and unit != null and unit.is_alive():
		behavior.lock_intent({"controller": self, "phase": "intent_lock"}, unit)


func _targets_are_valid(user: BattleUnitState, card: CardData, targets: Array, write_log: bool = true, equipment_slot: String = "", play_mode: int = CardEnums.CardPlayMode.NORMAL, extra_context: Dictionary = {}) -> bool:
	var target_type := _get_card_target_type(user, card, equipment_slot, play_mode, extra_context)
	if target_type == CardEnums.TargetType.NONE:
		return _card_effect_targets_are_valid(user, card, targets, write_log, equipment_slot, play_mode, extra_context)

	if target_type == CardEnums.TargetType.AREA:
		if targets.size() != 1 or not (targets[0] is Vector2i):
			if write_log:
				_emit_log("%s 需要一个位置目标。" % card.card_name)
			return false
		if not map_data.is_valid_cell(targets[0]):
			if write_log:
				_emit_log("目标位置超出地图边界。")
			return false
		return _card_effect_targets_are_valid(user, card, targets, write_log, equipment_slot, play_mode, extra_context)

	if target_type == CardEnums.TargetType.SELF:
		if targets.size() != 1 or targets[0] != user:
			if write_log:
				_emit_log("%s 目标必须是自己。" % card.card_name)
			return false
		return _card_effect_targets_are_valid(user, card, targets, write_log, equipment_slot, play_mode, extra_context)

	if target_type == CardEnums.TargetType.ALL:
		return _card_effect_targets_are_valid(user, card, targets, write_log, equipment_slot, play_mode, extra_context)

	if target_type == CardEnums.TargetType.SINGLE and targets.size() != 1:
		if write_log:
			_emit_log("%s 需要一个目标。" % card.card_name)
		return false

	for target in targets:
		if target is BattleObjectState:
			var target_object := target as BattleObjectState
			var object_context := extra_context.duplicate()
			object_context["controller"] = self
			object_context["user"] = user
			object_context["card"] = card
			object_context["equipment_slot"] = equipment_slot
			object_context["play_mode"] = play_mode
			if not card.is_object_target_allowed(object_context, target_object):
				if write_log:
					_emit_log("%s \u4e0d\u80fd\u9009\u62e9 %s \u4f5c\u4e3a\u76ee\u6807\u3002" % [
						card.card_name,
						target_object.get_display_name(),
					])
				return false
			var object_range := card.get_effective_range(user, equipment_slot)
			if card.effect != null and card.effect.uses_strike:
				var object_profile := user.build_strike_profile_object(
					equipment_slot,
					{"controller": self, "target_object": target_object}
				)
				var targetless_weapon_range := user.get_attack_range(
					equipment_slot,
					{"controller": self}
				)
				object_range += get_effective_attack_range_at_cell(
					user,
					target_object.cell,
					equipment_slot
				) - targetless_weapon_range
				if object_profile.primary_range_type == EquipmentData.WeaponRangeType.RANGED \
						and not targeting.has_line_of_sight(user.cell, target_object.cell):
					return false
			if map_data.get_distance(user.cell, target_object.cell) > object_range:
				return false
			continue
		if not (target is BattleUnitState) or not target.is_alive():
			if write_log:
				_emit_log("目标无效。")
			return false

		var target_context := extra_context.duplicate()
		target_context["controller"] = self
		target_context["user"] = user
		target_context["card"] = card
		target_context["equipment_slot"] = equipment_slot
		target_context["play_mode"] = play_mode
		if not target_context.has("druid_orientation"):
			target_context["druid_orientation"] = _get_druid_orientation_for_card(user, card)
		if not card.is_unit_target_allowed(target_context, target):
			if write_log:
				_emit_log("%s 不能选择 %s 作为目标。" % [card.card_name, target.get_display_name()])
			return false
		if not target.can_be_targeted_by_other_card(user, card, target_context):
			if write_log:
				_emit_log("%s 受到披夜保护，暂时不能成为其他单位手牌的目标。" % target.get_display_name())
			return false
		if user.faction == target.faction and not target.can_be_friendly_target(user, target_context):
			if write_log:
				_emit_log("%s 当前不能成为其他友方效果的目标。" % target.get_display_name())
			return false
		if target_type == CardEnums.TargetType.SINGLE and user.faction != target.faction and is_unit_concealed(target):
			if write_log:
				_emit_log("%s 位于隐蔽地表，不能被敌方单体效果指定。" % target.get_display_name())
			return false

		var distance := user.get_range_distance_to(target, {"controller": self, "equipment_slot": equipment_slot, "card": card})
		var card_range := card.get_effective_range(user, equipment_slot)
		if card.effect != null and card.effect.uses_strike:
			var profile := user.build_strike_profile_object(equipment_slot, {"controller": self, "target": target})
			var effective_weapon_range := get_effective_attack_range_against(user, target, equipment_slot)
			var targetless_weapon_range := user.get_attack_range(equipment_slot, {"controller": self})
			card_range += effective_weapon_range - targetless_weapon_range
			if profile.primary_range_type == EquipmentData.WeaponRangeType.RANGED \
					and not targeting.has_line_of_sight_between_units(user, target):
				if write_log:
					_emit_log("%s \u4e0e %s \u4e4b\u95f4\u7684\u89c6\u7ebf\u88ab\u963b\u6321\u3002" % [
						user.get_display_name(),
						target.get_display_name(),
					])
				return false
			if card.effect is RangerHuntMomentCardEffect and profile.primary_range_type == EquipmentData.WeaponRangeType.RANGED:
				card_range = effective_weapon_range + 2
				if distance > card_range:
					if write_log:
						_emit_log("%s 距离 %.0f，超出 %s 射程 %.0f。" % [target.get_display_name(), distance, card.card_name, card_range])
					return false
				continue
		if distance > card_range:
			if write_log:
				_emit_log("%s 距离 %.0f，超出 %s 射程 %.0f。" % [target.get_display_name(), distance, card.card_name, card_range])
			return false

	return _card_effect_targets_are_valid(user, card, targets, write_log, equipment_slot, play_mode, extra_context)


func _card_effect_targets_are_valid(user: BattleUnitState, card: CardData, targets: Array, write_log: bool, equipment_slot: String, play_mode: int, extra_context: Dictionary = {}) -> bool:
	if card == null:
		return false

	var context := extra_context.duplicate()
	context["controller"] = self
	context["user"] = user
	context["card"] = card
	context["equipment_slot"] = equipment_slot
	context["play_mode"] = play_mode
	return card.are_targets_valid(context, targets, write_log)


func _get_card_target_type(user: BattleUnitState, card: CardData, equipment_slot: String = "", play_mode: int = CardEnums.CardPlayMode.NORMAL, extra_context: Dictionary = {}) -> int:
	if card == null:
		return CardEnums.TargetType.NONE

	var context := extra_context.duplicate()
	context["controller"] = self
	context["user"] = user
	context["card"] = card
	context["equipment_slot"] = equipment_slot
	context["play_mode"] = play_mode
	if not context.has("druid_orientation"):
		context["druid_orientation"] = _get_druid_orientation_for_card(user, card)
	return card.get_target_type_for_mode(play_mode, context)


func _is_cell_valid_for_unit(unit: BattleUnitState, cell: Vector2i, deployment_only: bool, write_log: bool = true) -> bool:
	if not targeting.is_unit_inside_map_bounds(unit, cell, write_log):
		return false

	if deployment_only and not map_data.is_player_deployment_cell(cell):
		if write_log:
			_emit_log("目标位置不在玩家部署区内。")
		return false

	return targeting.is_unit_cell_clear(unit, cell, write_log)


func _find_enemy_spawn_cell() -> Variant:
	for _i in range(map_data.grid_columns * map_data.grid_rows * 2):
		var cell := map_data.random_enemy_spawn_cell(rng)
		if _is_spawn_cell_valid(cell):
			return cell

	for cell in map_data.get_all_cells():
		if not map_data.is_enemy_spawn_cell(cell):
			continue
		if _is_spawn_cell_valid(cell):
			return cell
	return null


func _find_enemy_spawn_cell_for_enemy(enemy_state: EnemyState) -> Variant:
	if enemy_state != null and enemy_state.enemy_data != null:
		var wants_formation := enemy_state.enemy_data.unit_tags.has("military")
		var wants_statue_anchor := enemy_state.enemy_data.unit_tags.has("statue")
		if wants_formation or wants_statue_anchor:
			for anchor in enemy_units:
				if anchor == null or not anchor.is_alive() or anchor.enemy_state == null \
						or anchor.enemy_state.enemy_data == null:
					continue
				var anchor_matches := anchor.enemy_state.enemy_data.unit_tags.has("military") if wants_formation \
					else anchor.enemy_state.enemy_data.archetype_id == &"gray_bastion_paladin"
				if not anchor_matches:
					continue
				for cell in map_data.get_cells_in_range(anchor.cell, 1):
					if cell != anchor.cell and map_data.is_enemy_spawn_cell(cell) and _is_spawn_cell_valid(cell):
						return cell
	return _find_enemy_spawn_cell()


func _is_spawn_cell_valid(cell: Vector2i) -> bool:
	if not map_data.is_valid_cell(cell):
		return false

	return targeting.is_unit_cell_clear(null, cell, false)


func _rebuild_turn_order() -> void:
	turn_order.clear()
	for unit in units:
		if unit.is_alive() and EnemyRuleDispatcher.can_take_turn(unit):
			turn_order.append(unit)

	turn_order.sort_custom(Callable(self, "_compare_turn_order"))


func _compare_turn_order(a: BattleUnitState, b: BattleUnitState) -> bool:
	if a.get_agility() == b.get_agility():
		return a.turn_order_index < b.turn_order_index

	return a.get_agility() > b.get_agility()


func _check_battle_end() -> bool:
	var players_alive := false
	for unit in player_units:
		if unit.is_alive():
			players_alive = true
			break

	var enemies_alive := false
	for unit in enemy_units:
		if unit.is_alive():
			enemies_alive = true
			break

	if players_alive and enemies_alive:
		return false

	phase = Phase.ENDED
	turn_flow_state = TurnFlowState.IDLE
	cards_in_flight.clear()
	resolution_runner.clear_pending_actions()
	_commit_battle_result(players_alive)
	var result := BattleResult.from_controller(self, players_alive)
	if players_alive:
		_emit_log("战斗胜利。")
	else:
		_emit_log("战斗失败。")
	state_changed.emit()
	battle_finished.emit(result)
	return true


func _commit_battle_result(victory: bool) -> void:
	if battle_result_committed:
		return
	battle_result_committed = true
	for unit in player_units:
		if unit == null or unit.character_state == null:
			continue
		unit.notify_curse_battle_finished(victory, {
			"controller": self,
			"phase": "battle_finished",
			"victory": victory,
			"immediate": true,
		})
		var transformed := unit.character_state.process_curse_battle_result(victory and unit.is_alive())
		for curse in transformed:
			_emit_log("%s 的诅咒“%s”由报转化为果。" % [unit.get_display_name(), curse.get_display_name()])
	_resolve_unrest_transfers()
	for unit in player_units:
		if unit == null or unit.character_state == null:
			continue
		var source := runtime_character_sources.get(unit.character_state) as CharacterState
		if source != null:
			unit.character_state.commit_curse_state_to(source)
			source.current_health = maxi(1, unit.get_current_health()) if victory else unit.get_current_health()
			source.ranger_element_inventory = unit.character_state.ranger_element_inventory.duplicate(true)


func _resolve_unrest_transfers() -> void:
	for unit in player_units:
		if unit == null or unit.character_state == null:
			continue
		for curse in unit.character_state.curse_instances.duplicate():
			if curse == null or curse.get_curse_id() != "unrest" or curse.state != CurseInstance.State.REPORT:
				continue
			if not bool(curse.persistent_data.get("transfer_after_battle", false)):
				continue
			curse.persistent_data.erase("transfer_after_battle")
			var candidates: Array[BattleUnitState] = []
			for candidate in player_units:
				if candidate != unit and candidate != null and candidate.is_alive() and candidate.character_state != null and candidate.character_state.get_curse("unrest") == null:
					candidates.append(candidate)
			if candidates.is_empty():
				continue
			var target := candidates[rng.randi_range(0, candidates.size() - 1)]
			unit.character_state.curse_instances.erase(curse)
			curse.deepen()
			target.character_state.curse_instances.append(curse)
			_emit_log("%s 的不休之报转移给 %s，并加深1。" % [unit.get_display_name(), target.get_display_name()])


func _emit_log(message: String) -> void:
	log_message.emit(message)


func _equipment_slot_label(slot: String) -> String:
	match slot:
		"weapon", "main":
			return "武器"
		"armor", "off":
			return "防具"
		"accessory_1":
			return "饰品1"
		"accessory_2":
			return "饰品2"
		_:
			return "装备栏"


func enqueue_effect(callback: Callable, args: Array = [], priority: int = 0, label: String = "", context = null) -> void:
	resolution_runner.enqueue_effect(callback, args, priority, label, context)


func enqueue_trigger(callback: Callable, args: Array = [], priority: int = 0, label: String = "", context = null) -> void:
	if get_current_action_id() <= 0:
		if callback.is_valid():
			callback.callv(args)
		return
	resolution_runner.enqueue_trigger(callback, args, priority, label, context)


func push_action_frame(frame: BattleActionFrame) -> bool:
	return resolution_runner.push_action_frame(frame)


func _on_action_frames_cancelled(frames: Array) -> void:
	for frame_value in frames:
		var frame := frame_value as BattleActionFrame
		if frame == null or not (frame.context is CardPlayContext):
			continue
		var card_context := frame.context as CardPlayContext
		if card_context.card != null:
			cards_in_flight.erase(card_context.card.get_instance_id())


func _on_action_resolution_completed(action_id: int) -> void:
	var prefix := "%d:" % action_id
	for key_value in stealth_cancelled_actions.keys().duplicate():
		if str(key_value).begins_with(prefix):
			stealth_cancelled_actions.erase(key_value)


func get_current_action_id() -> int:
	return resolution_runner.get_current_action_id()


func _can_submit_turn_action(unit: BattleUnitState, action_label: String, write_log: bool = true, allow_during_resolution: bool = false) -> bool:
	var failure := ""
	if phase != Phase.BATTLE:
		failure = "战斗尚未开始"
	elif unit == null or not unit.is_alive():
		failure = "行动单位无效"
	elif current_unit != unit or turn_flow_state != TurnFlowState.ACTIVE:
		failure = "当前不是该单位的行动阶段"
	elif (is_resolving_actions() or resolution_state_notification_active) \
		and internal_action_submission_depth <= 0 and not allow_during_resolution:
		failure = "当前仍在结算其他行动"

	if failure.is_empty():
		return true
	if write_log:
		_emit_log("无法执行%s：%s。" % [action_label, failure])
	return false


func _is_turn_action_execution_valid(unit: BattleUnitState) -> bool:
	return phase == Phase.BATTLE \
		and turn_flow_state == TurnFlowState.ACTIVE \
		and unit != null \
		and unit.is_alive() \
		and current_unit == unit


func is_resolving_actions() -> bool:
	return action_resolution_active or resolution_runner.is_draining_actions


func _begin_action_resolution() -> void:
	if action_resolution_active:
		return
	action_resolution_active = true
	state_changed.emit()


func _end_action_resolution() -> void:
	if not action_resolution_active:
		return
	action_resolution_active = false


func _notify_action_resolution_finished() -> void:
	resolution_state_notification_active = true
	state_changed.emit()
	resolution_state_notification_active = false
	if unbound_force_end_after_action and current_unit != null and turn_flow_state == TurnFlowState.ACTIVE:
		unbound_force_end_after_action = false
		_request_turn_end(current_unit)


func activate_unbound_industry(unit: BattleUnitState, depth: int) -> void:
	if unit == null or current_unit != unit:
		return
	unbound_skip_enemy_pending = true
	unbound_extra_unit = unit
	unbound_extra_ap = 2 + maxi(1, depth)
	unbound_force_end_after_action = true
	_emit_log("%s 结束当前回合，并以无羁截断下一名敌人的行动。" % unit.get_display_name())


func activate_curse_action(unit: BattleUnitState, curse: CurseInstance, action_id: String, extra_context: Dictionary = {}) -> bool:
	if not _can_submit_turn_action(unit, "诅咒行动"):
		return false
	var context := extra_context.duplicate()
	context["controller"] = self
	context["unit"] = unit
	context["curse"] = curse
	if not unit.can_activate_curse_action(curse, action_id, context):
		_emit_log("当前不能执行该诅咒行动。")
		return false
	return push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_curse_action"),
		[unit, curse, action_id, context],
		0,
		"%s 诅咒行动" % unit.get_display_name(),
		context
	))


func _resolve_curse_action(unit: BattleUnitState, curse: CurseInstance, action_id: String, context: Dictionary) -> void:
	if not _is_turn_action_execution_valid(unit):
		return
	if unit.activate_curse_action(curse, action_id, context):
		_emit_log("%s 执行了%s。" % [unit.get_display_name(), curse.get_display_name()])
	state_changed.emit()
	_check_battle_end()


func _begin_unbound_extra_phase() -> void:
	var unit := unbound_extra_unit
	if unit == null or not unit.is_alive():
		unbound_extra_unit = null
		turn_flow_state = TurnFlowState.IDLE
		advance_turn()
		return
	current_unit = unit
	turn_flow_state = TurnFlowState.ACTIVE
	unbound_extra_active = true
	unit.current_ap = unbound_extra_ap
	unbound_extra_unit = null
	unbound_extra_ap = 0
	action_phase_serial += 1
	if unit.is_mage_adventurer():
		unit.mage_state.start_action_phase()
	_emit_log("%s 获得无羁额外行动阶段与 %d AP。" % [unit.get_display_name(), unit.current_ap])
	state_changed.emit()


func spawn_curse_root(owner: BattleUnitState, target_cell: Vector2i, max_health: int, friendly: bool, mirrors_damage: bool = false, depth: int = 1) -> BattleUnitState:
	if owner == null or map_data == null or not map_data.is_valid_cell(target_cell):
		return null
	if not targeting.is_unit_cell_clear(null, target_cell, false):
		return null
	var root := BattleUnitState.new()
	root.setup_curse_proxy(units.size() + 1000, owner, "友方活根" if friendly else "敌方活根", max_health, not friendly, mirrors_damage, depth)
	root.set_hex_cell(target_cell, map_data)
	units.append(root)
	_emit_log("%s 在格 (%d, %d) 生成了%s。" % [owner.get_display_name(), target_cell.x, target_cell.y, root.get_display_name()])
	state_changed.emit()
	return root


func spawn_enemy_unit(enemy_state: EnemyState, target_cell: Vector2i, starting_hand_count: int = -1, shared_deck_owner: BattleUnitState = null) -> BattleUnitState:
	if enemy_state == null or map_data == null or not map_data.is_valid_cell(target_cell) \
			or not targeting.is_unit_cell_clear(null, target_cell, false):
		return null
	var next_id := 0
	for existing in units:
		if existing != null:
			next_id = maxi(next_id, existing.unit_id + 1)
	var unit := BattleUnitState.new()
	unit.setup_enemy(next_id, enemy_state, config.default_token_radius)
	unit.battle_controller = self
	unit.set_hex_cell(target_cell, map_data)
	if shared_deck_owner != null:
		unit.draw_pile = shared_deck_owner.draw_pile
		unit.discard_pile = shared_deck_owner.discard_pile
		unit.hand.clear()
	else:
		unit.ensure_initialized(config, rng)
	if starting_hand_count >= 0:
		for card in unit.hand:
			unit.draw_pile.append(card)
		unit.hand.clear()
		unit.shuffle_draw_pile(rng)
		unit.draw_cards(starting_hand_count, rng, {"controller": self, "reason": "enemy_spawn"})
	units.append(unit)
	enemy_units.append(unit)
	if phase == Phase.BATTLE:
		_lock_enemy_intent(unit)
	state_changed.emit()
	return unit


func get_curse_roots(owner: BattleUnitState, hostile: bool = false) -> Array[BattleUnitState]:
	var result: Array[BattleUnitState] = []
	for unit in units:
		if unit != null and unit.is_curse_proxy and unit.curse_proxy_owner == owner and unit.curse_proxy_hostile == hostile and unit.is_alive():
			result.append(unit)
	return result


func apply_temporary_curse_report(target: BattleUnitState, source_curse: CurseInstance, expires_after_turn_serial: int) -> bool:
	if target == null or source_curse == null or source_curse.definition == null:
		return false
	var projected := source_curse.duplicate(true) as CurseInstance
	projected.state = CurseInstance.State.REPORT
	projected.sealed = false
	target.add_curse_to_zone(projected, {"controller": self, "reason": "preservation_industry"})
	var status := TemporaryCurseReportStatus.new()
	status.projected_curse = projected
	status.expires_after_turn_serial = expires_after_turn_serial
	target.add_status(status)
	return true


func resolve_effect_queue() -> void:
	resolution_runner.resolve_effect_queue()


func _emit_basic_attack_trigger(context: Dictionary) -> void:
	basic_attack_triggered.emit(context)


func _emit_equipment_switch_started(context: Dictionary) -> void:
	equipment_switch_started.emit(context)


func _emit_equipment_switched_out(context: Dictionary) -> void:
	equipment_switched_out.emit(context)


func _emit_equipment_switched_in(context: Dictionary) -> void:
	equipment_switched_in.emit(context)


func _queue_global_effects(callback_name: String, unit: BattleUnitState = null) -> void:
	if scene_prototype == null:
		return

	for effect in scene_prototype.global_effects:
		if effect == null or not _resource_script_defines_method(effect, callback_name):
			continue

		var context := {
			"controller": self,
			"scenario": scenario,
			"scene_prototype": scene_prototype,
			"unit": unit,
		}
		enqueue_effect(
			Callable(effect, callback_name),
			[context],
			_get_effect_priority(effect),
			"%s.%s" % [effect.get_display_name(), callback_name],
			context
		)


func _queue_unit_status_effects(callback_name: String, unit: BattleUnitState) -> void:
	if unit == null:
		return

	for status in unit.statuses.duplicate():
		if status == null or not _resource_script_defines_method(status, callback_name):
			continue

		var context := {
			"controller": self,
			"unit": unit,
			"status": status,
		}
		enqueue_effect(
			Callable(status, callback_name),
			[unit, context],
			_get_effect_priority(status),
			"%s.%s" % [status.display_name, callback_name],
			context
		)


func queue_status_event(status: StatusEffect, callback_name: String, unit: BattleUnitState, context = null) -> void:
	if status == null or unit == null or not _resource_script_defines_method(status, callback_name):
		return

	var event_context = context
	if event_context == null:
		event_context = {}
	if event_context is Dictionary:
		event_context = event_context.duplicate()
		event_context["controller"] = self
		event_context["unit"] = unit
		event_context["status"] = status
	enqueue_effect(
		Callable(status, callback_name),
		[unit, event_context],
		_get_effect_priority(status),
		"%s.%s" % [status.display_name, callback_name],
		event_context
	)


func queue_unit_status_event(callback_name: String, unit: BattleUnitState, context = null) -> void:
	if unit == null:
		return

	for status in unit.statuses.duplicate():
		queue_status_event(status, callback_name, unit, context)


func _get_effect_priority(effect) -> int:
	if effect == null:
		return 0

	var value = effect.get("effect_priority")
	if value == null:
		return 0

	return int(value)


func _resource_script_defines_method(resource: Resource, method_name: String) -> bool:
	if resource == null or resource.get_script() == null:
		return false
	for method in resource.get_script().get_script_method_list():
		if str(method.get("name", "")) == method_name:
			return true
	return false


func _process_before_damage(target: BattleUnitState, damage_context: DamageContext) -> void:
	var statuses := target.statuses.duplicate()
	statuses.sort_custom(func(left, right): return _get_effect_priority(left) > _get_effect_priority(right))
	for status in statuses:
		if status == null or not status.has_method("on_before_damage"):
			continue
		status.on_before_damage(target, damage_context)
		if damage_context.prevented:
			break

	target.remove_expired_statuses()
