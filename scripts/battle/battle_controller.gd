extends RefCounted
class_name BattleController

const BattleHexGrid = preload("res://scripts/battle/battle_hex_grid.gd")

signal log_message(message: String)
signal state_changed
signal basic_attack_triggered(context: Dictionary)
signal equipment_switch_started(context: Dictionary)
signal equipment_switched_out(context: Dictionary)
signal equipment_switched_in(context: Dictionary)

const DRUID_PREPARE_TRANSFORM_ACTION := "druid_prepare_transform"
const DRUID_PREPARE_UNTRANSFORM_ACTION := "druid_prepare_untransform"
const WARRIOR_MOMENTUM_RESOURCE := "势"
const MAX_ENEMY_DECISIONS_PER_TURN := 32
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

func setup(new_scenario: BattleScenario) -> void:
	scenario = new_scenario
	if scenario == null:
		config = BattleConfig.new()
		scene_prototype = null
		map_data = BattleMapData.new()
		_reset_runtime_state()
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
	resolution_runner.setup(self)
	targeting.setup(self)
	strike_resolver.setup(self)

	var id := 0
	for character_template in scenario.get_player_states():
		if character_template == null:
			continue
		var character_state := _create_runtime_character_state(character_template)
		if character_state == null:
			continue
		var unit := BattleUnitState.new()
		unit.setup_player(id, character_state, config.default_token_radius)
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
		var spawn_cell_value: Variant = _find_enemy_spawn_cell()
		if not (spawn_cell_value is Vector2i):
			_emit_log("敌方出生区已满，跳过 %s。" % enemy_state.get_enemy_name())
			continue
		var spawn_cell: Vector2i = spawn_cell_value
		var unit := BattleUnitState.new()
		unit.setup_enemy(id, enemy_state, config.default_token_radius)
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


func _reset_runtime_state() -> void:
	phase = Phase.DEPLOYMENT
	units.clear()
	player_units.clear()
	enemy_units.clear()
	turn_order.clear()
	current_turn_index = -1
	current_unit = null
	turn_flow_state = TurnFlowState.IDLE
	enemy_decision_count = 0
	cards_in_flight.clear()
	action_resolution_active = false
	internal_action_submission_depth = 0
	resolution_state_notification_active = false


func _create_runtime_character_state(template: CharacterState) -> CharacterState:
	if template == null:
		return null

	var state := template.duplicate(true) as CharacterState
	if state == null:
		return null

	state.ensure_initialized()
	state.reset_class_resources()
	state.current_health = state.get_max_health()
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

	phase = Phase.BATTLE
	turn_flow_state = TurnFlowState.IDLE
	_rebuild_turn_order()
	_emit_log("战斗开始。")
	current_turn_index = -1
	advance_turn()
	return true


func advance_turn() -> void:
	if phase != Phase.BATTLE or turn_flow_state != TurnFlowState.IDLE:
		return

	if _check_battle_end():
		return

	if turn_order.is_empty():
		_rebuild_turn_order()

	for _i in range(turn_order.size()):
		current_turn_index = (current_turn_index + 1) % turn_order.size()
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

	_check_battle_end()


func end_current_turn() -> void:
	if is_resolving_actions() or resolution_state_notification_active:
		return
	_request_turn_end(current_unit)


func _request_turn_end(unit: BattleUnitState) -> void:
	if phase != Phase.BATTLE or unit == null or current_unit != unit or turn_flow_state != TurnFlowState.ACTIVE:
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

	unit.start_turn(config)
	for battle_unit in units:
		if battle_unit != null:
			battle_unit.remove_expired_statuses()
	_queue_unit_status_effects("on_turn_start", unit)
	_queue_global_effects("on_turn_start", unit)
	unit.notify_equipment_turn_start({"controller": self, "phase": "turn_start"})


