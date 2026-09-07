extends EnemyBehavior
class_name TacticalEnemyBehavior


func lock_intent(context: Dictionary = {}, enemy_state = null) -> void:
	var controller := context.get("controller") as BattleController
	var unit := enemy_state as BattleUnitState
	if controller == null or unit == null or unit.enemy_state == null:
		return
	unit.enemy_state.intent_plan = EnemyIntentPlanner.build_plan(controller, unit, controller.battle_round + 1)
	controller.state_changed.emit()


func on_turn_start(context: Dictionary = {}, enemy_state = null) -> void:
	var unit := enemy_state as BattleUnitState
	if unit == null or unit.enemy_state == null or unit.enemy_state.intent_plan == null:
		return
	unit.enemy_state.intent_plan.prepare_execution(unit.current_ap)


func choose_action(context: Dictionary = {}, enemy_state = null) -> Dictionary:
	var controller := context.get("controller") as BattleController
	var unit := enemy_state as BattleUnitState
	if controller == null or unit == null or unit.enemy_state == null:
		return {"action_started": false}
	var plan := unit.enemy_state.intent_plan
	while plan != null and not plan.forced_steps.is_empty():
		var step: Dictionary = plan.forced_steps.pop_front()
		var started := _execute_step(controller, unit, step)
		controller.state_changed.emit()
		if started:
			return {"action_started": true}
	if plan == null or not plan.execution_prepared:
		return {"action_started": false}
	if plan.is_finished():
		return {"action_started": false}
	while not plan.is_finished():
		if plan.get_current_budget() <= 0 or plan.current_group_reached_action_limit():
			plan.complete_current_group()
			controller.state_changed.emit()
			continue
		var action := EnemyIntentPlanner.choose_action(
			controller,
			unit,
			plan.get_current_category(),
			mini(unit.current_ap, plan.get_current_budget()),
			plan.get_current_group().combo_tags
		)
		if action == null:
			plan.complete_current_group()
			controller.state_changed.emit()
			continue
		if not _execute_action(controller, unit, action):
			plan.complete_current_group()
			controller.state_changed.emit()
			continue
		var group := plan.get_current_group()
		plan.consume_current_budget(action.ap_cost)
		for tag in action.provided_tags:
			if group != null and not group.combo_tags.has(tag):
				group.combo_tags.append(tag)
		controller.state_changed.emit()
		return {"action_started": true}
	return {"action_started": false}


func _execute_action(controller: BattleController, unit: BattleUnitState, action: EnemyIntentAction) -> bool:
	if action == null or not action.is_valid():
		return false
	match action.kind:
		EnemyIntentAction.Kind.CARD:
			if not unit.hand.has(action.card) or not controller._targets_are_valid(unit, action.card, action.targets, false):
				return false
			unit.enemy_state.remember_seen_card(action.card)
			return controller.play_card(unit, action.card, action.targets)
		EnemyIntentAction.Kind.BASIC_ATTACK:
			var target = action.targets[0]
			return controller.basic_attack(unit, target) if target is BattleUnitState else controller.basic_attack_object(unit, target as BattleObjectState)
		EnemyIntentAction.Kind.MOVE:
			return controller.move_unit_to_cell(unit, action.cell)
	return false


func _execute_step(controller: BattleController, unit: BattleUnitState, step: Dictionary) -> bool:
	match str(step.get("type", "")):
		"card":
			var card := step.get("card") as CardData
			if card == null or not unit.hand.has(card):
				return false
			var targets: Array = step.get("targets", [])
			if not controller._targets_are_valid(unit, card, targets, false):
				return false
			unit.enemy_state.remember_seen_card(card)
			return controller.play_card(unit, card, targets)
		"basic_attack":
			var target := _find_unit(controller, int(step.get("target_id", -1)))
			return controller.basic_attack(unit, target) if target != null else false
		"move":
			return controller.move_unit_to_cell(unit, step.get("cell", BattleHexGrid.INVALID_CELL))
		"switch":
			return EnemyRuleDispatcher.execute_intent_step(controller, unit, step)
		"chapter_two_special":
			return EnemyRuleDispatcher.execute_intent_step(controller, unit, step)
	return false


func _find_unit(controller: BattleController, unit_id: int) -> BattleUnitState:
	for unit in controller.units:
		if unit != null and unit.unit_id == unit_id and unit.is_alive():
			return unit
	return null
