extends StatusEffect
class_name RangerDaggerDamagePenaltyStatus


func _init() -> void:
	status_id = "ranger_dagger_damage_penalty"
	display_name = "回锋衰减"


func get_damage_bonus(_unit: BattleUnitState, context: Dictionary = {}) -> int:
	var equipment: EquipmentData = context.get("equipment") as EquipmentData
	if equipment == null or equipment.range_type != EquipmentData.WeaponRangeType.MELEE:
		return 0
	return -stacks


func on_turn_end(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	stacks = 0
