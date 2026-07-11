extends Node

var _exit_code: int = 0
var _chain_count: int = 0
var _chain_action_ids: Array[int] = []
var _order: Array[String] = []
var _stage_action_ids: Array[int] = []
var _stage_lock_states: Array[bool] = []
var _reentrant_end_attempts: int = 0
var _duplicate_card_results: Array[bool] = []


func _ready() -> void:
	var runner_controller := BattleController.new()
	runner_controller.setup(null)
	_test_non_recursive_action_chain(runner_controller)
	_test_action_chain_limit(runner_controller)
	_test_effect_queue_reentry(runner_controller)
	_test_after_stage(runner_controller)
	_test_action_order(runner_controller)
	_test_turn_command_boundary()
	_test_turn_start_death_recovery()

	print("FLOW_DIAG: completed")
	get_tree().quit(_exit_code)


func _test_non_recursive_action_chain(controller: BattleController) -> void:
	controller.resolution_runner.reset()
	_chain_count = 0
	_chain_action_ids.clear()
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_chain_action"),
		[controller, 300]
	))
	if _chain_count != 300:
		_fail("FLOW_DIAG: non-recursive chain expected 300 actions, got %d" % _chain_count)
	var unique_ids := {}
	for action_id in _chain_action_ids:
		unique_ids[action_id] = true
	if unique_ids.size() != 300:
		_fail("FLOW_DIAG: chained actions did not receive unique action ids")
	_assert_runner_idle(controller, "300 action chain")


func _test_action_chain_limit(controller: BattleController) -> void:
	controller.resolution_runner.reset()
	_chain_count = 0
	_chain_action_ids.clear()
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_chain_action"),
		[controller, BattleResolutionRunner.MAX_ACTIONS_PER_PUMP + 20]
	))
	if _chain_count != BattleResolutionRunner.MAX_ACTIONS_PER_PUMP:
		_fail("FLOW_DIAG: action pump limit expected %d, got %d" % [
			BattleResolutionRunner.MAX_ACTIONS_PER_PUMP,
			_chain_count,
		])
	_assert_runner_idle(controller, "action pump limit")


func _chain_action(controller: BattleController, remaining: int) -> void:
	_chain_count += 1
	_chain_action_ids.append(controller.get_current_action_id())
	if remaining > 1:
		controller.push_action_frame(BattleActionFrame.create(
			Callable(self, "_chain_action"),
			[controller, remaining - 1]
		))


func _test_effect_queue_reentry(controller: BattleController) -> void:
	controller.resolution_runner.reset()
	_order.clear()
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_reentrant_effect"),
		[controller]
	))
	if _order != ["effect_enter", "effect_exit", "queued_effect"]:
		_fail("FLOW_DIAG: effect queue reentry changed order: %s" % str(_order))
	_assert_runner_idle(controller, "effect queue reentry")


func _reentrant_effect(controller: BattleController) -> void:
	_order.append("effect_enter")
	controller.enqueue_effect(Callable(self, "_record_order").bind("queued_effect"))
	controller.resolve_effect_queue()
	_order.append("effect_exit")


func _test_after_stage(controller: BattleController) -> void:
	controller.resolution_runner.reset()
	_order.clear()
	_stage_action_ids.clear()
	_stage_lock_states.clear()
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_record_stage"),
		[controller, "main"],
		0,
		"after stage diagnostic",
		null,
		Callable(self, "_queue_after_stage_effect"),
		[controller]
	))
	if _order != ["main", "after_callback", "after_effect"]:
		_fail("FLOW_DIAG: after stage order incorrect: %s" % str(_order))
	if _stage_action_ids.size() != 3 or _stage_action_ids[0] <= 0 \
		or _stage_action_ids[0] != _stage_action_ids[1] \
		or _stage_action_ids[1] != _stage_action_ids[2]:
		_fail("FLOW_DIAG: after stage did not retain one action id")
	for locked in _stage_lock_states:
		if not locked:
			_fail("FLOW_DIAG: after stage escaped the action lock")
			break
	_assert_runner_idle(controller, "after stage")


