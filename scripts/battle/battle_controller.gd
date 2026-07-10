extends RefCounted
class_name BattleController

signal log_message(message: String)
signal state_changed
signal basic_attack_triggered(context: Dictionary)
signal equipment_switch_started(context: Dictionary)
signal equipment_switched_out(context: Dictionary)
signal equipment_switched_in(context: Dictionary)

const DRUID_PREPARE_TRANSFORM_ACTION := "druid_prepare_transform"
const DRUID_PREPARE_UNTRANSFORM_ACTION := "druid_prepare_untransform"
const WARRIOR_MOMENTUM_RESOURCE := "势"

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
var class_resource_actions_used := {}
var action_resolution_lock_count: int = 0
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
		unit.setup_player(id, character_state, config.default_unit_radius)
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
		var spawn_position := _find_enemy_spawn_position(enemy_state)
		var unit := BattleUnitState.new()
		unit.setup_enemy(id, enemy_state, config.default_unit_radius, spawn_position)
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
	class_resource_actions_used.clear()
	action_resolution_lock_count = 0


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


func deploy_player_unit(unit: BattleUnitState, position: Vector2) -> bool:
	if is_resolving_actions():
		return false
	if phase != Phase.DEPLOYMENT:
		_emit_log("当前不是部署阶段。")
		return false

	if unit == null or unit.faction != BattleUnitState.Faction.PLAYER:
		_emit_log("只能部署玩家单位。")
		return false

	if not _is_position_valid_for_unit(unit, position, true):
		return false

	unit.position = position
	unit.is_deployed = true
	_emit_log("%s 部署到 (%.0f, %.0f)。" % [unit.get_display_name(), position.x, position.y])
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
	_rebuild_turn_order()
	_emit_log("战斗开始。")
	current_turn_index = -1
	advance_turn()
	return true


func advance_turn() -> void:
	if phase != Phase.BATTLE:
		return

	if _check_battle_end():
		return

	if turn_order.is_empty():
		_rebuild_turn_order()

	for _i in range(turn_order.size()):
		current_turn_index = (current_turn_index + 1) % turn_order.size()
		current_unit = turn_order[current_turn_index]
		if current_unit.is_alive():
			push_action_frame(BattleActionFrame.create(
				Callable(self, "_resolve_turn_start_action"),
				[current_unit],
				0,
				"%s 回合开始" % current_unit.get_display_name(),
				{"unit": current_unit, "phase": "turn_start"},
				Callable(self, "_finish_turn_start_action"),
				[current_unit]
			))
			return

	_check_battle_end()


func end_current_turn() -> void:
	if phase != Phase.BATTLE or current_unit == null:
		return

	var unit := current_unit
	push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_turn_end_action"),
		[unit],
		0,
		"%s 回合结束" % unit.get_display_name(),
		{"unit": unit, "phase": "turn_end"},
		Callable(self, "_finish_turn_end_action"),
		[unit]
	))


func _resolve_turn_start_action(unit: BattleUnitState) -> void:
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return

	unit.start_turn(config)
	class_resource_actions_used.erase(unit.unit_id)
	for battle_unit in units:
		if battle_unit != null:
			battle_unit.remove_expired_statuses()
	_queue_unit_status_effects("on_turn_start", unit)
	_queue_global_effects("on_turn_start", unit)


func _finish_turn_start_action(unit: BattleUnitState) -> void:
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return

	unit.remove_expired_statuses()
	_emit_log("轮到 %s，AP：%d。" % [unit.get_display_name(), unit.current_ap])
	state_changed.emit()
	if current_unit == unit and unit.faction == BattleUnitState.Faction.ENEMY:
		_run_enemy_turn(unit)


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
		Callable(unit, "exile_expiring_temporary_cards"),
		[self],
		-100,
		"回合结束临时牌放逐",
		{"controller": self, "unit": unit, "phase": "turn_end"}
	)


func _finish_turn_end_action(unit: BattleUnitState) -> void:
	if phase == Phase.BATTLE and current_unit == unit:
		advance_turn()


func move_current_unit_to(position: Vector2) -> bool:
	return move_unit_to(current_unit, position)


