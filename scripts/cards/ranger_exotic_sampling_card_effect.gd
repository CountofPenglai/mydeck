extends CardEffect
class_name RangerExoticSamplingCardEffect


func can_play(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and user.is_ranger()


func provides_area_target_cells() -> bool:
	return true


func get_area_target_cells(context: Dictionary = {}) -> Array[Vector2i]:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var cells: Array[Vector2i] = []
	if controller == null or user == null:
		return cells
	for cell in controller.map_data.get_all_cells():
		if controller.can_place_elemental_trap(user, cell) and controller.map_data.get_distance(user.cell, cell) <= 3:
			cells.append(cell)
	return cells


func are_targets_valid(context: Dictionary = {}, targets: Array = [], _write_log: bool = true) -> bool:
	if targets.size() != 1 or not (targets[0] is Vector2i):
		return false
	return get_area_target_cells(context).has(targets[0] as Vector2i)


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1:
		return
	controller.place_elemental_trap(user, targets[0] as Vector2i)
