extends CardPlayCondition
class_name LoseHealthCondition

@export_range(0, 999, 1) var amount: int = 1
@export var allow_lethal: bool = false


func _init() -> void:
	condition_name = "失去生命"


func can_pay(context: Dictionary = {}) -> bool:
	var user := _get_user(context)
	if user == null:
		return false
	if allow_lethal:
		return user.get_current_health() > 0

	return user.get_current_health() > amount


func pay(context: Dictionary = {}) -> bool:
	if not can_pay(context):
		return false

	var user := _get_user(context)
	var old_health := user.get_current_health()
	user.set_current_health(maxi(0, old_health - amount))

	var controller := _get_controller(context)
	if controller != null:
		controller._emit_log("%s 失去 %d 点生命。" % [user.get_display_name(), old_health - user.get_current_health()])
	return true


func get_description() -> String:
	return "失去 %d 生命" % amount