func _finish_turn_start_action(unit: BattleUnitState) -> void:
	if phase != Phase.BATTLE:
		turn_flow_state = TurnFlowState.IDLE
		return
	if unit == null or current_unit != unit or not unit.is_alive():
		turn_flow_state = TurnFlowState.IDLE
		advance_turn()
		return

	unit.remove_expired_statuses()
	turn_flow_state = TurnFlowState.ACTIVE
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
	unit.notify_equipment_turn_end({"controller": self, "phase": "turn_end"})
	enqueue_effect(
		Callable(unit, "exile_expiring_temporary_cards"),
		[self],
		-100,
		"回合结束临时牌放逐",
		{"controller": self, "unit": unit, "phase": "turn_end"}
	)


func _finish_turn_end_action(unit: BattleUnitState) -> void:
	if current_unit == unit:
		turn_flow_state = TurnFlowState.IDLE
	if phase == Phase.BATTLE and current_unit == unit:
		advance_turn()


func move_current_unit_to_cell(cell: Vector2i) -> bool:
	return move_unit_to_cell(current_unit, cell)


func move_unit_to_cell(unit: BattleUnitState, cell: Vector2i) -> bool:
	if not _can_submit_turn_action(unit, "移动"):
		return false

	if not _is_cell_valid_for_unit(unit, cell, false):
		return false

	var distance := map_data.get_distance(unit.cell, cell)
	var ap_cost := unit.get_move_ap_cost(distance, config)
	if distance <= 0:
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
	if not _is_cell_valid_for_unit(unit, cell, false):
		return

	var distance := map_data.get_distance(unit.cell, cell)
	if distance <= 0:
		return

	var ap_cost := unit.get_move_ap_cost(distance, config)
	if unit.current_ap < ap_cost:
		_emit_log("%s AP不足，移动需要 %d AP。" % [unit.get_display_name(), ap_cost])
		return

	unit.current_ap -= ap_cost
	unit.notify_move_ap_cost_paid({
		"controller": self,
		"cell": cell,
		"distance": distance,
		"ap_cost": ap_cost,
	})
	unit.set_hex_cell(cell, map_data)
	_emit_log("%s 移动到格 (%d, %d)，消耗 %d AP。" % [unit.get_display_name(), unit.cell.x, unit.cell.y, ap_cost])
	state_changed.emit()


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


func _build_card_play_context(user: BattleUnitState, card: CardData, targets: Array, strike_context: Dictionary, play_mode: int, write_log: bool, allow_during_resolution: bool = false) -> CardPlayContext:
	if card == null or not _can_submit_turn_action(user, "出牌", write_log, allow_during_resolution):
		if write_log:
			if card == null:
				_emit_log("没有可打出的卡牌。")
		return null
	if not allow_during_resolution and cards_in_flight.has(card.get_instance_id()):
		if write_log:
			_emit_log("%s 已在结算队列中。" % card.card_name)
		return null

	if not _card_source_is_valid(user, card, play_mode, write_log):
		return null
	if not card.supports_play_mode(play_mode):
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
	}

	var condition_context := _build_special_play_condition_context(user, card, play_mode)
	condition_context["druid_orientation"] = druid_orientation
	if not card.can_pay_special_conditions(condition_context, play_mode):
		if write_log:
			_emit_log("%s 的%s条件不足：%s。" % [card.card_name, CardEnums.play_mode_label(play_mode), card.get_special_condition_text(play_mode)])
		return null

	var effective_ap_cost := get_card_ap_cost_for_mode(user, card, play_mode, card_context_seed)
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
	condition_context["druid_orientation"] = druid_orientation

	var payment_snapshot := _snapshot_card_payment_state(frame.user)
	var payment_queue_size := resolution_runner.get_current_effect_queue_size()
	frame.user.current_ap -= effective_ap_cost
	if not _try_pay_druid_resonance(frame.user, frame.card, refreshed_context):
		_rollback_card_payment(frame.user, payment_snapshot, payment_queue_size)
		return
	if not frame.card.pay_special_conditions(condition_context, play_mode):
		_rollback_card_payment(frame.user, payment_snapshot, payment_queue_size)
		_emit_log("%s 的%s条件支付失败。" % [frame.card.card_name, CardEnums.play_mode_label(play_mode)])
		return

	if play_mode == CardEnums.CardPlayMode.MOMENTUM:
		if not frame.user.banish_discard_card(frame.card):
			_rollback_card_payment(frame.user, payment_snapshot, payment_queue_size)
			_emit_log("%s 不在弃牌堆，无法余势打出。" % frame.card.card_name)
			return
		frame.discard_after_play = false
		_emit_log("%s 放逐弃牌堆中的 %s。" % [frame.user.get_display_name(), frame.card.card_name])

	frame.user.notify_card_ap_cost_paid(frame.card, {
		"controller": self,
		"card": frame.card,
		"ap_cost": effective_ap_cost,
		"play_mode": play_mode,
		"druid_orientation": druid_orientation,
	})
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
	frame.card.play(context_dict, frame.targets)