func _record_stage(controller: BattleController, label: String) -> void:
	_order.append(label)
	_stage_action_ids.append(controller.get_current_action_id())
	_stage_lock_states.append(controller.is_resolving_actions())


func _queue_after_stage_effect(controller: BattleController) -> void:
	_record_stage(controller, "after_callback")
	controller.enqueue_effect(
		Callable(self, "_record_stage"),
		[controller, "after_effect"]
	)


func _test_action_order(controller: BattleController) -> void:
	controller.resolution_runner.reset()
	_order.clear()
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_queue_outer_and_inner"),
		[controller]
	))
	if _order != ["outer_1", "outer_2", "inner_action"]:
		_fail("FLOW_DIAG: action/effect order incorrect: %s" % str(_order))
	_assert_runner_idle(controller, "action order")


func _queue_outer_and_inner(controller: BattleController) -> void:
	controller.enqueue_effect(Callable(self, "_record_order").bind("outer_1"))
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_record_order"),
		["inner_action"]
	))
	controller.enqueue_effect(Callable(self, "_record_order").bind("outer_2"))


func _record_order(label: String) -> void:
	_order.append(label)


func _test_turn_command_boundary() -> void:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if scenario == null:
		_fail("FLOW_DIAG: sample battle scenario missing")
		return
	var controller := BattleController.new()
	controller.setup(scenario)
	_deploy_players(controller)
	if not controller.start_battle() or controller.current_unit == null:
		_fail("FLOW_DIAG: failed to start sample battle")
		return

	var active_unit := controller.current_unit
	var inactive_unit := _find_other_alive_unit(controller, active_unit)
	var opponent := controller.get_nearest_opponent(inactive_unit) if inactive_unit != null else null
	if inactive_unit == null or opponent == null:
		_fail("FLOW_DIAG: command boundary units missing")
		return
	var inactive_ap := inactive_unit.current_ap
	var inactive_position := inactive_unit.position
	if controller.move_unit_to(inactive_unit, inactive_position):
		_fail("FLOW_DIAG: out-of-turn movement was accepted")
	if controller.basic_attack(inactive_unit, opponent):
		_fail("FLOW_DIAG: out-of-turn basic attack was accepted")
	if not inactive_unit.hand.is_empty():
		var card := inactive_unit.hand[0] as CardData
		if controller.can_play_card_with_mode(inactive_unit, card, CardEnums.CardPlayMode.NORMAL):
			_fail("FLOW_DIAG: out-of-turn card preview was accepted")
		if controller.play_card(inactive_unit, card, [opponent]):
			_fail("FLOW_DIAG: out-of-turn card play was accepted")
	if inactive_unit.current_ap != inactive_ap or inactive_unit.position != inactive_position:
		_fail("FLOW_DIAG: rejected out-of-turn command changed unit state")

	_test_duplicate_card_submission(controller, active_unit)

	var expected_player := _find_next_player_in_turn_order(controller, active_unit)
	controller.state_changed.connect(_attempt_reentrant_end_turn.bind(controller))
	controller.end_current_turn()
	if _reentrant_end_attempts <= 0:
		_fail("FLOW_DIAG: reentrant end-turn path was not exercised")
	if expected_player != null and controller.phase == BattleController.Phase.BATTLE and controller.current_unit != expected_player:
		_fail("FLOW_DIAG: reentrant end-turn skipped the expected player turn")
	_assert_runner_idle(controller, "turn command boundary")


