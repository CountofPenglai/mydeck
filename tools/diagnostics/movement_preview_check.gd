extends Node

const ITERATIONS := 300


func _ready() -> void:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if scenario == null:
		push_error("MOVE_PREVIEW_DIAG: scenario missing")
		get_tree().quit(1)
		return
	var controller := BattleController.new()
	controller.setup(scenario)
	var unit := controller.player_units[0]
	if not controller.deploy_player_unit_at_cell(unit, Vector2i(2, 4)):
		push_error("MOVE_PREVIEW_DIAG: deployment failed")
		get_tree().quit(1)
		return
	var neighbors := BattleHexGrid.neighbors(unit.cell)
	controller.surface_state.set_base_element(neighbors[0], BattleSurfaceState.Element.WATER)
	controller.surface_state.set_base_element(neighbors[1], BattleSurfaceState.Element.ICE)
	for ap_budget in [1, 2, 4]:
		unit.current_ap = ap_budget
		var reference := _reference_reachable_cells(controller, unit)
		var optimized := controller.get_reachable_cells(unit)
		if optimized != reference:
			push_error("MOVE_PREVIEW_DIAG: reachable cells differ at %d AP" % ap_budget)
			get_tree().quit(1)
			return
	unit.current_ap = 4
	var expected := controller.get_reachable_cells(unit)
	var started := Time.get_ticks_usec()
	for _index in range(ITERATIONS):
		var actual := controller.get_reachable_cells(unit)
		if actual != expected:
			push_error("MOVE_PREVIEW_DIAG: reachable cells changed between calls")
			get_tree().quit(1)
			return
	var elapsed := Time.get_ticks_usec() - started
	var average_usec := float(elapsed) / float(ITERATIONS)
	if average_usec > 100000.0:
		push_error("MOVE_PREVIEW_DIAG: %.2f us/call exceeds regression budget" % average_usec)
		get_tree().quit(1)
		return
	print("MOVE_PREVIEW_DIAG: %d cells, %.2f us/call" % [expected.size(), average_usec])
	get_tree().quit()


func _reference_reachable_cells(controller: BattleController, unit: BattleUnitState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in controller.map_data.get_all_cells():
		if cell != unit.cell and not controller.targeting.is_unit_cell_clear(unit, cell, false):
			continue
		var path := controller.get_movement_path(unit, cell)
		if path.is_empty():
			continue
		var movement_cost := controller._get_path_movement_cost(unit, path)
		if unit.get_move_ap_cost(movement_cost, controller.config) <= unit.current_ap:
			result.append(cell)
	return result
