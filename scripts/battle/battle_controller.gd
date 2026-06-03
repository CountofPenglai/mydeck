extends RefCounted
class_name BattleController

signal log_message(message: String)
signal state_changed
signal basic_attack_triggered(context: Dictionary)
signal weapon_switch_started(context: Dictionary)
signal weapon_switched_out(context: Dictionary)
signal weapon_switched_in(context: Dictionary)

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
var resolution_runner := BattleResolutionRunner.new()
var targeting := BattleTargeting.new()
var strike_resolver := BattleStrikeResolver.new()

func setup(new_scenario: BattleScenario) -> void:
	scenario = new_scenario
	config = scenario.battle_config
	scene_prototype = scenario.scene_prototype
	map_data = scenario.get_map_data()
	if scene_prototype != null and scene_prototype.scene_texture != null:
		map_data.background_texture = scene_prototype.scene_texture
	rng.seed = scenario.seed
	phase = Phase.DEPLOYMENT
	units.clear()
	player_units.clear()
	enemy_units.clear()
	turn_order.clear()
	current_turn_index = -1
	current_unit = null
	resolution_runner.setup(self)
	targeting.setup(self)
	strike_resolver.setup(self)

	var id := 0
	for character_state in scenario.players:
		if character_state == null:
			continue
		character_state.ensure_initialized()
		character_state.current_health = character_state.get_max_health()
		var unit := BattleUnitState.new()
		unit.setup_player(id, character_state, config.default_unit_radius)
		id += 1
		units.append(unit)
		player_units.append(unit)

	for enemy_state in scenario.get_enemy_states():
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


func deploy_player_unit(unit: BattleUnitState, position: Vector2) -> bool:
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
	for unit in player_units:
		if not unit.is_deployed:
			return false

	return not player_units.is_empty() and not enemy_units.is_empty()


func start_battle() -> bool:
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
			current_unit.start_turn(config)
			_queue_unit_status_effects("on_turn_start", current_unit)
			_queue_global_effects("on_turn_start", current_unit)
			resolve_effect_queue()
			current_unit.remove_expired_statuses()
			_emit_log("轮到 %s，AP：%d。" % [current_unit.get_display_name(), current_unit.current_ap])
			state_changed.emit()
			if current_unit.faction == BattleUnitState.Faction.ENEMY:
				_run_enemy_turn(current_unit)
			return

	_check_battle_end()


func end_current_turn() -> void:
	if phase != Phase.BATTLE or current_unit == null:
		return

	var draw_count := 0
	if config.ap_per_end_turn_draw > 0:
		draw_count = floori(float(current_unit.current_ap) / float(config.ap_per_end_turn_draw))

	if draw_count > 0:
		var drawn := current_unit.draw_cards(draw_count, rng)
		_emit_log("%s 保留 %d AP，抽取 %d 张牌。" % [current_unit.get_display_name(), current_unit.current_ap, drawn])

	current_unit.current_ap = 0
	_queue_global_effects("on_turn_end", current_unit)
	resolve_effect_queue()
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
	var move_per_ap := unit.get_move_distance_per_ap(config)
	var ap_cost := ceili(distance / move_per_ap)
	if ap_cost <= 0:
		return true

	if unit.current_ap < ap_cost:
		_emit_log("%s AP不足，移动需要 %d AP。" % [unit.get_display_name(), ap_cost])
		return false

	unit.current_ap -= ap_cost
	unit.position = position
	_emit_log("%s 移动到 (%.0f, %.0f)，消耗 %d AP。" % [unit.get_display_name(), position.x, position.y, ap_cost])
	state_changed.emit()
	return true


func play_card(user: BattleUnitState, card: CardData, targets: Array, strike_context: Dictionary = {}) -> bool:
	if phase != Phase.BATTLE:
		_emit_log("战斗尚未开始。")
		return false

	if user == null or card == null or not user.is_alive():
		_emit_log("没有可打出的卡牌。")
		return false

	if user.current_ap < card.ap_cost:
		_emit_log("%s AP不足，%s 需要 %d AP。" % [user.get_display_name(), card.card_name, card.ap_cost])
		return false

	var weapon_slot := str(strike_context.get("weapon_slot", ""))
	if not _targets_are_valid(user, card, targets, true, weapon_slot):
		return false

	var extra_context := strike_context.duplicate()
	extra_context.erase("weapon_slot")
	var context := CardPlayContext.create(self, user, card, weapon_slot, extra_context)
	var context_dict := context.to_dict()
	if not card.can_play(context_dict):
		_emit_log("%s 当前不能打出。" % card.card_name)
		return false

	if resolution_runner.effect_limit_reached:
		_emit_log("%s 未加入结算：单张卡牌效果结算已达到上限。" % card.card_name)
		return true

	user.current_ap -= card.ap_cost
	resolution_runner.push_card_frame(BattleCardFrame.create(user, card, targets, context))
	return true


