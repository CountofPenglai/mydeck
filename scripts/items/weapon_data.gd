extends EquipmentData
class_name WeaponData

enum GripType {
	ONE_HAND,
	MAIN_HAND,
	OFF_HAND,
	TWO_HAND,
}

@export_enum("单手", "主手", "副手", "双手") var grip_type: int = GripType.ONE_HAND
@export var attack_bonus: int = 0
@export var attack_range: float = 80.0

func can_equip_main_hand() -> bool:
	return grip_type == GripType.ONE_HAND or grip_type == GripType.MAIN_HAND or grip_type == GripType.TWO_HAND


func can_equip_off_hand() -> bool:
	return grip_type == GripType.ONE_HAND or grip_type == GripType.OFF_HAND


func is_two_handed() -> bool:
	return grip_type == GripType.TWO_HAND


func get_grip_label() -> String:
	match grip_type:
		GripType.ONE_HAND:
			return "单手"
		GripType.MAIN_HAND:
			return "主手"
		GripType.OFF_HAND:
			return "副手"
		GripType.TWO_HAND:
			return "双手"
		_:
			return "未知"
