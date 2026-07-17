extends RangerCardEffectBase
class_name RangerShadowPassageCardEffect

const BattleHexGrid = preload("res://scripts/battle/battle_hex_grid.gd")

@export_range(1, 12, 1) var movement_range: int = 3


func are_targets_valid(context: Dictionary = {}, targets: Array = [], write_log: bool = true) -> bool:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null or targets.size() != 1 or not (targets[0] is Vector2i):
		return false
	var landing_cell: Vector2i = targets[0]
	var valid := _is_valid_landing(controller, user, landing_cell)
	if not valid and write_log:
		controller._emit_log("猎影穿行需要选择范围 %d 内、与敌人相邻的空格。" % movement_range)
	return valid


func provides_area_target_cells() -> bool:
	return true


func get_area_target_cells(context: Dictionary = {}) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null or controller.phase != BattleController.Phase.BATTLE \
			or not user.is_alive() or not user.can_start_voluntary_movement():
		return result
	for cell: Vector2i in controller.map_data.get_all_cells():
		if _is_valid_landing(controller, user, cell):
			result.append(cell)
	return result


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null or targets.size() != 1 or not (targets[0] is Vector2i):
		return
	controller.enqueue_effect(
		Callable(self, "_resolve_passage"),
		[controller, user, targets[0] as Vector2i],
		effect_priority,
		"猎影穿行：移动",
		context
	)
	_enqueue_combo_completion(context)


func _resolve_passage(controller: BattleController, user: BattleUnitState, landing_cell: Vector2i) -> void:
	if controller.apply_card_movement_to_cell(user, landing_cell, "猎影穿行"):
		controller.enqueue_effect(
			Callable(controller, "enter_ranger_stealth"),
			[user, "猎影穿行潜行"],
			-10,
			"猎影穿行：进入潜行"
		)


func _is_valid_landing(controller: BattleController, user: BattleUnitState, cell: Vector2i) -> bool:
	if cell == user.cell:
		return false
	if not controller.map_data.is_valid_cell(cell):
		return false
	if BattleHexGrid.distance(user.cell, cell) > movement_range:
		return false
	if not controller.targeting.is_unit_cell_clear(user, cell, false):
		return false
	for enemy: BattleUnitState in controller.get_opposing_units(user):
		if BattleHexGrid.distance(enemy.cell, cell) == 1:
			return true
	return false
