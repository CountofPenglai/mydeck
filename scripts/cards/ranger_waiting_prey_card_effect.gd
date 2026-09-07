extends CardEffect
class_name RangerWaitingPreyCardEffect

const CHOICE_KEY := "enemy_intent_choice"


func requires_enemy_intent_choice(context: Dictionary = {}) -> bool:
	return not context.has(CHOICE_KEY)


func get_enemy_intent_choice_options(context: Dictionary = {}) -> Array[Dictionary]:
	return _options(context, false)


func get_enemy_intent_choice_prompt(_context: Dictionary = {}) -> String:
	return "选择一个可削减的公开敌人意图"


func can_play(context: Dictionary = {}) -> bool:
	return _has_live_current_ranger(context) and not _options(context, false).is_empty()


func can_pay_play_cost(context: Dictionary = {}) -> bool:
	return _has_live_current_ranger(context) and not _resolve_choice(context, context.get(CHOICE_KEY, {}) as Dictionary).is_empty()


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var choice: Dictionary = context.get(CHOICE_KEY, {}) as Dictionary
	var target := _resolve_choice(context, choice)
	if not _has_live_current_ranger(context) or target.is_empty():
		return
	controller.steal_enemy_intent_ap(user, target.get("enemy") as BattleUnitState, int(choice.get("slot_index", -1)), bool(choice.get("is_fallback", false)), 1)


func _options(context: Dictionary, attacks_only: bool) -> Array[Dictionary]:
	var controller: BattleController = context.get("controller") as BattleController
	var result: Array[Dictionary] = []
	if not _has_live_current_ranger(context):
		return result
	for enemy in controller.enemy_units:
		if enemy == null or not enemy.is_alive() or enemy.enemy_state == null or enemy.enemy_state.intent_plan == null:
			continue
		var plan := enemy.enemy_state.intent_plan
		if plan.round_locked <= 0 or plan.execution_prepared or plan.is_finished() \
				or plan.stolen_ap_total >= enemy.get_max_ap(controller.config):
			continue
		for index in range(plan.primary_intents.size()):
			var reduction := int(plan.primary_ap_reductions[index]) if index < plan.primary_ap_reductions.size() else 0
			if (not attacks_only or plan.primary_intents[index] == EnemyIntentCategory.Type.ATTACK) and reduction < 2:
				result.append(_choice(enemy, plan, index, false, plan.get_primary_slot_display(index)))
		if (not attacks_only or plan.fallback_intent == EnemyIntentCategory.Type.ATTACK) and plan.fallback_ap_reduction < 2:
			result.append(_choice(enemy, plan, 0, true, plan.get_fallback_display()))
	return result


func _choice(enemy: BattleUnitState, plan, index: int, fallback: bool, label: String) -> Dictionary:
	return {"enemy": enemy, "enemy_id": enemy.get_instance_id(), "plan_id": plan.get_instance_id(), "slot_index": index, "is_fallback": fallback, "label": "%s · %s" % [enemy.get_display_name(), label]}


func _resolve_choice(context: Dictionary, choice: Dictionary) -> Dictionary:
	for option in _options(context, false):
		if int(option.get("enemy_id", -1)) == int(choice.get("enemy_id", -2)) and int(option.get("plan_id", -1)) == int(choice.get("plan_id", -2)) and int(option.get("slot_index", -1)) == int(choice.get("slot_index", -2)) and bool(option.get("is_fallback", false)) == bool(choice.get("is_fallback", false)):
			return option
	return {}


func _has_live_current_ranger(context: Dictionary) -> bool:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return controller != null and user != null and user.is_alive() and user.is_ranger() \
		and controller.current_unit == user
