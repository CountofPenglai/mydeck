extends CardEffect
class_name ChargeCardEffect

const BattleHexGrid = preload("res://scripts/battle/battle_hex_grid.gd")

@export_range(0, 12, 1) var move_ap_budget: int = 2
@export_range(0, 12, 1) var target_range_bonus: int = 3
@export_range(0, 12, 1) var long_charge_threshold: int = 5
@export_range(0, 99, 1) var long_charge_damage_bonus: int = 3


func _init() -> void:
	uses_strike = true


func modify_effective_range(user_value, _equipment_slot: String, current_range: int) -> int:
	var user := user_value as BattleUnitState
	if user == null or user.battle_controller == null:
		return current_range
	return user.battle_controller.get_ap_movement_distance(user, move_ap_budget) + target_range_bonus


func get_valid_targets(context: Dictionary = {}) -> Array:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	if controller == null or user == null:
		return []
	var result: Array[BattleUnitState] = []
	for target in controller.get_units_by_filter(user, BattleController.UnitFilter.OPPONENTS):
		if _is_valid_target(controller, user, target, false):
			result.append(target)
	return result


func is_object_target_allowed(_context: Dictionary = {}, _target: BattleObjectState = null) -> bool:
	return false


func are_targets_valid(context: Dictionary = {}, targets: Array = [], write_log: bool = true) -> bool:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var target := targets[0] as BattleUnitState if targets.size() == 1 else null
	return _is_valid_target(controller, user, target, write_log)


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	var target := targets[0] as BattleUnitState if targets.size() == 1 else null
	if not _is_valid_target(controller, user, target, false) or card == null:
		return

	var start_cell := user.cell
	var landing_cell := _landing_cell(controller, user, target)
	if landing_cell != start_cell \
			and not controller.apply_card_movement_to_cell(user, landing_cell, "冲锋"):
		return
	if not target.is_alive():
		return
	var moved_distance := BattleHexGrid.distance(start_cell, user.cell)
	var damage_bonus := long_charge_damage_bonus if moved_distance > long_charge_threshold else 0
	controller.perform_strike_with_modifier(
		user,
		target,
		card,
		damage_bonus,
		"冲锋打击",
		str(context.get("equipment_slot", ""))
	)


func _is_valid_target(
	controller: BattleController,
	user: BattleUnitState,
	target: BattleUnitState,
	write_log: bool
) -> bool:
	if controller == null or user == null or target == null \
			or controller.phase != BattleController.Phase.BATTLE \
			or not user.is_alive() or not target.is_alive() or target.faction == user.faction \
			or not user.can_start_voluntary_movement():
		return false
	var max_range := controller.get_ap_movement_distance(user, move_ap_budget) + target_range_bonus
	var distance := BattleHexGrid.distance(user.cell, target.cell)
	if distance > max_range:
		if write_log:
			controller._emit_log("%s 距离 %d，超出冲锋范围 %d。" % [target.get_display_name(), distance, max_range])
		return false
	if not controller.targeting.has_line_of_sight_between_units(user, target):
		if write_log:
			controller._emit_log("冲锋路径被阻挡。")
		return false
	var landing_cell := _landing_cell(controller, user, target)
	if landing_cell == BattleHexGrid.INVALID_CELL:
		if write_log:
			controller._emit_log("目标面前没有可用的冲锋落点。")
		return false
	return true


func _landing_cell(
	controller: BattleController,
	user: BattleUnitState,
	target: BattleUnitState
) -> Vector2i:
	if controller == null or controller.map_data == null or user == null or target == null:
		return BattleHexGrid.INVALID_CELL
	var line := controller.map_data.get_line(user.cell, target.cell)
	if line.size() < 2:
		return BattleHexGrid.INVALID_CELL
	var landing_cell: Vector2i = line[line.size() - 2]
	if landing_cell == user.cell:
		return landing_cell
	if not controller.map_data.is_valid_cell(landing_cell) \
			or not controller.targeting.is_unit_cell_clear(user, landing_cell, false):
		return BattleHexGrid.INVALID_CELL
	return landing_cell