func move_unit_to(unit: BattleUnitState, position: Vector2) -> bool:
	if phase != Phase.BATTLE:
		_emit_log("战斗尚未开始。")
		return false

	if unit == null or not unit.is_alive():
		_emit_log("没有可移动的单位。")
		return false

	if not _is_position_valid_for_unit(unit, position, false):
		return false

	var distance := unit.position.distance_to(position)
	var ap_cost := unit.get_move_ap_cost(distance, config)
	if distance <= 0.001:
		return true

	if unit.current_ap < ap_cost:
		_emit_log("%s AP不足，移动需要 %d AP。" % [unit.get_display_name(), ap_cost])
		return false

	push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_direct_move_action"),
		[unit, position],
		0,
		"%s 直接移动" % unit.get_display_name(),
		{"unit": unit, "position": position, "ap_cost": ap_cost}
	))
	return true


func _resolve_direct_move_action(unit: BattleUnitState, position: Vector2) -> void:
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return
	if not _is_position_valid_for_unit(unit, position, false):
		return

	var distance := unit.position.distance_to(position)
	if distance <= 0.001:
		return

	var ap_cost := unit.get_move_ap_cost(distance, config)
	if unit.current_ap < ap_cost:
		_emit_log("%s AP不足，移动需要 %d AP。" % [unit.get_display_name(), ap_cost])
		return

	unit.current_ap -= ap_cost
	unit.notify_move_ap_cost_paid({
		"controller": self,
		"position": position,
		"distance": distance,
		"ap_cost": ap_cost,
	})
	unit.position = position
	_emit_log("%s 移动到 (%.0f, %.0f)，消耗 %d AP。" % [unit.get_display_name(), position.x, position.y, ap_cost])
	state_changed.emit()


func play_card(user: BattleUnitState, card: CardData, targets: Array, strike_context: Dictionary = {}, play_mode: int = CardEnums.CardPlayMode.NORMAL) -> bool:
	if phase != Phase.BATTLE:
		_emit_log("战斗尚未开始。")
		return false

	if user == null or card == null or not user.is_alive():
		_emit_log("没有可打出的卡牌。")
		return false

	if not _card_source_is_valid(user, card, play_mode, true):
		return false
	if not card.supports_play_mode(play_mode):
		_emit_log("%s 不能以%s方式打出。" % [card.card_name, CardEnums.play_mode_label(play_mode)])
		return false
	if not _is_druid_card_play_state_valid(user, card, true):
		return false

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
		_emit_log("%s 的%s条件不足：%s。" % [card.card_name, CardEnums.play_mode_label(play_mode), card.get_special_condition_text(play_mode)])
		return false

	var effective_ap_cost := get_card_ap_cost_for_mode(user, card, play_mode, card_context_seed)
	if user.current_ap < effective_ap_cost:
		_emit_log("%s AP不足，%s 需要 %d AP。" % [user.get_display_name(), card.card_name, effective_ap_cost])
		return false

	var equipment_slot := str(strike_context.get("equipment_slot", ""))
	var target_context := strike_context.duplicate()
	target_context["druid_orientation"] = druid_orientation
	if not _targets_are_valid(user, card, targets, true, equipment_slot, play_mode, target_context):
		return false

	var extra_context := strike_context.duplicate()
	extra_context.erase("equipment_slot")
	extra_context["actual_ap_cost"] = effective_ap_cost
	extra_context["play_mode"] = play_mode
	extra_context["druid_orientation"] = druid_orientation
	var context := CardPlayContext.create(self, user, card, equipment_slot, extra_context, play_mode)
	var context_dict := context.to_dict()
	if not card.can_play(context_dict):
		_emit_log("%s 当前不能打出。" % card.card_name)
		return false

	if resolution_runner.effect_limit_reached:
		_emit_log("%s 未加入结算：当前主要行动效果结算已达到上限。" % card.card_name)
		return false

	var payment_snapshot := _snapshot_card_payment_state(user)
	user.current_ap -= effective_ap_cost
	if not _try_pay_druid_resonance(user, card, context):
		_restore_card_payment_state(user, payment_snapshot)
		return false
	if not card.pay_special_conditions(condition_context, play_mode):
		_restore_card_payment_state(user, payment_snapshot)
		_emit_log("%s 的%s条件支付失败。" % [card.card_name, CardEnums.play_mode_label(play_mode)])
		return false

	var discard_after_play := true
	if play_mode == CardEnums.CardPlayMode.MOMENTUM:
		if not user.banish_discard_card(card):
			_restore_card_payment_state(user, payment_snapshot)
			_emit_log("%s 不在弃牌堆，无法余势打出。" % card.card_name)
			return false
		discard_after_play = false
		_emit_log("%s 放逐弃牌堆中的 %s。" % [user.get_display_name(), card.card_name])

	if play_mode == CardEnums.CardPlayMode.NORMAL:
		user.notify_card_ap_cost_paid(card, {
			"controller": self,
			"card": card,
			"ap_cost": effective_ap_cost,
			"druid_orientation": druid_orientation,
		})

	resolution_runner.push_card_frame(BattleCardFrame.create(user, card, targets, context, discard_after_play))
	return true


