extends EnemyBehavior
class_name TacticalEnemyBehavior


func lock_intent(context: Dictionary = {}, enemy_state = null) -> void:
	var controller := context.get("controller") as BattleController
	var unit := enemy_state as BattleUnitState
	if controller == null or unit == null or unit.enemy_state == null:
		return
	unit.enemy_state.intent_plan = EnemyIntentPlanner.build_plan(controller, unit, controller.battle_round + 1)
	controller.state_changed.emit()


func choose_action(context: Dictionary = {}, enemy_state = null) -> Dictionary:
	var controller := context.get("controller") as BattleController
	var unit := enemy_state as BattleUnitState
	if controller == null or unit == null or unit.enemy_state == null or unit.current_ap <= 0:
		return {"action_started": false}
	var plan := unit.enemy_state.intent_plan
	while plan != null and not plan.steps.is_empty():
		var step: Dictionary = plan.steps.pop_front()
		var started := _execute_step(controller, unit, step)
		controller.state_changed.emit()
		if started:
			return {"action_started": true}
	return {"action_started": false}


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
			return ChapterOneEnemyRules.switch_champion_weapon(controller, unit, _find_unit(controller, int(step.get("target_id", -1))))
	return false


func _find_unit(controller: BattleController, unit_id: int) -> BattleUnitState:
	for unit in controller.units:
		if unit != null and unit.unit_id == unit_id and unit.is_alive():
			return unit
	return null