func _finish_card_play_frame(frame: BattleCardFrame) -> void:
	if frame == null or frame.card == null:
		return
	cards_in_flight.erase(frame.card.get_instance_id())
	if not frame.resolved_successfully or frame.user == null:
		return

	if frame.discard_after_play:
		if should_card_exile_after_play(frame):
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
	_emit_log("%s 打出 %s，消耗 %d AP。" % [frame.user.get_display_name(), frame.card.card_name, actual_ap_cost])
	state_changed.emit()
	_check_battle_end()


func _snapshot_card_payment_state(user: BattleUnitState) -> Dictionary:
	if user == null:
		return {}

	var snapshot := {
		"current_ap": user.current_ap,
		"current_health": user.get_current_health(),
		"hand": user.hand.duplicate(),
		"discard_pile": user.discard_pile.duplicate(),
		"exiled_pile": user.exiled_pile.duplicate(),
		"mana_zone": user.mana_zone.duplicate(),
		"enchant_zone": user.enchant_zone.duplicate(),
		"curse_zone": user.curse_zone.duplicate(),
		"card_runtime_states": user.card_runtime_states.duplicate(true),
		"equipment_runtime_states": user.snapshot_equipment_runtime_states(),
		"pending_next_card_damage_bonus": user.pending_next_card_damage_bonus,
		"active_card_damage_bonuses": user.active_card_damage_bonuses.duplicate(true),
		"statuses": _duplicate_resources(user.statuses),
		"druid_transformed": user.druid_transformed,
		"druid_prepare_used": user.druid_prepare_used,
		"druid_temporary_mana": user.druid_temporary_mana,
	}
	if user.character_state != null:
		snapshot["class_resources"] = _duplicate_resources(user.character_state.class_resources)
		snapshot["inventory"] = _duplicate_resources(user.character_state.inventory)
		snapshot["weapon_equipment"] = user.character_state.weapon_equipment
		snapshot["weapon_face"] = user.character_state.weapon_face
		snapshot["armor_equipment"] = user.character_state.armor_equipment
		snapshot["accessory_equipment_1"] = user.character_state.accessory_equipment_1
		snapshot["accessory_equipment_2"] = user.character_state.accessory_equipment_2
	return snapshot