func _snapshot_card_payment_state(user: BattleUnitState) -> Dictionary:
	if user == null:
		return {}

	return {
		"current_ap": user.current_ap,
		"current_health": user.get_current_health(),
		"hand": user.hand.duplicate(),
		"discard_pile": user.discard_pile.duplicate(),
		"exiled_pile": user.exiled_pile.duplicate(),
		"mana_zone": user.mana_zone.duplicate(),
		"enchant_zone": user.enchant_zone.duplicate(),
		"curse_zone": user.curse_zone.duplicate(),
		"card_runtime_states": user.card_runtime_states.duplicate(true),
		"druid_transformed": user.druid_transformed,
		"druid_prepare_used": user.druid_prepare_used,
		"druid_temporary_mana": user.druid_temporary_mana,
	}


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
	user.druid_transformed = bool(snapshot.get("druid_transformed", user.druid_transformed))
	user.druid_prepare_used = bool(snapshot.get("druid_prepare_used", user.druid_prepare_used))
	user.druid_temporary_mana = int(snapshot.get("druid_temporary_mana", user.druid_temporary_mana))


func basic_attack(attacker: BattleUnitState, target: BattleUnitState, equipment_slot: String = "") -> bool:
	if phase != Phase.BATTLE:
		return false

	if attacker == null or target == null or not attacker.is_alive() or not target.is_alive():
		_emit_log("攻击目标无效。")
		return false

	if attacker.current_ap < config.basic_attack_ap_cost:
		_emit_log("%s AP不足，普通攻击需要 %d AP。" % [attacker.get_display_name(), config.basic_attack_ap_cost])
		return false

	var attack_range := attacker.get_attack_range(equipment_slot)
	var distance := attacker.distance_to(target)
	if distance > attack_range:
		_emit_log("距离 %.0f 超出 %s 的攻击距离 %.0f。" % [distance, attacker.get_display_name(), attack_range])
		return false

	push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_basic_attack_action"),
		[attacker, target, equipment_slot],
		0,
		"%s 普通攻击" % attacker.get_display_name(),
		{"attacker": attacker, "target": target, "equipment_slot": equipment_slot}
	))
	return true


func _resolve_basic_attack_action(attacker: BattleUnitState, target: BattleUnitState, equipment_slot: String = "") -> void:
	if phase != Phase.BATTLE:
		return
	if attacker == null or target == null or not attacker.is_alive() or not target.is_alive():
		_emit_log("攻击目标无效。")
		return
	if attacker.current_ap < config.basic_attack_ap_cost:
		_emit_log("%s AP不足，普通攻击需要 %d AP。" % [attacker.get_display_name(), config.basic_attack_ap_cost])
		return

	var attack_range := attacker.get_attack_range(equipment_slot)
	var distance := attacker.distance_to(target)
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
	if phase != Phase.BATTLE or user == null or card == null or not user.is_alive():
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

	return card.can_pay_special_conditions(_build_special_play_condition_context(user, card, play_mode), play_mode)


