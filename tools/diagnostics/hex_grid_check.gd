extends Node

var _exit_code := 0


func _ready() -> void:
	var map_data := load("res://resources/battle/sample_battle_map.tres") as BattleMapData
	if map_data == null:
		_fail("HEX_DIAG: failed to load map data")
		_finish()
		return
	_test_coordinate_round_trip(map_data)
	_test_distance_and_lines(map_data)
	_test_controller_authority(map_data)
	_test_migrated_ranges()
	print("HEX_DIAG: completed")
	_finish()


func _test_coordinate_round_trip(map_data: BattleMapData) -> void:
	for cell in map_data.get_all_cells():
		var restored := map_data.map_to_cell(map_data.cell_to_map(cell))
		if restored != cell:
			_fail("HEX_DIAG: round trip failed for %s -> %s" % [cell, restored])
	var center := Vector2i(5, 4)
	var neighbors := 0
	for cell in map_data.get_all_cells():
		if map_data.get_distance(center, cell) == 1:
			neighbors += 1
	if neighbors != 6:
		_fail("HEX_DIAG: center cell has %d neighbors instead of 6" % neighbors)


func _test_distance_and_lines(map_data: BattleMapData) -> void:
	var start := Vector2i(1, 1)
	var finish := Vector2i(9, 7)
	var distance := map_data.get_distance(start, finish)
	if distance != map_data.get_distance(finish, start):
		_fail("HEX_DIAG: distance is not symmetric")
	var forward := map_data.get_line(start, finish)
	var backward := map_data.get_line(finish, start)
	backward.reverse()
	if forward != backward:
		_fail("HEX_DIAG: line is not directionally stable")
	if forward.size() != distance + 1 or forward.front() != start or forward.back() != finish:
		_fail("HEX_DIAG: line endpoints or length are invalid")
	for source in map_data.get_all_cells():
		for target in map_data.get_all_cells():
			var source_line := map_data.get_line(source, target)
			var reverse_line := map_data.get_line(target, source)
			reverse_line.reverse()
			if source_line != reverse_line:
				_fail("HEX_DIAG: unstable line between %s and %s" % [source, target])
				return


func _test_controller_authority(_map_data: BattleMapData) -> void:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	var controller := BattleController.new()
	controller.setup(scenario)
	for unit in controller.enemy_units:
		_assert_unit_synced(controller, unit)
	if not controller.player_units.is_empty() and controller.deploy_player_unit_at_cell(controller.player_units[0], Vector2i(-1000, -1000)):
		_fail("HEX_DIAG: deployment accepted an out-of-bounds click")
	for index in range(controller.player_units.size()):
		var cell := Vector2i(index % controller.map_data.player_deployment_columns, index + 2)
		if not controller.deploy_player_unit_at_cell(controller.player_units[index], cell):
			_fail("HEX_DIAG: player deployment failed at %s" % cell)
		_assert_unit_synced(controller, controller.player_units[index])
	if controller.player_units.size() >= 2:
		var occupied := controller.player_units[0].cell
		if controller.targeting.is_unit_cell_clear(controller.player_units[1], occupied, false):
			_fail("HEX_DIAG: occupied cell was reported clear")
	var mover: BattleUnitState = controller.player_units[0]
	controller.phase = BattleController.Phase.BATTLE
	var destination := Vector2i(mover.cell.x + 2, mover.cell.y)
	var distance := controller.map_data.get_distance(mover.cell, destination)
	if mover.get_move_ap_cost(distance, controller.config) != ceili(float(distance) / float(mover.get_move_distance_per_ap(controller.config))):
		_fail("HEX_DIAG: movement AP cost is not based on integer cell distance")
	var discount := NextMoveApDiscountStatus.new()
	discount.stacks = 1
	discount.discount_amount = 1
	mover.add_status(discount)
	mover.current_ap = 0
	var free_neighbor := Vector2i(mover.cell.x + 1, mover.cell.y)
	if not controller.get_reachable_cells(mover).has(free_neighbor):
		_fail("HEX_DIAG: AP discount was omitted from reachable-cell query")
	var extended_distance := mover.get_move_distance_per_ap(controller.config) * 2
	var extended_destination := Vector2i(mover.cell.x + extended_distance, mover.cell.y)
	if not controller.can_unit_reach_cell_with_ap(mover, extended_destination, 1, false, true):
		_fail("HEX_DIAG: AP discount did not extend normal movement validation")
	if controller.can_unit_reach_cell_with_ap(mover, extended_destination, 1, false, false):
		_fail("HEX_DIAG: free card movement incorrectly borrowed an AP discount")
	mover.statuses.erase(discount)
	var invalid_move := controller.apply_movement_effect(mover, Vector2i(-1, -1), 0, true, 1)
	if bool(invalid_move.get("success", false)):
		_fail("HEX_DIAG: out-of-bounds movement was clamped through pixel distance")
	_test_full_enemy_spawn_zone(controller)


func _test_full_enemy_spawn_zone(controller: BattleController) -> void:
	if controller.enemy_units.is_empty():
		_fail("HEX_DIAG: no enemy available for spawn-zone test")
		return
	var template_state := controller.enemy_units[0].enemy_state
	for cell in controller.map_data.get_all_cells():
		if not controller.map_data.is_enemy_spawn_cell(cell):
			continue
		var already_occupied := false
		for unit in controller.units:
			if unit.is_deployed and unit.is_alive() and unit.cell == cell:
				already_occupied = true
				break
		if already_occupied:
			continue
		var blocker := BattleUnitState.new()
		blocker.setup_enemy(1000 + controller.units.size(), template_state, controller.config.default_token_radius)
		blocker.set_hex_cell(cell, controller.map_data)
		controller.units.append(blocker)
	if controller._find_enemy_spawn_cell() != null:
		_fail("HEX_DIAG: full enemy spawn zone returned an overlapping fallback")


func _test_migrated_ranges() -> void:
	var bow := load("res://resources/items/training_bow.tres") as EquipmentData
	var melee := load("res://resources/enemies/battle_melee_enemy_data.tres") as EnemyData
	var ranged := load("res://resources/enemies/battle_ranged_enemy_data.tres") as EnemyData
	var moonlight := load("res://resources/cards/druid_moonlit_mend.tres") as CardData
	if bow == null or bow.attack_range != 2:
		_fail("HEX_DIAG: bow range migration failed")
	if melee == null or melee.base_attack_range != 1:
		_fail("HEX_DIAG: melee enemy range migration failed")
	if ranged == null or ranged.base_attack_range != 3:
		_fail("HEX_DIAG: ranged enemy range migration failed")
	if moonlight == null or moonlight.card_range != 3 or moonlight.inverted_card_range != 3:
		_fail("HEX_DIAG: moonlight range migration failed")


func _assert_unit_synced(controller: BattleController, unit: BattleUnitState) -> void:
	if not controller.map_data.is_valid_cell(unit.cell):
		_fail("HEX_DIAG: deployed unit has invalid cell")
	elif not unit.position.is_equal_approx(controller.map_data.cell_to_map(unit.cell)):
		_fail("HEX_DIAG: unit display position is not derived from its cell")


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)


func _finish() -> void:
	get_tree().quit(_exit_code)
