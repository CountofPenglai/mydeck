extends RefCounted
class_name StrikeProfile

var primary_slot: String = "unarmed"
var primary_equipment: EquipmentData
var primary_base_damage: int = 1
var primary_range: int = 0
var primary_range_type: int = EquipmentData.WeaponRangeType.MELEE
var primary_damage_type: int = CardEnums.DamageType.STRENGTH
var primary_damage_bonus: int = 0
var add_offhand: bool = false
var offhand_equipment: EquipmentData
var offhand_base_damage: int = 0
var offhand_damage_bonus: int = 0
var offhand_damage_type: int = CardEnums.DamageType.STRENGTH


func to_dict() -> Dictionary:
	return {
		"primary_slot": primary_slot,
		"primary_equipment": primary_equipment,
		"primary_base_damage": primary_base_damage,
		"primary_range": primary_range,
		"primary_range_type": primary_range_type,
		"primary_damage_type": primary_damage_type,
		"primary_damage_bonus": primary_damage_bonus,
		"add_offhand": add_offhand,
		"offhand_equipment": offhand_equipment,
		"offhand_base_damage": offhand_base_damage,
		"offhand_damage_bonus": offhand_damage_bonus,
		"offhand_damage_type": offhand_damage_type,
	}