func basic_attack(attacker: BattleUnitState, target: BattleUnitState, weapon_slot: String = "") -> bool:
	if phase != Phase.BATTLE:
		return false

	if attacker == null or target == null or not attacker.is_alive() or not target.is_alive():
		_emit_log("攻击目标无效。")
		return false

	if attacker.current_ap < config.basic_attack_ap_cost:
		_emit_log("%s AP不足，普通攻击需要 %d AP。" % [attacker.get_display_name(), config.basic_attack_ap_cost])
		return false

	var attack_range := attacker.get_attack_range(weapon_slot)
	var distance := attacker.distance_to(target)
	if distance > attack_range:
		_emit_log("距离 %.0f 超出 %s 的攻击距离 %.0f。" % [distance, attacker.get_display_name(), attack_range])
		return false

	attacker.current_ap -= config.basic_attack_ap_cost
	perform_strike(attacker, target, null, "普通攻击", weapon_slot)
	resolve_effect_queue()
	state_changed.emit()
	_check_battle_end()
	return true


func perform_strike(attacker: BattleUnitState, target: BattleUnitState, source = null, label: String = "打击", weapon_slot: String = "") -> int:
	return strike_resolver.perform_strike(attacker, target, source, label, weapon_slot)


func perform_strike_with_modifier(attacker: BattleUnitState, target: BattleUnitState, source = null, damage_modifier: int = 0, label: String = "打击", weapon_slot: String = "") -> int:
	return strike_resolver.perform_strike_with_modifier(attacker, target, source, damage_modifier, label, weapon_slot)


func apply_movement_effect(unit: BattleUnitState, target_position: Vector2, agility_modifier: int = 0, truncate_to_range: bool = true) -> Dictionary:
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

	if not map_data.contains_map_position(end_position):
		end_position = clamp_to_map(end_position)

	var max_distance := maxf(0.0, float(unit.get_agility() + agility_modifier) * config.move_distance_per_agility)
	result["max_distance"] = max_distance
	var direction := end_position - start_position
	if truncate_to_range and direction.length() > max_distance:
		if direction.length() <= 0.001:
			end_position = start_position
		else:
			end_position = start_position + direction.normalized() * max_distance
			end_position = clamp_to_map(end_position)

	end_position = targeting.find_clear_endpoint_along_segment(unit, start_position, end_position)
	if not map_data.contains_map_position(end_position) or not targeting.is_unit_position_clear(unit, end_position, true):
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


func switch_weapon_from_inventory(unit: BattleUnitState, preferred_weapon: WeaponData = null) -> Dictionary:
	var result := {"success": false}
	if unit == null or unit.character_state == null:
		return result

	var before_context := {
		"controller": self,
		"unit": unit,
		"preferred_weapon": preferred_weapon,
	}
	enqueue_trigger(Callable(self, "_emit_weapon_switch_started"), [before_context], 0, "切换武器时", before_context)

	result = unit.character_state.switch_weapon_from_inventory(preferred_weapon)
	result["controller"] = self
	result["unit"] = unit
	if not bool(result.get("success", false)):
		_emit_log("%s 没有可切换的背包武器。" % unit.get_display_name())
		return result

	var old_weapon = result.get("old_weapon")
	var new_weapon = result.get("new_weapon")
	if old_weapon != null:
		enqueue_trigger(Callable(self, "_emit_weapon_switched_out"), [result], 0, "切换掉当前武器", result)
	if new_weapon != null:
		enqueue_trigger(Callable(self, "_emit_weapon_switched_in"), [result], 0, "切换出新的武器", result)

	_emit_log("%s 切换武器：%s 装备到%s。" % [
		unit.get_display_name(),
		new_weapon.item_name,
		"主手" if str(result.get("slot", "")) == "main" else "副手",
	])
	state_changed.emit()
	return result


