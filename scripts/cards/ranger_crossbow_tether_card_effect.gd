extends CardEffect
class_name RangerCrossbowTetherCardEffect

const CROSSBOW_SLOT := "paired"

@export_range(1, 12, 1) var pull_distance: int = 2


func can_play(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and user.is_ranger() and _has_crossbow(user)


func are_targets_valid(context: Dictionary = {}, targets: Array = [], write_log: bool = true) -> bool:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null or targets.size() != 1:
		return false
	var target: BattleUnitState = targets[0] as BattleUnitState
	if target == null or not _has_crossbow(user):
		return false
	var attack_range := controller.get_effective_attack_range_against(user, target, CROSSBOW_SLOT)
	if user.cell_distance_to(target) <= attack_range:
		return true
	if write_log:
		controller._emit_log("%s 超出弩索牵引的弩射程。" % target.get_display_name())
	return false


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1:
		return
	var target: BattleUnitState = targets[0] as BattleUnitState
	if target == null:
		return

	controller.perform_strike(user, target, card, "弩索牵引", CROSSBOW_SLOT)
	if not target.is_alive():
		return
	controller.force_move_toward(target, user.cell, pull_distance, user)
	controller.collect_surface_elements(user, target.cell, "牵引终点")


func _has_crossbow(user: BattleUnitState) -> bool:
	var profile: StrikeProfile = user.build_strike_profile_object(CROSSBOW_SLOT)
	return profile.primary_equipment != null and profile.primary_equipment.has_tag("弩")
