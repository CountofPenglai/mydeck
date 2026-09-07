extends CardPlayCondition
class_name RangerSurfaceComboCondition


func _init() -> void:
	condition_name = "你位于元素地表"


func can_pay(context: Dictionary = {}) -> bool:
	var controller := _get_controller(context)
	var user := _get_user(context)
	return controller != null and user != null and controller.surface_state.get_element(user.cell) != BattleSurfaceState.Element.NONE


func get_description() -> String:
	return "你位于元素地表"
