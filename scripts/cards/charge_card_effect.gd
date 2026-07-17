extends CardEffect
class_name ChargeCardEffect

const BattleHexGrid = preload("res://scripts/battle/battle_hex_grid.gd")

@export var agility_modifier: int = 3
@export var move_ap_budget: int = 2
@export var strike_damage_modifier: int = -2

func _init() -> void:
	uses_strike = true


func are_targets_valid(context: Dictionary = {}, targets: Array = [], write_log: bool = true) -> bool:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null or targets.size() != 1 or not (targets[0] is Vector2i):
		return false

	var valid := _is_valid_direction_cell(controller, user, targets[0] as Vector2i)
	if not valid and write_log:
		controller._emit_log("冲锋需要选择直线移动范围内、能够产生实际位移的方向格。")
	return valid


func provides_area_target_cells() -> bool:
	return true


func get_area_target_cells(context: Dictionary = {}) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null:
		return result
	for cell: Vector2i in controller.map_data.get_all_cells():
		if _is_valid_direction_cell(controller, user, cell):
			result.append(cell)
	return result


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller = context.get("controller")
	var user = context.get("user")
	var card = context.get("card")
	if controller == null or user == null or targets.is_empty() or not (targets[0] is Vector2i):
		return

	var requested_cell: Vector2i = targets[0]
	var movement = controller.apply_movement_effect(user, requested_cell, agility_modifier, false, move_ap_budget)
	if not bool(movement.get("success", false)):
		return

	var start_cell: Vector2i = movement.get("start_cell", user.cell)
	var end_cell: Vector2i = movement.get("end_cell", user.cell)
	var hits = controller.get_units_along_hex_line(
		user,
		start_cell,
		end_cell,
		BattleController.UnitFilter.OPPONENTS
	)
	for target in hits:
		controller.enqueue_effect(
			Callable(controller, "perform_strike_with_modifier"),
			[user, target, card, strike_damage_modifier, "冲锋打击", str(context.get("equipment_slot", ""))],
			effect_priority,
			"冲锋途经打击",
			{
				"controller": controller,
				"user": user,
				"target": target,
				"card": card,
			}
		)


func _is_valid_direction_cell(controller: BattleController, user: BattleUnitState, cell: Vector2i) -> bool:
	if controller.phase != BattleController.Phase.BATTLE or not user.is_alive() or not user.can_start_voluntary_movement():
		return false
	if not controller.map_data.is_valid_cell(cell) or cell == user.cell:
		return false
	var max_distance := controller.get_ap_movement_distance(user, move_ap_budget, agility_modifier)
	if BattleHexGrid.distance(user.cell, cell) > max_distance:
		return false
	var endpoint := controller.targeting.find_clear_endpoint_along_hex_line(user, user.cell, cell)
	return endpoint != user.cell and controller.targeting.is_unit_cell_clear(user, endpoint, false)
