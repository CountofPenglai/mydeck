extends EnemyBehavior
class_name MeleeEnemyBehavior

const BattleHexGrid = preload("res://scripts/battle/battle_hex_grid.gd")

enum State {
	APPROACH,
	ATTACK,
}

@export var state: int = State.APPROACH


func choose_action(context: Dictionary = {}, enemy_state = null) -> Dictionary:
	var controller: BattleController = context.get("controller") as BattleController
	var unit: BattleUnitState = enemy_state as BattleUnitState
	if controller == null or unit == null or unit.current_ap <= 0 or not unit.is_alive():
		return {"state": state, "action_started": false}
	var target := controller.get_nearest_opponent(unit)
	if target == null:
		return {"state": state, "action_started": false}
	var card := controller.find_playable_card_against(unit, target)
	if card != null:
		state = State.ATTACK
		return {"state": state, "action_started": controller.play_card(unit, card, [target])}
	if unit.cell_distance_to(target) <= unit.get_attack_range():
		state = State.ATTACK
		return {"state": state, "action_started": controller.basic_attack(unit, target)}
	state = State.APPROACH
	return {"state": state, "action_started": _move_toward_attack_range(controller, unit, target)}


func _move_toward_attack_range(controller: BattleController, unit: BattleUnitState, target: BattleUnitState) -> bool:
	var best_cell: Vector2i = BattleHexGrid.INVALID_CELL
	var best_score := 2147483647
	var best_move := 2147483647
	for cell in controller.get_reachable_cells(unit):
		if cell == unit.cell:
			continue
		if not controller.targeting.is_unit_cell_clear(unit, cell, false):
			continue
		var target_distance := controller.map_data.get_distance(cell, target.cell)
		var score: int = absi(target_distance - unit.get_attack_range())
		var move_distance := controller.map_data.get_distance(unit.cell, cell)
		if score < best_score or (score == best_score and move_distance < best_move):
			best_cell = cell
			best_score = score
			best_move = move_distance
	if best_cell == BattleHexGrid.INVALID_CELL:
		return false
	return controller.move_unit_to_cell(unit, best_cell)
