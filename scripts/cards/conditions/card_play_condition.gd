extends Resource
class_name CardPlayCondition

@export var condition_name: String = "条件"


func can_pay(_context: Dictionary = {}) -> bool:
	return true


func pay(context: Dictionary = {}) -> bool:
	return can_pay(context)


func get_description() -> String:
	return condition_name


func _get_user(context: Dictionary) -> BattleUnitState:
	var user = context.get("user")
	if user is BattleUnitState:
		return user

	return null


func _get_controller(context: Dictionary) -> BattleController:
	var controller = context.get("controller")
	if controller is BattleController:
		return controller

	return null