func _test_duplicate_card_submission(controller: BattleController, unit: BattleUnitState) -> void:
	var card := (load("res://resources/cards/battle_strike.tres") as CardData).duplicate() as CardData
	var target := controller.get_nearest_opponent(unit)
	if card == null or target == null:
		_fail("FLOW_DIAG: duplicate card diagnostic resources missing")
		return
	unit.hand.append(card)
	unit.current_ap = 10
	target.position = unit.position + Vector2(60.0, 0.0)
	_duplicate_card_results.clear()
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_submit_same_card_twice"),
		[controller, unit, card, target]
	))
	if _duplicate_card_results != [true, false]:
		_fail("FLOW_DIAG: duplicate in-flight card submissions were not rejected: %s" % str(_duplicate_card_results))


func _submit_same_card_twice(controller: BattleController, unit: BattleUnitState, card: CardData, target: BattleUnitState) -> void:
	controller.internal_action_submission_depth += 1
	_duplicate_card_results.append(controller.play_card(unit, card, [target]))
	_duplicate_card_results.append(controller.play_card(unit, card, [target]))
	controller.internal_action_submission_depth = maxi(0, controller.internal_action_submission_depth - 1)


func _test_turn_start_death_recovery() -> void:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if scenario == null:
		return
	var controller := BattleController.new()
	controller.setup(scenario)
	_deploy_players(controller)
	if not controller.start_battle() or controller.current_unit == null:
		_fail("FLOW_DIAG: failed to start turn-start death diagnostic")
		return
	var doomed := controller.current_unit
	controller.turn_flow_state = BattleController.TurnFlowState.START_PENDING
	controller.push_action_frame(BattleActionFrame.create(
		Callable(doomed, "set_current_health"),
		[0],
		0,
		"turn-start lethal diagnostic",
		null,
		Callable(controller, "_finish_turn_start_action"),
		[doomed]
	))
	if controller.phase == BattleController.Phase.BATTLE \
		and (controller.current_unit == doomed or controller.turn_flow_state != BattleController.TurnFlowState.ACTIVE):
		_fail("FLOW_DIAG: lethal turn-start effect left combat stuck")
	_assert_runner_idle(controller, "turn-start death recovery")


func _attempt_reentrant_end_turn(controller: BattleController) -> void:
	if not controller.is_resolving_actions() and not controller.resolution_state_notification_active:
		return
	_reentrant_end_attempts += 1
	controller.end_current_turn()


func _deploy_players(controller: BattleController) -> void:
	var deploy_rect := controller.map_data.player_deployment_rect
	for index in range(controller.player_units.size()):
		var unit: BattleUnitState = controller.player_units[index]
		var position := deploy_rect.position + Vector2(64.0 + float(index) * 72.0, deploy_rect.size.y * 0.5)
		if not controller.deploy_player_unit(unit, position):
			_fail("FLOW_DIAG: failed to deploy %s" % unit.get_display_name())


func _find_other_alive_unit(controller: BattleController, excluded: BattleUnitState) -> BattleUnitState:
	for unit in controller.units:
		if unit != null and unit != excluded and unit.is_alive():
			return unit
	return null


func _find_next_player_in_turn_order(controller: BattleController, current: BattleUnitState) -> BattleUnitState:
	var start := controller.turn_order.find(current)
	if start < 0:
		return null
	for offset in range(1, controller.turn_order.size() + 1):
		var unit: BattleUnitState = controller.turn_order[(start + offset) % controller.turn_order.size()]
		if unit != null and unit.is_alive() and unit.faction == BattleUnitState.Faction.PLAYER:
			return unit
	return null


func _assert_runner_idle(controller: BattleController, label: String) -> void:
	if controller.is_resolving_actions():
		_fail("FLOW_DIAG: controller remained locked after %s" % label)
	if controller.get_current_action_id() != 0:
		_fail("FLOW_DIAG: action id leaked after %s" % label)
	if not controller.resolution_runner.action_queue.is_empty():
		_fail("FLOW_DIAG: action queue not empty after %s" % label)
	if controller.resolution_runner.queue_scopes.size() != 1 \
		or not (controller.resolution_runner.queue_scopes[0] as Array).is_empty():
		_fail("FLOW_DIAG: effect queue scope leaked after %s" % label)


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
	print("ERROR: " + message)
