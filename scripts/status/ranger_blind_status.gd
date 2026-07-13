extends StatusEffect
class_name RangerBlindStatus

@export_range(1, 12, 1) var maximum_range: int = 2
var remaining_turn_ends: int = 1


func _init() -> void:
	status_id = "ranger_blind"
	display_name = "致盲"


func modify_attack_range(_unit: BattleUnitState, current_range: int, context: Dictionary = {}) -> int:
	if int(context.get("range_type", EquipmentData.WeaponRangeType.MELEE)) != EquipmentData.WeaponRangeType.RANGED:
		return current_range
	return mini(current_range, maximum_range)


func on_turn_end(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	remaining_turn_ends -= 1
	if remaining_turn_ends <= 0:
		stacks = 0
