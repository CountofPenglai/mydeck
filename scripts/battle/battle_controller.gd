extends RefCounted
class_name BattleController

signal log_message(message: String)
signal state_changed

enum Phase {
	DEPLOYMENT,
	BATTLE,
	ENDED,
}

var scenario: BattleScenario
var config: BattleConfig
var map_data: BattleMapData
var rng := RandomNumberGenerator.new()
var phase: int = Phase.DEPLOYMENT
var units: Array[BattleUnitState] = []
var player_units: Array[BattleUnitState] = []
var enemy_units: Array[BattleUnitState] = []
var turn_order: Array[BattleUnitState] = []
var current_turn_index: int = -1
var current_unit: BattleUnitState

func setup(new_scenario: BattleScenario) -> void:
	scenario = new_scenario
	config = scenario.battle_config
	map_data = scenario.map_data
	rng.seed = scenario.seed
	phase = Phase.DEPLOYMENT
	units.clear()
	player_units.clear()
	enemy_units.clear()
	turn_order.clear()
	current_turn_index = -1
	current_unit = null

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

	for enemy_state in scenario.enemies:
		if enemy_state == null:
			continue
		enemy_state.ensure_initialized(rng.randi())
		enemy_state.current_health = enemy_state.get_max_health()
		enemy_state.generate_deck(rng.randi())
		var spawn_position := _find_enemy_spawn_position()
		var unit := BattleUnitState.new()
		unit.setup_enemy(id, enemy_state, config.default_unit_radius, spawn_position)
		id += 1
		units.append(unit)
		enemy_units.append(unit)

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


func play_card(user: BattleUnitState, card: CardData, targets: Array) -> bool:
	if phase != Phase.BATTLE:
		_emit_log("战斗尚未开始。")
		return false

	if user == null or card == null or not user.is_alive():
		_emit_log("没有可打出的卡牌。")
		return false

	if user.current_ap < card.ap_cost:
		_emit_log("%s AP不足，%s 需要 %d AP。" % [user.get_display_name(), card.card_name, card.ap_cost])
		return false

	if not _targets_are_valid(user, card, targets):
		return false

	var context := {
		"controller": self,
		"user": user,
		"card": card,
	}
	if not card.can_play(context):
		_emit_log("%s 当前不能打出。" % card.card_name)
		return false

	user.current_ap -= card.ap_cost
	card.play(context, targets)
	user.discard_card(card)
	_emit_log("%s 打出 %s，消耗 %d AP。" % [user.get_display_name(), card.card_name, card.ap_cost])
	state_changed.emit()
	_check_battle_end()
	return true


func basic_attack(attacker: BattleUnitState, target: BattleUnitState) -> bool:
	if phase != Phase.BATTLE:
		return false

	if attacker == null or target == null or not attacker.is_alive() or not target.is_alive():
		_emit_log("攻击目标无效。")
		return false

	if attacker.current_ap < config.basic_attack_ap_cost:
		_emit_log("%s AP不足，普通攻击需要 %d AP。" % [attacker.get_display_name(), config.basic_attack_ap_cost])
		return false

	var distance := attacker.distance_to(target)
	if distance > attacker.get_attack_range():
		_emit_log("距离 %.0f 超出 %s 的攻击距离 %.0f。" % [distance, attacker.get_display_name(), attacker.get_attack_range()])
		return false

	attacker.current_ap -= config.basic_attack_ap_cost
	apply_damage(attacker, target, attacker.get_attack(), "普通攻击")
	state_changed.emit()
	_check_battle_end()
	return true


func apply_damage(source: BattleUnitState, target: BattleUnitState, amount: int, label: String = "伤害") -> void:
	if target == null or not target.is_alive():
		return

	var actual := target.apply_damage(amount)
	var source_name := "效果"
	if source != null:
		source_name = source.get_display_name()
	_emit_log("%s 对 %s 造成 %d 点%s。" % [source_name, target.get_display_name(), actual, label])


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


func _targets_are_valid(user: BattleUnitState, card: CardData, targets: Array, write_log: bool = true) -> bool:
	if card.target_type == CardEnums.TargetType.NONE:
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
		var card_range := card.get_effective_range(user)
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

	for other in units:
		if other == unit or not other.is_deployed or not other.is_alive():
			continue
		if position.distance_to(other.position) < unit.radius + other.radius:
			_emit_log("目标位置与 %s 重叠。" % other.get_display_name())
			return false

	return true


func _find_enemy_spawn_position() -> Vector2:
	for _i in range(40):
		var position := map_data.random_enemy_spawn_position(rng)
		var fake := BattleUnitState.new()
		fake.radius = config.default_unit_radius
		if _is_spawn_position_valid(fake, position):
			return position

	return map_data.enemy_spawn_rect.get_center()


func _is_spawn_position_valid(unit: BattleUnitState, position: Vector2) -> bool:
	if not map_data.contains_map_position(position):
		return false

	for other in units:
		if not other.is_deployed:
			continue
		if position.distance_to(other.position) < unit.radius + other.radius:
			return false

	return true


func _rebuild_turn_order() -> void:
	turn_order.clear()
	for unit in units:
		if unit.is_alive():
			turn_order.append(unit)

	turn_order.sort_custom(Callable(self, "_compare_turn_order"))


func clamp_to_map(position: Vector2) -> Vector2:
	return Vector2(
		clampf(position.x, 0.0, map_data.map_size.x),
		clampf(position.y, 0.0, map_data.map_size.y)
	)


func _compare_turn_order(a: BattleUnitState, b: BattleUnitState) -> bool:
	if a.get_speed() == b.get_speed():
		return a.turn_order_index < b.turn_order_index

	return a.get_speed() > b.get_speed()


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
