extends RefCounted
class_name StrikeProfile

var primary_slot: String = "unarmed"
var primary_weapon: WeaponData
var primary_power: int = 1
var primary_range: float = 0.0
var primary_weapon_type: int = WeaponData.WeaponType.MELEE
var damage_bonus: int = 0
var add_offhand: bool = false
var offhand_weapon: WeaponData
var offhand_power: int = 0


static func from_dict(values: Dictionary) -> StrikeProfile:
	var profile := StrikeProfile.new()
	profile.primary_slot = str(values.get("primary_slot", profile.primary_slot))
	profile.primary_weapon = values.get("primary_weapon")
	profile.primary_power = int(values.get("primary_power", profile.primary_power))
	profile.primary_range = float(values.get("primary_range", profile.primary_range))
	profile.primary_weapon_type = int(values.get("primary_weapon_type", profile.primary_weapon_type))
	profile.damage_bonus = int(values.get("damage_bonus", profile.damage_bonus))
	profile.add_offhand = bool(values.get("add_offhand", profile.add_offhand))
	profile.offhand_weapon = values.get("offhand_weapon")
	profile.offhand_power = int(values.get("offhand_power", profile.offhand_power))
	return profile


func to_dict() -> Dictionary:
	return {
		"primary_slot": primary_slot,
		"primary_weapon": primary_weapon,
		"primary_power": primary_power,
		"primary_range": primary_range,
		"primary_weapon_type": primary_weapon_type,
		"damage_bonus": damage_bonus,
		"add_offhand": add_offhand,
		"offhand_weapon": offhand_weapon,
		"offhand_power": offhand_power,
	}

