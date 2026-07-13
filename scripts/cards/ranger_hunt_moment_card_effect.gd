extends RangerWeaponCardEffect
class_name RangerHuntMomentCardEffect

@export_range(0.0, 1.0, 0.05) var health_threshold_ratio: float = 0.5
@export_range(1.0, 5.0, 0.1) var threshold_damage_multiplier: float = 2.0
@export_range(0, 12, 1) var crossbow_range_bonus: int = 2


func are_targets_valid(context: Dictionary = {}, targets: Array = [], write_log: bool = true) -> bool:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null or targets.size() != 1 or not (targets[0] is BattleUnitState):
		return false

	var target: BattleUnitState = targets[0] as BattleUnitState
	if target == null or not target.is_alive() or target.faction == user.faction:
		if write_log:
			controller._emit_log("请选择一个存活的敌方目标。")
		return false

	var equipment_slot: String = str(context.get("equipment_slot", ""))
	var profile: StrikeProfile = user.build_strike_profile_object(equipment_slot, {})
	var allowed_range: int = profile.primary_range
	if _is_crossbow(profile):
		allowed_range += crossbow_range_bonus
	var distance: int = user.cell_distance_to(target)
	if distance > allowed_range:
		if write_log:
			controller._emit_log("%s 距离 %d，超出猎杀时刻射程 %d。" % [target.get_display_name(), distance, allowed_range])
		return false
	return true


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null or targets.size() != 1 or not (targets[0] is BattleUnitState):
		return

	var target: BattleUnitState = targets[0] as BattleUnitState
	var equipment_slot: String = str(context.get("equipment_slot", ""))
	var profile: StrikeProfile = user.build_strike_profile_object(equipment_slot, {})
	var damage_multiplier: float = threshold_damage_multiplier if _is_below_health_threshold(target) else 1.0
	var dagger_strike: bool = _is_dagger(profile)
	var strike_options := {"ignore_ranged_surface_reduction": _is_crossbow(profile)}
	_enqueue_weapon_strike(context, target, "猎杀时刻", 0, damage_multiplier, strike_options, effect_priority)
	if dagger_strike:
		controller.enqueue_effect(
			Callable(self, "_enter_stealth_after_dagger_kill"),
			[controller, user, target],
			effect_priority,
			"猎杀时刻：匕首击杀判定",
			context
		)


func _is_below_health_threshold(target: BattleUnitState) -> bool:
	if target == null:
		return false
	var max_health: int = target.get_max_health()
	if max_health <= 0:
		return false
	return float(target.get_current_health()) / float(max_health) <= health_threshold_ratio


func _enter_stealth_after_dagger_kill(controller: BattleController, user: BattleUnitState, target: BattleUnitState) -> void:
	if controller == null or user == null or target == null or target.is_alive():
		return
	controller.enter_ranger_stealth(user, "猎杀回身")


func _is_dagger(profile: StrikeProfile) -> bool:
	return profile != null and profile.primary_equipment != null and profile.primary_equipment.has_tag("匕首")


func _is_crossbow(profile: StrikeProfile) -> bool:
	return profile != null and profile.primary_equipment != null and profile.primary_equipment.has_tag("弩")