func _restore_card_payment_state(user: BattleUnitState, snapshot: Dictionary) -> void:
	if user == null or snapshot.is_empty():
		return

	user.current_ap = int(snapshot.get("current_ap", user.current_ap))
	user.set_current_health(int(snapshot.get("current_health", user.get_current_health())))

	var hand_snapshot: Array = snapshot.get("hand", []) as Array
	var discard_snapshot: Array = snapshot.get("discard_pile", []) as Array
	var exile_snapshot: Array = snapshot.get("exiled_pile", []) as Array
	var mana_snapshot: Array = snapshot.get("mana_zone", []) as Array
	var enchant_snapshot: Array = snapshot.get("enchant_zone", []) as Array
	var curse_snapshot: Array = snapshot.get("curse_zone", []) as Array
	var runtime_snapshot: Dictionary = snapshot.get("card_runtime_states", {}) as Dictionary
	user.hand.assign(hand_snapshot)
	user.discard_pile.assign(discard_snapshot)
	user.exiled_pile.assign(exile_snapshot)
	user.mana_zone.assign(mana_snapshot)
	user.enchant_zone.assign(enchant_snapshot)
	user.curse_zone.assign(curse_snapshot)
	user.card_runtime_states = runtime_snapshot.duplicate(true)
	user.restore_equipment_runtime_states(snapshot.get("equipment_runtime_states", {}) as Dictionary)
	user.pending_next_card_damage_bonus = int(snapshot.get("pending_next_card_damage_bonus", 0))
	user.active_card_damage_bonuses = (snapshot.get("active_card_damage_bonuses", {}) as Dictionary).duplicate(true)
	var status_snapshot: Array = snapshot.get("statuses", []) as Array
	user.statuses.assign(status_snapshot)
	user.druid_transformed = bool(snapshot.get("druid_transformed", user.druid_transformed))
	user.druid_prepare_used = bool(snapshot.get("druid_prepare_used", user.druid_prepare_used))
	user.druid_temporary_mana = int(snapshot.get("druid_temporary_mana", user.druid_temporary_mana))
	if user.character_state != null:
		var resource_snapshot: Array = snapshot.get("class_resources", []) as Array
		var inventory_snapshot: Array = snapshot.get("inventory", []) as Array
		user.character_state.class_resources.assign(resource_snapshot)
		user.character_state.inventory.assign(inventory_snapshot)
		user.character_state.weapon_equipment = snapshot.get("weapon_equipment") as EquipmentData
		user.character_state.weapon_face = int(snapshot.get("weapon_face", user.character_state.weapon_face))
		user.character_state.armor_equipment = snapshot.get("armor_equipment") as EquipmentData
		user.character_state.accessory_equipment_1 = snapshot.get("accessory_equipment_1") as EquipmentData
		user.character_state.accessory_equipment_2 = snapshot.get("accessory_equipment_2") as EquipmentData


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

	if attacker.current_ap < config.basic_attack_ap_cost:
		_emit_log("%s AP不足，普通攻击需要 %d AP。" % [attacker.get_display_name(), config.basic_attack_ap_cost])
		return false

	var attack_range := attacker.get_attack_range(equipment_slot)
	var distance := attacker.cell_distance_to(target)
	if distance > attack_range:
		_emit_log("距离 %.0f 超出 %s 的攻击距离 %.0f。" % [distance, attacker.get_display_name(), attack_range])
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
	if attacker.current_ap < config.basic_attack_ap_cost:
		_emit_log("%s AP不足，普通攻击需要 %d AP。" % [attacker.get_display_name(), config.basic_attack_ap_cost])
		return

	var attack_range := attacker.get_attack_range(equipment_slot)
	var distance := attacker.cell_distance_to(target)
	if distance > attack_range:
		_emit_log("距离 %.0f 超出 %s 的攻击距离 %.0f。" % [distance, attacker.get_display_name(), attack_range])
		return

	attacker.current_ap -= config.basic_attack_ap_cost
	perform_strike(attacker, target, null, "普通攻击", equipment_slot)
	state_changed.emit()
	_check_battle_end()


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
	return user.get_card_ap_cost(card, cost_context)


func get_card_ap_cost_for_mode(user: BattleUnitState, card: CardData, play_mode: int, context: Dictionary = {}) -> int:
	if play_mode == CardEnums.CardPlayMode.NORMAL:
		return get_card_ap_cost(user, card, context)

	return 0


func can_play_card_with_mode(user: BattleUnitState, card: CardData, play_mode: int) -> bool:
	if card == null or not _can_submit_turn_action(user, "出牌", false):
		return false
	if not _card_source_is_valid(user, card, play_mode, false):
		return false
	if not card.supports_play_mode(play_mode):
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