func can_preview_card_targets(user: BattleUnitState, card: CardData, targets: Array, equipment_slot: String = "", play_mode: int = CardEnums.CardPlayMode.NORMAL, extra_context: Dictionary = {}) -> bool:
	if phase != Phase.BATTLE or user == null or card == null or not user.is_alive():
		return false

	return _targets_are_valid(user, card, targets, false, equipment_slot, play_mode, extra_context)


func can_activate_exiled_card(user: BattleUnitState, card: CardData) -> bool:
	if phase != Phase.BATTLE or is_resolving_actions():
		return false
	if user == null or card == null or not user.is_alive():
		return false
	if current_unit != user or user.faction != BattleUnitState.Faction.PLAYER:
		return false
	if not user.has_card_in_exile(card):
		return false

	return card.can_activate_from_exile(_build_exiled_card_action_context(user, card))


func can_activate_enchant_card(user: BattleUnitState, card: CardData) -> bool:
	if phase != Phase.BATTLE or is_resolving_actions():
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

	push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_exiled_card_action"),
		[user, card],
		0,
		"%s 发动放逐区卡牌" % user.get_display_name(),
		_build_exiled_card_action_context(user, card)
	))
	return true


func activate_enchant_card(user: BattleUnitState, card: CardData) -> bool:
	if not can_activate_enchant_card(user, card):
		_emit_log("当前无法发动这张附魔区卡牌。")
		return false

	push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_enchant_card_action"),
		[user, card],
		0,
		"%s 发动附魔区卡牌" % user.get_display_name(),
		_build_enchant_card_action_context(user, card)
	))
	return true


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


func can_unit_reach_position_with_ap(unit: BattleUnitState, position: Vector2, max_ap: int = 1, write_log: bool = false) -> bool:
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return false
	if not _is_position_valid_for_unit(unit, position, false, write_log):
		return false

	var distance := unit.position.distance_to(position)
	var ap_cost := unit.get_move_ap_cost(distance, config)
	if ap_cost > max_ap:
		if write_log:
			_emit_log("%s 无法以 %d AP 移动到目标位置。" % [unit.get_display_name(), max_ap])
		return false

	return true


func can_unit_reach_position_with_ap_and_agility_modifier(unit: BattleUnitState, position: Vector2, max_ap: int = 1, agility_modifier: int = 0, write_log: bool = false) -> bool:
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return false

	var max_distance := get_ap_movement_distance(unit, max_ap, agility_modifier)
	return can_unit_reach_position_with_distance(unit, position, max_distance, write_log)


func can_unit_reach_position_with_agility_modifier(unit: BattleUnitState, position: Vector2, agility_modifier: int = 0, write_log: bool = false) -> bool:
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return false

	var max_distance := get_agility_movement_distance(unit, agility_modifier)
	return can_unit_reach_position_with_distance(unit, position, max_distance, write_log)


func can_unit_reach_position_with_distance(unit: BattleUnitState, position: Vector2, max_distance: float, write_log: bool = false) -> bool:
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return false
	if not _is_position_valid_for_unit(unit, position, false, write_log):
		return false

	var distance := unit.position.distance_to(position)
	if distance > max_distance + 0.001:
		if write_log:
			_emit_log("%s 无法移动到目标位置，距离 %.0f 超出可移动距离 %.0f。" % [
				unit.get_display_name(),
				distance,
				max_distance,
			])
		return false

	return true


func get_agility_movement_distance(unit: BattleUnitState, agility_modifier: int = 0) -> float:
	if unit == null:
		return 0.0

	return maxf(0.0, float(unit.get_agility() + agility_modifier) * config.move_distance_per_agility)


func get_ap_movement_distance(unit: BattleUnitState, ap_budget: int, agility_modifier: int = 0) -> float:
	if unit == null:
		return 0.0

	return float(maxi(0, ap_budget)) * unit.get_move_distance_per_ap(config, agility_modifier)


