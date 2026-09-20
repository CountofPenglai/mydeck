extends CardEffect
class_name DruidBloodwoodCovenantCardEffect


const ROOT_STATUS := preload("res://scripts/status/druid_root_status.gd")
const TURN_DAMAGE_BONUS_STATUS := preload("res://scripts/status/druid_turn_damage_bonus_status.gd")


func _init() -> void:
	uses_strike = true


func requires_weapon_choice(context: Dictionary = {}) -> bool:
	return not _is_upright(context)


func is_unit_target_allowed(context: Dictionary = {}, target: BattleUnitState = null) -> bool:
	var user := context.get("user") as BattleUnitState
	if user == null or target == null:
		return false
	return target != user if _is_upright(context) else target.faction != user.faction


func are_targets_valid(context: Dictionary = {}, targets: Array = [], _write_log: bool = true) -> bool:
	return targets.size() == 1 and targets[0] is BattleUnitState and is_unit_target_allowed(context, targets[0] as BattleUnitState)


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1 or not (targets[0] is BattleUnitState):
		return
	var target := targets[0] as BattleUnitState
	if _is_upright(context):
		var amount := user.get_available_mana()
		if target.faction == user.faction:
			var bonus := TURN_DAMAGE_BONUS_STATUS.new() as StatusEffect
			bonus.stacks = amount
			target.add_status(bonus)
		else:
			_deal_intelligence_damage(controller, user, target, card, amount, "根脉结契")
		target.add_status(ROOT_STATUS.new())
		return
	var root_count := _count_rooted_in_weapon_range(controller, user, str(context.get("equipment_slot", "")))
	controller.perform_unit_strike_with_options_and_after_effects(
		user, target, card, root_count * 4, 1.0, "群根怒袭", str(context.get("equipment_slot", "")), {}, Callable()
	)


func _deal_intelligence_damage(controller: BattleController, user: BattleUnitState, target: BattleUnitState, card: CardData, base: int, label: String) -> int:
	var damage_context := {"controller": controller, "card": card, "target": target, "resolved_damage_type": CardEnums.DamageType.INTELLIGENCE, "source_card": card}
	return controller.apply_damage(user, target, base + user.get_damage_bonus(damage_context), label, damage_context)


func _count_rooted_in_weapon_range(controller: BattleController, user: BattleUnitState, equipment_slot: String) -> int:
	var count := 0
	for candidate_value in controller.units:
		var candidate := candidate_value as BattleUnitState
		if candidate == null or not candidate.is_alive() or not candidate.has_status("druid_root"):
			continue
		if user.get_range_distance_to(candidate, {"controller": controller, "equipment_slot": equipment_slot}) <= controller.get_effective_attack_range_against(user, candidate, equipment_slot):
			count += 1
	return count


func _is_upright(context: Dictionary) -> bool:
	return int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT)) == CardEnums.DruidOrientation.UPRIGHT
