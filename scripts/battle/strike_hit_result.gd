extends RefCounted
class_name StrikeHitResult

var slot: String = ""
var equipment: EquipmentData
var damage_amount: int = 0
var actual_damage: int = 0


static func create(new_slot: String, new_equipment: EquipmentData, new_damage_amount: int, new_actual_damage: int) -> StrikeHitResult:
	var result := StrikeHitResult.new()
	result.slot = new_slot
	result.equipment = new_equipment
	result.damage_amount = new_damage_amount
	result.actual_damage = new_actual_damage
	return result


func to_dict() -> Dictionary:
	return {
		"slot": slot,
		"equipment": equipment,
		"damage_amount": damage_amount,
		"actual_damage": actual_damage,
	}
