extends Node

const PREVIEW_ITERATIONS := 200

var _exit_code := 0


func _ready() -> void:
	_test_charge_direction_movement()
	_test_card_path_movement()
	_test_ranger_movement_queries()
	print("CARD_MOVE_DIAG: completed")
	get_tree().quit(_exit_code)


func _test_charge_direction_movement() -> void:
	var controller := _create_controller()
	var warrior := controller.player_units[0] as BattleUnitState
	var blocker := controller.enemy_units[0] as BattleUnitState
	warrior.set_hex_cell(Vector2i(2, 4), controller.map_data)
	blocker.set_hex_cell(Vector2i(3, 4), controller.map_data)
	var destination := Vector2i(4, 4)
	var card := load("res://resources/cards/battle_charge.tres") as CardData
	var effect := card.effect as ChargeCardEffect
	var context := {"controller": controller, "user": warrior, "card": card, "equipment_slot": "weapon"}
	var cells := effect.get_area_target_cells(context)
	if not cells.has(destination):
		_fail("CARD_MOVE_DIAG: charge did not expose a clear endpoint behind an enemy")
		return
	if not effect.are_targets_valid(context, [destination], false):
		_fail("CARD_MOVE_DIAG: charge preview and target validation disagree")
		return
	var started := Time.get_ticks_usec()
	for _index in range(PREVIEW_ITERATIONS):
		effect.get_area_target_cells(context)
	var average_usec := float(Time.get_ticks_usec() - started) / float(PREVIEW_ITERATIONS)
	if average_usec > 100000.0:
		_fail("CARD_MOVE_DIAG: charge target query took %.2f us/call" % average_usec)
	warrior.hand.append(card)
	warrior.current_ap = 10
	controller.current_unit = warrior
	if not controller.play_card(warrior, card, [destination], {"equipment_slot": "weapon"}):
		_fail("CARD_MOVE_DIAG: charge card frame rejected a valid cell target")
		return
	if warrior.cell != destination:
		_fail("CARD_MOVE_DIAG: charge previewed %s but ended at %s" % [destination, warrior.cell])
	print("CARD_MOVE_DIAG: charge %d cells, %.2f us/query" % [cells.size(), average_usec])


func _test_card_path_movement() -> void:
	var controller := _create_controller()
	var warrior := controller.player_units[0] as BattleUnitState
	warrior.set_hex_cell(Vector2i(2, 4), controller.map_data)
	var move_ap_limit := 1
	var cells := controller.get_reachable_cells_for_ap(warrior, move_ap_limit, false)
	var destination := BattleHexGrid.INVALID_CELL
	var path: Array[Vector2i] = []
	for candidate in cells:
		var candidate_path := controller.get_movement_path(warrior, candidate)
		if candidate_path.size() >= 3:
			destination = candidate
			path = candidate_path
			break
	if destination == BattleHexGrid.INVALID_CELL:
		_fail("CARD_MOVE_DIAG: card path movement had no two-cell path")
		return
	controller.surface_state.create_advanced_surface(path[1], BattleSurfaceState.Element.LAVA, controller.battle_round)
	var movement_logs: Array[String] = []
	controller.log_message.connect(func(message: String) -> void: movement_logs.append(message))
	if not controller.apply_card_path_movement_to_cell(warrior, destination, move_ap_limit, false, "diagnostic"):
		_fail("CARD_MOVE_DIAG: card movement rejected a reachable path")
		return
	if warrior.cell != destination:
		_fail("CARD_MOVE_DIAG: card movement ended at %s instead of %s" % [warrior.cell, destination])
	if not movement_logs.any(func(message: String) -> bool: return message.contains("熔岩")):
		_fail("CARD_MOVE_DIAG: card movement skipped an intermediate lava surface")
	print("CARD_MOVE_DIAG: path movement %d legal cells, path length %d" % [cells.size(), path.size()])


func _test_ranger_movement_queries() -> void:
	var controller := _create_controller()
	var ranger := controller.player_units[1] as BattleUnitState
	var target := controller.enemy_units[0] as BattleUnitState
	ranger.set_hex_cell(Vector2i(3, 4), controller.map_data)
	target.set_hex_cell(Vector2i(4, 4), controller.map_data)
	var shadow_card := load("res://resources/cards/ranger_shadow_passage.tres") as CardData
	var shadow := shadow_card.effect as RangerShadowPassageCardEffect
	var shadow_context := {"controller": controller, "user": ranger, "card": shadow_card}
	var shadow_cells := shadow.get_area_target_cells(shadow_context)
	for cell in shadow_cells:
		if not shadow.are_targets_valid(shadow_context, [cell], false):
			_fail("CARD_MOVE_DIAG: shadow passage query returned an invalid cell")
			break

	var cross_card := load("res://resources/cards/ranger_cross_hunt_step.tres") as CardData
	var cross := cross_card.effect as RangerCrossHuntStepCardEffect
	for slot in ["weapon", "paired"]:
		var cross_context := {"controller": controller, "user": ranger, "card": cross_card, "equipment_slot": slot}
		var landing_cells := cross.get_landing_target_cells(cross_context, [target])
		if landing_cells.is_empty():
			_fail("CARD_MOVE_DIAG: cross hunt step had no %s landing cells" % slot)
			continue
		for cell in landing_cells:
			var validation_context := cross_context.duplicate()
			validation_context["landing_cell"] = cell
			if not cross.are_targets_valid(validation_context, [target], false):
				_fail("CARD_MOVE_DIAG: cross hunt step query returned an invalid %s cell" % slot)
				break
	var rooted := RangerRootedStatus.new()
	rooted.stacks = 1
	ranger.add_status(rooted)
	if not shadow.get_area_target_cells(shadow_context).is_empty():
		_fail("CARD_MOVE_DIAG: rooted ranger still previewed shadow passage cells")
	var rooted_cross_context := {"controller": controller, "user": ranger, "card": cross_card, "equipment_slot": "paired"}
	if not cross.get_landing_target_cells(rooted_cross_context, [target]).is_empty():
		_fail("CARD_MOVE_DIAG: rooted ranger still previewed cross-step landing cells")
	print("CARD_MOVE_DIAG: shadow %d cells; cross-step queries aligned" % shadow_cells.size())


func _create_controller() -> BattleController:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	var controller := BattleController.new()
	controller.setup(scenario)
	for index in range(controller.player_units.size()):
		var unit := controller.player_units[index] as BattleUnitState
		controller.deploy_player_unit_at_cell(unit, Vector2i(index % controller.map_data.player_deployment_columns, index + 2))
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	return controller


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
	print("ERROR: " + message)
