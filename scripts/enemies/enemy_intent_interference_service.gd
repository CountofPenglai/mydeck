extends RefCounted
class_name EnemyIntentInterferenceService


static func steal_enemy_intent_ap(
		controller: BattleController,
		thief: BattleUnitState,
		target: BattleUnitState,
		slot_index: int,
		is_fallback: bool,
		requested: int
	) -> int:
	if controller == null or thief == null or target == null:
		return 0
	if not thief.is_alive() or thief.faction != BattleUnitState.Faction.PLAYER \
			or thief.character_state == null or not thief.is_ranger() or thief != controller.current_unit:
		return 0
	if controller.phase != BattleController.Phase.BATTLE \
			or controller.turn_flow_state != BattleController.TurnFlowState.ACTIVE:
		return 0
	if not target.is_alive() or target.faction != BattleUnitState.Faction.ENEMY \
			or target.enemy_state == null or target.enemy_state.intent_plan == null:
		return 0

	var plan: EnemyIntentPlan = target.enemy_state.intent_plan
	if plan.round_locked <= 0 or plan.execution_prepared or plan.is_finished():
		return 0
	var actual_stolen := plan.reduce_public_intent_budget(
		slot_index,
		is_fallback,
		requested,
		target.get_max_ap(controller.config)
	)
	if actual_stolen <= 0:
		return 0

	thief.current_ap += actual_stolen
	controller._emit_log("%s 从 %s 的%s偷取 %d AP。" % [
		thief.get_display_name(),
		target.get_display_name(),
		_get_slot_label(plan, slot_index, is_fallback),
		actual_stolen,
	])
	controller.state_changed.emit()
	return actual_stolen


static func _get_slot_label(plan: EnemyIntentPlan, slot_index: int, is_fallback: bool) -> String:
	if is_fallback:
		return "备用%s意图" % EnemyIntentCategory.get_label(plan.fallback_intent)
	if slot_index >= 0 and slot_index < plan.primary_intents.size():
		return "主%d %s意图" % [slot_index + 1, EnemyIntentCategory.get_label(plan.primary_intents[slot_index])]
	return "公开意图"
