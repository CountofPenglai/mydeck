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
	if controller == null or unit == null or unit.enemy_state == null:
		return {"action_started": false}
	var plan := unit.enemy_state.intent_plan
	while plan != null and not plan.forced_steps.is_empty():
		var step: Dictionary = plan.forced_steps.pop_front()
		var started := _execute_step(controller, unit, step)
		controller.state_changed.emit()
		if started:
			return {"action_started": true}
	if plan == null:
		return {"action_started": false}
	if unit.current_ap <= 0:
		plan.finish()
		return {"action_started": false}
	var profile := unit.enemy_state.enemy_data.ai_profile
	if profile == null:
		profile = EnemyAIProfile.create_preset(EnemyAIProfile.Preset.BALANCED)
	while not plan.is_finished():
		if plan.stage_start_ap < 0:
			plan.stage_start_ap = unit.current_ap
		if plan.stage_action_count >= profile.max_actions_per_intent:
			plan.advance_stage()
			continue
		var budget := _get_stage_ap_budget(unit, plan, profile)
		var action := EnemyIntentPlanner.choose_action(
			controller,
			unit,
			plan.get_current_category(),
			budget,
			plan.active_combo_tags
		)
		if action == null:
			plan.advance_stage()
			continue
		if not _execute_action(controller, unit, action):
			plan.advance_stage()
			continue
		plan.stage_action_count += 1
		for tag in action.provided_tags:
			if not plan.active_combo_tags.has(tag):
				plan.active_combo_tags.append(tag)
		controller.state_changed.emit()
		return {"action_started": true}
	return {"action_started": false}


func _get_stage_ap_budget(unit: BattleUnitState, plan: EnemyIntentPlan, profile: EnemyAIProfile) -> int:
	if plan.current_stage != EnemyIntentPlan.STAGE_PRIMARY_ONE:
		return unit.current_ap
	var allowed_total := mini(
		profile.primary_one_ap_budget,
		maxi(0, plan.stage_start_ap - profile.reserve_ap_for_primary_two)
	)
	var spent := maxi(0, plan.stage_start_ap - unit.current_ap)
	return mini(unit.current_ap, maxi(0, allowed_total - spent))


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
			return controller.basic_attack(unit, action.targets[0] as BattleUnitState)
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
