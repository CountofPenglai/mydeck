extends CardPlayCondition
class_name RangerElementsCollectedCondition

@export_range(1, 99, 1) var required_count: int = 3


func _init() -> void:
	condition_name = "本回合实际采集元素"


func can_pay(context: Dictionary = {}) -> bool:
	var user := _get_user(context)
	return user != null and user.is_ranger() and user.ranger_state.elements_collected_this_turn >= required_count


func get_description() -> String:
	return "本回合实际采集的元素至少 %d 枚" % required_count