func _card_source_is_valid(user: BattleUnitState, card: CardData, play_mode: int, write_log: bool) -> bool:
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

	var distance := map_data.get_distance(unit.cell, cell)
	var ap_cost := unit.get_move_ap_cost(distance, config) if apply_ap_cost_modifiers else ceili(float(distance) / float(unit.get_move_distance_per_ap(config)))
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

	var distance := map_data.get_distance(unit.cell, cell)
	if distance > max_distance:
		if write_log:
			_emit_log("%s 无法移动到目标位置，距离 %.0f 超出可移动距离 %.0f。" % [
				unit.get_display_name(),
				distance,
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

	return maxi(0, ap_budget) * unit.get_move_distance_per_ap(config, agility_modifier)


func get_reachable_cells(unit: BattleUnitState, ap_budget: int = -1) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if unit == null or map_data == null or not map_data.is_valid_cell(unit.cell):
		return result
	var available_ap := unit.current_ap if ap_budget < 0 else ap_budget
	for cell in map_data.get_all_cells():
		var distance := map_data.get_distance(unit.cell, cell)
		if unit.get_move_ap_cost(distance, config) > available_ap:
			continue
		if cell != unit.cell and not targeting.is_unit_cell_clear(unit, cell, false):
			continue
		result.append(cell)
	return result


func apply_card_movement_to_cell(unit: BattleUnitState, cell: Vector2i, label: String = "卡牌移动") -> bool:
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return false
	if not _is_cell_valid_for_unit(unit, cell, false):
		return false

	unit.set_hex_cell(cell, map_data)
	_emit_log("%s 移动到格 (%d, %d)（%s）。" % [unit.get_display_name(), unit.cell.x, unit.cell.y, label])
	state_changed.emit()
	return true


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
	var end_position := map_data.cell_to_map(end_cell)
	if not map_data.is_valid_cell(end_cell) or not targeting.is_unit_cell_clear(unit, end_cell, true):
		return result

	unit.set_hex_cell(end_cell, map_data)
	result["success"] = true
	result["end_cell"] = end_cell
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
	_emit_equipment_switch_started(before_context)

	result = unit.character_state.switch_equipment_from_inventory(preferred_equipment)
	result["controller"] = self
	result["unit"] = unit
	if not bool(result.get("success", false)):
		_emit_log("%s 没有可切换的背包武器。" % unit.get_display_name())
		return result

	var old_equipment = result.get("old_equipment")
	var new_equipment = result.get("new_equipment")
	var switch_context := {
		"controller": self,
		"switch_result": result,
		"action_id": get_current_action_id(),
	}
	if old_equipment != null:
		unit.notify_equipment_before_switch_out(old_equipment, int(result.get("old_face", 0)), switch_context)
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

	_emit_log("%s 切换装备：%s 装备到%s。" % [
		unit.get_display_name(),
		new_equipment.item_name,
		_equipment_slot_label(str(result.get("slot", ""))),
	])
	state_changed.emit()
	return result


func can_switch_weapon_from_inventory(unit: BattleUnitState) -> bool:
	return _find_inventory_weapon(unit) != null


func switch_weapon_from_inventory(unit: BattleUnitState) -> Dictionary:
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


func can_activate_equipment_action(unit: BattleUnitState, effect: EquipmentEffect) -> bool:
	if phase != Phase.BATTLE or turn_flow_state != TurnFlowState.ACTIVE or unit == null or current_unit != unit:
		return false
	if is_resolving_actions() or resolution_state_notification_active or not unit.is_equipment_action_active(effect):
		return false
	var context := {"controller": self, "unit": unit}
	for action in unit.get_equipment_actions(context):
		if action.get("effect") != effect:
			continue
		var cost := int(action.get("momentum_cost", 0))
		return bool(action.get("enabled", false)) and unit.get_class_resource_value(WARRIOR_MOMENTUM_RESOURCE) >= cost
	return false


func activate_equipment_action(unit: BattleUnitState, effect: EquipmentEffect) -> bool:
	if not can_activate_equipment_action(unit, effect):
		return false
	return push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_equipment_action"),
		[unit, effect],
		0,
		"%s 使用武器行动" % unit.get_display_name(),
		{"unit": unit, "equipment_effect": effect}
	))


func _resolve_equipment_action(unit: BattleUnitState, effect: EquipmentEffect) -> void:
	if unit == null or effect == null or not unit.is_equipment_action_active(effect):
		return
	var context := {"controller": self, "unit": unit, "action_id": get_current_action_id()}
	for action in unit.get_equipment_actions(context):
		if action.get("effect") != effect:
			continue
		var cost := int(action.get("momentum_cost", 0))
		if not bool(action.get("enabled", false)):
			return
		if cost > 0 and not unit.consume_class_resource(WARRIOR_MOMENTUM_RESOURCE, cost):
			return
		if effect.activate(unit, action.get("root") as EquipmentData, action.get("component") as EquipmentData, action.get("runtime") as EquipmentRuntimeState, context):
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
	if unit.hand.is_empty():
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
	unit.set_druid_transformed(true)
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

	unit.set_druid_transformed(false)
	unit.druid_prepare_used = true
	_emit_log("%s 支付 1 点法力，解除变身状态。" % unit.get_display_name())
	state_changed.emit()


