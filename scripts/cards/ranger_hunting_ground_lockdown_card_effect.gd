extends RangerWeaponCardEffect
class_name RangerHuntingGroundLockdownCardEffect

func requires_enemy_intent_choice(context: Dictionary = {}) -> bool:
	return not context.has(RangerWaitingPreyCardEffect.CHOICE_KEY)


func get_enemy_intent_choice_options(context: Dictionary = {}) -> Array[Dictionary]:
	var base := RangerWaitingPreyCardEffect.new()
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	var slot := str(context.get("equipment_slot", ""))
	if slot.is_empty() and user != null:
		# Targetless hand availability must consider every selectable component.
		for weapon_option in user.get_attack_weapon_options():
			var probe := context.duplicate()
			probe["equipment_slot"] = str(weapon_option.get("slot", ""))
			if not get_enemy_intent_choice_options(probe).is_empty():
				return get_enemy_intent_choice_options(probe)
		return []
	var result: Array[Dictionary] = []
	for choice in base._options(context, true):
		var enemy: BattleUnitState = choice.get("enemy") as BattleUnitState
		if _can_strike_target(controller, user, card, enemy, slot, context):
			result.append(choice)
	return result


func _can_strike_target(controller: BattleController, user: BattleUnitState, card: CardData, enemy: BattleUnitState, slot: String, context: Dictionary) -> bool:
	if controller == null or user == null or card == null or enemy == null or slot.is_empty() or not user.is_ranger() \
			or not user.can_use_attack_mode(slot, {"controller": controller, "target": enemy}) \
			or controller.is_unit_concealed(enemy):
		return false
	var target_context := context.duplicate()
	target_context["controller"] = controller
	target_context["user"] = user
	target_context["card"] = card
	target_context["equipment_slot"] = slot
	if not target_context.has("play_mode"):
		target_context["play_mode"] = CardEnums.CardPlayMode.NORMAL
	if not enemy.can_be_targeted_by_other_card(user, card, target_context):
		return false
	if user.get_range_distance_to(enemy, {"controller": controller, "equipment_slot": slot}) > controller.get_effective_attack_range_against(user, enemy, slot):
		return false
	var profile := user.build_strike_profile_object(slot, {"controller": controller, "target": enemy})
	return profile.primary_range_type != EquipmentData.WeaponRangeType.RANGED or controller.targeting.has_line_of_sight_between_units(user, enemy)


func get_enemy_intent_choice_prompt(_context: Dictionary = {}) -> String:
	return "选择该武器射程内敌人的攻击意图"


func can_play(context: Dictionary = {}) -> bool:
	return not get_enemy_intent_choice_options(context).is_empty()


func can_pay_play_cost(context: Dictionary = {}) -> bool:
	var choice: Dictionary = context.get(RangerWaitingPreyCardEffect.CHOICE_KEY, {}) as Dictionary
	for option in get_enemy_intent_choice_options(context):
		if _matches(option, choice):
			return true
	return false


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	var choice: Dictionary = context.get(RangerWaitingPreyCardEffect.CHOICE_KEY, {}) as Dictionary
	if controller == null or user == null or card == null:
		return
	for option in get_enemy_intent_choice_options(context):
		if _matches(option, choice):
			var enemy: BattleUnitState = option.get("enemy") as BattleUnitState
			controller.steal_enemy_intent_ap(user, enemy, int(choice.get("slot_index", -1)), bool(choice.get("is_fallback", false)), 1)
			_enqueue_weapon_strike(context, enemy, "猎场封锁")
			return


func _matches(option: Dictionary, choice: Dictionary) -> bool:
	return int(option.get("enemy_id", -1)) == int(choice.get("enemy_id", -2)) and int(option.get("plan_id", -1)) == int(choice.get("plan_id", -2)) and int(option.get("slot_index", -1)) == int(choice.get("slot_index", -2)) and bool(option.get("is_fallback", false)) == bool(choice.get("is_fallback", false))
