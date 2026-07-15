extends CardEffect
class_name RangerTriPhaseDissectionCardEffect

const DAGGER_SLOT := "weapon"

@export_range(1, 9, 1) var strike_count: int = 3
@export_range(0, 99, 1) var replacement_base_damage: int = 1


func can_play(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and user.is_ranger() and _has_dagger(user)


func are_targets_valid(context: Dictionary = {}, _targets: Array = [], _write_log: bool = true) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and _has_dagger(user)


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1:
		return
	var target: BattleUnitState = targets[0] as BattleUnitState
	if target == null:
		return

	for strike_index in range(strike_count):
		if not target.is_alive():
			break
		controller.perform_strike_with_options(
			user,
			target,
			card,
			0,
			1.0,
			"三相解剖（%d/%d）" % [strike_index + 1, strike_count],
			DAGGER_SLOT,
			{"primary_base_damage_override": replacement_base_damage}
		)


func _has_dagger(user: BattleUnitState) -> bool:
	var profile: StrikeProfile = user.build_strike_profile_object(DAGGER_SLOT)
	return profile.primary_equipment != null and profile.primary_range_type == EquipmentData.WeaponRangeType.MELEE
