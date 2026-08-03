extends CardPlayCondition
class_name PreviousRoundBlockLostCondition

@export_range(0, 99, 1) var ap_amount: int = 2


func _init() -> void:
	condition_name = "支付 AP 或上一轮失去抵挡"


func can_pay(context: Dictionary = {}) -> bool:
	var user := _get_user(context)
	if user == null:
		return false
	var controller := _get_controller(context)
	var current_round := controller.battle_round if controller != null else -1
	return user.lost_block_in_previous_round(current_round) or user.current_ap >= ap_amount


func pay(context: Dictionary = {}) -> bool:
	if not can_pay(context):
		return false
	var user := _get_user(context)
	var controller := _get_controller(context)
	var current_round := controller.battle_round if controller != null else -1
	if user.lost_block_in_previous_round(current_round):
		if controller != null:
			controller._emit_log("%s 上一轮失去过抵挡，本次余势无消耗。" % user.get_display_name())
		return true
	user.current_ap -= ap_amount
	if controller != null:
		controller._emit_log("%s 支付 %d AP。" % [user.get_display_name(), ap_amount])
	return true


func get_description() -> String:
	return "支付 %d AP；若上一轮失去过抵挡则改为无消耗" % ap_amount
