extends CardPlayCondition
class_name PayAPCondition

@export_range(0, 99, 1) var amount: int = 1


func _init() -> void:
	condition_name = "支付 AP"


func can_pay(context: Dictionary = {}) -> bool:
	var user := _get_user(context)
	return user != null and user.current_ap >= amount


func pay(context: Dictionary = {}) -> bool:
	if not can_pay(context):
		return false

	var user := _get_user(context)
	user.current_ap -= amount

	var controller := _get_controller(context)
	if controller != null:
		controller._emit_log("%s 支付 %d AP。" % [user.get_display_name(), amount])
	return true


func get_description() -> String:
	return "支付 %d AP" % amount
