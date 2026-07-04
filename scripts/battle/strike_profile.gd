extends RefCounted
class_name StrikeProfile

var primary_slot: String = "unarmed"
var primary_equipment: EquipmentData
var primary_power: int = 1
var primary_range: float = 0.0
var primary_range_type: int = EquipmentData.WeaponRangeType.MELEE
var damage_bonus: int = 0
var add_offhand: bool = false
var offhand_equipment: EquipmentData
var offhand_power: int = 0


func to_dict() -> Dictionary:
	return {
		"primary_slot": primary_slot,
		"primary_equipment": primary_equipment,
		"primary_power": primary_power,
		"primary_range": primary_range,
		"primary_range_type": primary_range_type,
		"damage_bonus": damage_bonus,
		"add_offhand": add_offhand,
		"offhand_equipment": offhand_equipment,
		"offhand_power": offhand_power,
	}