func apply_damage(source: BattleUnitState, target: BattleUnitState, amount: int, label: String = "伤害") -> int:
	if target == null or not target.is_alive():
		return 0
	if amount <= 0:
		return 0

	var damage_context := DamageContext.create(self, source, target, amount, label)
	_process_before_damage(target, damage_context)
	if damage_context.prevented:
		return 0

	var actual := target.apply_damage(damage_context.amount)
	var source_name := "效果"
	if source != null:
		source_name = source.get_display_name()
	_emit_log("%s 对 %s 造成 %d 点%s。" % [source_name, target.get_display_name(), actual, label])
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
		if user.current_ap < card.ap_cost:
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


func _targets_are_valid(user: BattleUnitState, card: CardData, targets: Array, write_log: bool = true, weapon_slot: String = "") -> bool:
	if card.target_type == CardEnums.TargetType.NONE:
		return true

	if card.target_type == CardEnums.TargetType.AREA:
		if targets.size() != 1 or not (targets[0] is Vector2):
			if write_log:
				_emit_log("%s 需要一个位置目标。" % card.card_name)
			return false
		if not map_data.contains_map_position(targets[0]):
			if write_log:
				_emit_log("目标位置超出地图边界。")
			return false
		return true

	if card.target_type == CardEnums.TargetType.SELF:
		if targets.size() != 1 or targets[0] != user:
			if write_log:
				_emit_log("%s 目标必须是自己。" % card.card_name)
			return false
		return true

	if card.target_type == CardEnums.TargetType.SINGLE and targets.size() != 1:
		if write_log:
			_emit_log("%s 需要一个目标。" % card.card_name)
		return false

	for target in targets:
		if not (target is BattleUnitState) or not target.is_alive():
			if write_log:
				_emit_log("目标无效。")
			return false

		var distance := user.distance_to(target)
		var card_range := card.get_effective_range(user, weapon_slot)
		if distance > card_range:
			if write_log:
				_emit_log("%s 距离 %.0f，超出 %s 射程 %.0f。" % [target.get_display_name(), distance, card.card_name, card_range])
			return false

	return true


func _is_position_valid_for_unit(unit: BattleUnitState, position: Vector2, deployment_only: bool) -> bool:
	if not map_data.contains_map_position(position):
		_emit_log("目标位置超出地图边界。")
		return false

	if deployment_only and not map_data.contains_deployment_position(position):
		_emit_log("目标位置不在玩家部署区内。")
		return false

	return targeting.is_unit_position_clear(unit, position, true)


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


func enqueue_effect(callback: Callable, args: Array = [], priority: int = 0, label: String = "", context = null) -> void:
	resolution_runner.enqueue_effect(callback, args, priority, label, context)


func enqueue_trigger(callback: Callable, args: Array = [], priority: int = 0, label: String = "", context = null) -> void:
	resolution_runner.enqueue_trigger(callback, args, priority, label, context)


func resolve_effect_queue() -> void:
	resolution_runner.resolve_effect_queue()


func _emit_basic_attack_trigger(context: Dictionary) -> void:
	basic_attack_triggered.emit(context)


func _emit_weapon_switch_started(context: Dictionary) -> void:
	weapon_switch_started.emit(context)


func _emit_weapon_switched_out(context: Dictionary) -> void:
	weapon_switched_out.emit(context)


func _emit_weapon_switched_in(context: Dictionary) -> void:
	weapon_switched_in.emit(context)


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
	for status in target.statuses.duplicate():
		if status == null or not status.has_method("on_before_damage"):
			continue
		status.on_before_damage(target, damage_context)
		if damage_context.prevented:
			break

	target.remove_expired_statuses()


func _apply_global_effects(callback_name: String, unit: BattleUnitState = null) -> void:
	_queue_global_effects(callback_name, unit)
	resolve_effect_queue()


func _is_unit_position_clear(unit: BattleUnitState, position: Vector2, write_log: bool = false) -> bool:
	return targeting.is_unit_position_clear(unit, position, write_log)


func _closest_boundary_point(position: Vector2) -> Vector2:
	var closest := position
	var closest_distance := INF
	var point_count := map_data.boundary_points.size()
	for index in range(point_count):
		var start := map_data.boundary_points[index]
		var end := map_data.boundary_points[(index + 1) % point_count]
		var candidate := Geometry2D.get_closest_point_to_segment(position, start, end)
		var distance := position.distance_to(candidate)
		if distance < closest_distance:
			closest = candidate
			closest_distance = distance

	return closest