func apply_card_movement_to(unit: BattleUnitState, position: Vector2, label: String = "卡牌移动") -> bool:
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return false
	if not _is_position_valid_for_unit(unit, position, false):
		return false

	unit.position = position
	_emit_log("%s 移动到 (%.0f, %.0f)（%s）。" % [unit.get_display_name(), position.x, position.y, label])
	state_changed.emit()
	return true


func apply_movement_effect(unit: BattleUnitState, target_position: Vector2, agility_modifier: int = 0, truncate_to_range: bool = true, ap_budget: int = -1) -> Dictionary:
	var result := {
		"success": false,
		"start_position": Vector2.ZERO,
		"end_position": Vector2.ZERO,
		"requested_position": target_position,
		"max_distance": 0.0,
	}
	if phase != Phase.BATTLE or unit == null or not unit.is_alive():
		return result

	var start_position := unit.position
	var end_position := target_position
	result["start_position"] = start_position

	if not targeting.is_unit_inside_map_bounds(unit, end_position, false):
		if not truncate_to_range:
			return result
		end_position = clamp_to_map(end_position)

	var max_distance := get_agility_movement_distance(unit, agility_modifier)
	if ap_budget >= 0:
		max_distance = get_ap_movement_distance(unit, ap_budget, agility_modifier)
	result["max_distance"] = max_distance
	var direction := end_position - start_position
	if not truncate_to_range and direction.length() > max_distance + 0.001:
		return result
	if truncate_to_range and direction.length() > max_distance:
		if direction.length() <= 0.001:
			end_position = start_position
		else:
			end_position = start_position + direction.normalized() * max_distance
			end_position = clamp_to_map(end_position)

	end_position = targeting.find_clear_endpoint_along_segment(unit, start_position, end_position)
	if not targeting.is_unit_inside_map_bounds(unit, end_position, true) or not targeting.is_unit_position_clear(unit, end_position, true):
		return result

	unit.position = end_position
	result["success"] = true
	result["end_position"] = end_position
	_emit_log("%s 移动到 (%.0f, %.0f)。" % [unit.get_display_name(), end_position.x, end_position.y])
	state_changed.emit()
	return result


func get_units_by_filter(source: BattleUnitState, filter: int) -> Array[BattleUnitState]:
	return targeting.get_units_by_filter(source, filter)


func get_units_in_swept_circle(source: BattleUnitState, start_position: Vector2, end_position: Vector2, sweep_radius: float, filter: int) -> Array[BattleUnitState]:
	return targeting.get_units_in_swept_circle(source, start_position, end_position, sweep_radius, filter)


func get_units_in_range(source: BattleUnitState, range_distance: float, filter: int) -> Array[BattleUnitState]:
	return targeting.get_units_in_range(source, range_distance, filter)


func get_units_in_attack_range(source: BattleUnitState, range_bonus: float = 0.0, filter: int = UnitFilter.OPPONENTS, equipment_slot: String = "") -> Array[BattleUnitState]:
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
	enqueue_trigger(Callable(self, "_emit_equipment_switch_started"), [before_context], 0, "切换装备时", before_context)

	result = unit.character_state.switch_equipment_from_inventory(preferred_equipment)
	result["controller"] = self
	result["unit"] = unit
	if not bool(result.get("success", false)):
		_emit_log("%s 没有可切换的背包武器。" % unit.get_display_name())
		return result

	var old_equipment = result.get("old_equipment")
	var new_equipment = result.get("new_equipment")
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


func can_use_warrior_momentum(unit: BattleUnitState) -> bool:
	if phase != Phase.BATTLE or unit == null or current_unit != unit:
		return false
	if unit.faction != BattleUnitState.Faction.PLAYER:
		return false
	if unit.get_character_class() != CardEnums.CardClass.WARRIOR:
		return false
	if bool(class_resource_actions_used.get(unit.unit_id, false)):
		return false

	return unit.get_class_resource_value(WARRIOR_MOMENTUM_RESOURCE) > 0


