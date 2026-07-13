extends CardPlayCondition
class_name RangerStunComboCondition

const STUN_STATUS := preload("res://scripts/status/stun_status.gd")

@export_range(1, 9, 1) var stun_stacks: int = 1


func _init() -> void:
	condition_name = "获得眩晕 1"


func can_pay(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = _get_user(context)
	return user != null and user.is_ranger()


func pay(context: Dictionary = {}) -> bool:
	if not can_pay(context):
		return false
	var user: BattleUnitState = _get_user(context)
	var controller: BattleController = _get_controller(context)
	if controller == null:
		_apply_stun(user)
	else:
		controller.enqueue_effect(
			Callable(self, "_apply_stun"),
			[user],
			0,
			"险步突袭：获得眩晕",
			context
		)
	return true


func get_description() -> String:
	return "获得眩晕 %d" % stun_stacks


func _apply_stun(user: BattleUnitState) -> void:
	if user == null:
		return
	var status := STUN_STATUS.new() as StatusEffect
	status.stacks = stun_stacks
	user.add_status(status)