func should_card_enter_mana_after_play(frame: BattleCardFrame) -> bool:
	if frame == null or frame.user == null or frame.card == null:
		return false
	if not frame.user.is_druid() or not frame.card.is_druid_dual_card:
		return false
	if frame.context != null and bool(frame.context.extra.get("druid_send_to_mana_after_play", false)):
		return true
	if frame.context != null:
		var orientation := int(frame.context.extra.get("druid_orientation", _get_druid_orientation_for_card(frame.user, frame.card)))
		return orientation == CardEnums.DruidOrientation.INVERTED

	return frame.user.get_druid_card_orientation(frame.card) == CardEnums.DruidOrientation.INVERTED


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
	if card.resonance_cost <= 0 or not card.auto_pay_resonance:
		return true
	if not user.is_druid():
		return true
	if not user.can_pay_mana(card.resonance_cost):
		context.extra["druid_resonance_paid"] = false
		return true
	if not user.pay_mana(card.resonance_cost):
		_emit_log("%s 共鸣支付失败。" % card.card_name)
		return false

	context.extra["druid_resonance_paid"] = true
	_emit_log("%s 支付 %d 点法力触发共鸣。" % [user.get_display_name(), card.resonance_cost])
	return true


func gain_class_resource(unit: BattleUnitState, resource_name: String, amount: int) -> void:
	if unit == null or resource_name.is_empty() or amount <= 0:
		return

	var gained := unit.gain_class_resource(resource_name, amount)
	if gained > 0:
		_emit_log("%s 获得 %d 点%s。" % [unit.get_display_name(), gained, resource_name])
	state_changed.emit()


func grant_next_attack_card_free(unit: BattleUnitState, stacks: int = 1) -> void:
	if unit == null or stacks <= 0:
		return

	var status := NextAttackCardFreeStatus.new()
	status.stacks = stacks
	unit.add_status(status)
	_emit_log("%s 的下一张攻击牌消耗变为 0。" % unit.get_display_name())
	state_changed.emit()


func apply_damage(source: BattleUnitState, target: BattleUnitState, amount: int, label: String = "伤害") -> int:
	if target == null or not target.is_alive():
		return 0
	if amount <= 0:
		return 0

	var damage_context := DamageContext.create(self, source, target, amount, label)
	damage_context.metadata["action_id"] = get_current_action_id()
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
		damage_context.reduce_amount(reduction)
		if damage_context.prevented:
			return 0
	_process_before_damage(target, damage_context)
	if damage_context.prevented:
		return 0

	var actual := target.apply_damage(damage_context.amount)
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
	if source != null and actual > 0:
		source.notify_after_damage_dealt(event_context)
	if actual > 0:
		target.notify_after_damage_taken(event_context)
	return actual


func heal_unit(source: BattleUnitState, target: BattleUnitState, amount: int, label: String = "治疗") -> int:
	if target == null or not target.is_alive() or amount <= 0:
		return 0

	var before := target.get_current_health()
	target.set_current_health(before + amount)
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
		if unit.cell == selected_cell:
			return unit

	return null


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

		var distance := user.cell_distance_to(target)
		var card_range := card.get_effective_range(user, equipment_slot)
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


func _is_spawn_cell_valid(cell: Vector2i) -> bool:
	if not map_data.is_valid_cell(cell):
		return false

	return targeting.is_unit_cell_clear(null, cell, false)


func _rebuild_turn_order() -> void:
	turn_order.clear()
	for unit in units:
		if unit.is_alive():
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
	if players_alive:
		_emit_log("战斗胜利。")
	else:
		_emit_log("战斗失败。")
	state_changed.emit()
	return true


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