func use_warrior_momentum(unit: BattleUnitState) -> bool:
	if phase != Phase.BATTLE or unit == null or current_unit != unit:
		return false
	if unit.get_character_class() != CardEnums.CardClass.WARRIOR:
		_emit_log("只有战士可以使用势。")
		return false
	if bool(class_resource_actions_used.get(unit.unit_id, false)):
		_emit_log("%s 本回合已经使用过势。" % unit.get_display_name())
		return false
	if unit.get_class_resource_value(WARRIOR_MOMENTUM_RESOURCE) <= 0:
		_emit_log("%s 没有可消耗的势。" % unit.get_display_name())
		return false

	push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_warrior_momentum_action"),
		[unit],
		0,
		"%s 使用势" % unit.get_display_name(),
		{"unit": unit, "resource": WARRIOR_MOMENTUM_RESOURCE}
	))
	return true


func _resolve_warrior_momentum_action(unit: BattleUnitState) -> void:
	if not can_use_warrior_momentum(unit):
		return
	if not unit.consume_class_resource(WARRIOR_MOMENTUM_RESOURCE, 1):
		return

	var status := OneShotDamageBonusStatus.new()
	status.stacks = 1
	status.bonus_amount = 2
	unit.add_status(status)
	class_resource_actions_used[unit.unit_id] = true
	_emit_log("%s 消耗 1 点势，本回合每段伤害获得 +2 伤害加值。" % unit.get_display_name())
	state_changed.emit()


func can_use_druid_prepare_transform(unit: BattleUnitState) -> bool:
	if phase != Phase.BATTLE or unit == null or current_unit != unit:
		return false
	if unit.faction != BattleUnitState.Faction.PLAYER:
		return false
	if not unit.is_druid() or unit.druid_transformed or unit.druid_prepare_used:
		return false
	if unit.hand.is_empty():
		return false

	return true


func use_druid_prepare_transform(unit: BattleUnitState, selected_card: CardData = null) -> bool:
	if is_resolving_actions():
		return false
	if not can_use_druid_prepare_transform(unit):
		return false
	if selected_card != null and not unit.has_card_in_hand(selected_card):
		_emit_log("%s 不在手牌中，无法逆置置入法力区。" % selected_card.card_name)
		return false

	push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_druid_prepare_transform"),
		[unit, selected_card],
		0,
		"%s 准备变身" % unit.get_display_name(),
		{"unit": unit, "selected_card": selected_card}
	))
	return true


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
	if phase != Phase.BATTLE or unit == null or current_unit != unit:
		return false
	if unit.faction != BattleUnitState.Faction.PLAYER:
		return false
	if not unit.is_druid() or not unit.druid_transformed or unit.druid_prepare_used:
		return false
	if not unit.can_pay_mana(1):
		return false

	return true


func use_druid_prepare_untransform(unit: BattleUnitState) -> bool:
	if is_resolving_actions():
		return false
	if not can_use_druid_prepare_untransform(unit):
		return false

	push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_druid_prepare_untransform"),
		[unit],
		0,
		"%s 解除变身" % unit.get_display_name(),
		{"unit": unit}
	))
	return true


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
		var distance := unit.distance_to(other)
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
		if user.current_ap < get_card_ap_cost(user, card):
			continue
		if _targets_are_valid(user, card, [target], false):
			return card

	return null


func get_alive_units() -> Array[BattleUnitState]:
	var result: Array[BattleUnitState] = []
	for unit in units:
		if unit.is_alive():
			result.append(unit)

	return result


func get_unit_at_position(position: Vector2) -> BattleUnitState:
	for unit in units:
		if not unit.is_deployed or not unit.is_alive():
			continue
		if position.distance_to(unit.position) <= unit.radius:
			return unit

	return null


func get_first_undeployed_player() -> BattleUnitState:
	for unit in player_units:
		if not unit.is_deployed:
			return unit

	return null


func _run_enemy_turn(unit: BattleUnitState) -> void:
	if unit.enemy_state == null or unit.enemy_state.enemy_data == null:
		end_current_turn()
		return

	var behavior := unit.enemy_state.enemy_data.behavior
	if behavior == null:
		_emit_log("%s 没有战斗逻辑，结束回合。" % unit.get_display_name())
		end_current_turn()
		return

	behavior.on_turn_start({"controller": self}, unit)
	behavior.choose_action({"controller": self}, unit)
	behavior.on_turn_end({"controller": self}, unit)
	if phase == Phase.BATTLE and current_unit == unit:
		end_current_turn()


