extends CardPlayCondition
class_name WarriorArmorMomentumCondition

@export_range(1, 99, 1) var minimum_armor: int = 1


func _init() -> void:
	condition_name = "具有护甲"


func can_pay(context: Dictionary = {}) -> bool:
	var user := _get_user(context)
	return user != null and user.get_armor_stacks() >= minimum_armor


func get_description() -> String:
	return "具有至少 %d 点护甲" % minimum_armor
