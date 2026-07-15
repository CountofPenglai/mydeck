extends CardEffect
class_name RangerExoticSamplingCardEffect


func _init() -> void:
	uses_strike = true


func can_play(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and user.is_ranger()


func are_targets_valid(context: Dictionary = {}, _targets: Array = [], _write_log: bool = true) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if user == null:
		return false
	return not _get_weapon_mode(user, str(context.get("equipment_slot", "")), context).is_empty()


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1:
		return
	var target: BattleUnitState = targets[0] as BattleUnitState
	if target == null:
		return

	var equipment_slot := str(context.get("equipment_slot", ""))
	var mode := _get_weapon_mode(user, equipment_slot, context)
	if mode.is_empty():
		return
	var actual_damage := controller.perform_strike(user, target, card, "异域取样", equipment_slot)
	if actual_damage <= 0:
		return

	if mode == "melee":
		# 近战对目标格的通用采集已由 resolve_ranger_after_strike 完成。
		controller.collect_surface_elements(user, user.cell, "游侠当前")
	else:
		controller.collect_surface_elements(user, target.cell, "目标")


func _get_weapon_mode(user: BattleUnitState, equipment_slot: String, context: Dictionary) -> String:
	var profile: StrikeProfile = user.build_strike_profile_object(equipment_slot, context)
	if profile.primary_equipment == null:
		return ""
	return "melee" if profile.primary_range_type == EquipmentData.WeaponRangeType.MELEE else "ranged"