func _targets_are_valid(user: BattleUnitState, card: CardData, targets: Array, write_log: bool = true, equipment_slot: String = "", play_mode: int = CardEnums.CardPlayMode.NORMAL, extra_context: Dictionary = {}) -> bool:
	var target_type := _get_card_target_type(user, card, equipment_slot, play_mode, extra_context)
	if target_type == CardEnums.TargetType.NONE:
		return _card_effect_targets_are_valid(user, card, targets, write_log, equipment_slot, play_mode, extra_context)

	if target_type == CardEnums.TargetType.AREA:
		if targets.size() != 1 or not (targets[0] is Vector2):
			if write_log:
				_emit_log("%s 需要一个位置目标。" % card.card_name)
			return false
		if not map_data.contains_map_position(targets[0]):
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

		var distance := user.distance_to(target)
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


func _is_position_valid_for_unit(unit: BattleUnitState, position: Vector2, deployment_only: bool, write_log: bool = true) -> bool:
	if not targeting.is_unit_inside_map_bounds(unit, position, write_log):
		return false

	if deployment_only and not map_data.contains_deployment_position(position):
		if write_log:
			_emit_log("目标位置不在玩家部署区内。")
		return false

	return targeting.is_unit_position_clear(unit, position, write_log)


func _find_enemy_spawn_position(enemy_state: EnemyState) -> Vector2:
	for _i in range(40):
		var position := map_data.random_enemy_spawn_position(rng)
		var fake := BattleUnitState.new()
		fake.setup_enemy(-1, enemy_state, config.default_unit_radius, position)
		if _is_spawn_position_valid(fake, position):
			return position

	return map_data.enemy_spawn_rect.get_center()


func _is_spawn_position_valid(unit: BattleUnitState, position: Vector2) -> bool:
	if not map_data.contains_map_position(position):
		return false

	return targeting.is_unit_position_clear(unit, position, false)


func _rebuild_turn_order() -> void:
	turn_order.clear()
	for unit in units:
		if unit.is_alive():
			turn_order.append(unit)

	turn_order.sort_custom(Callable(self, "_compare_turn_order"))


func clamp_to_map(position: Vector2) -> Vector2:
	if map_data.boundary_points.size() >= 3:
		return _closest_boundary_point(position)

	return Vector2(
		clampf(position.x, 0.0, map_data.map_size.x),
		clampf(position.y, 0.0, map_data.map_size.y)
	)


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
	resolution_runner.enqueue_trigger(callback, args, priority, label, context)


func push_action_frame(frame: BattleActionFrame) -> void:
	resolution_runner.push_action_frame(frame)


func get_current_action_id() -> int:
	return resolution_runner.get_current_action_id()


func is_resolving_actions() -> bool:
	return action_resolution_lock_count > 0


func _begin_action_resolution() -> void:
	action_resolution_lock_count += 1
	if action_resolution_lock_count == 1:
		state_changed.emit()


func _end_action_resolution() -> void:
	action_resolution_lock_count = maxi(0, action_resolution_lock_count - 1)
	if action_resolution_lock_count == 0:
		state_changed.emit()


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
		if effect == null or not effect.has_method(callback_name):
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
		if status == null or not status.has_method(callback_name):
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
	if status == null or unit == null or not status.has_method(callback_name):
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


func _apply_global_effects(callback_name: String, unit: BattleUnitState = null) -> void:
	_queue_global_effects(callback_name, unit)
	resolve_effect_queue()




func _closest_boundary_point(position: Vector2) -> Vector2:
	var closest := position
	var closest_distance := INF
	var point_count := map_data.boundary_points.size()
	for index in range(point_count):
		var start: Vector2 = map_data.boundary_points[index]
		var end: Vector2 = map_data.boundary_points[(index + 1) % point_count]
		var candidate := Geometry2D.get_closest_point_to_segment(position, start, end)
		var distance := position.distance_to(candidate)
		if distance < closest_distance:
			closest = candidate
			closest_distance = distance

	return closest
