extends CardPlayCondition
class_name RangerDaggerPenaltyComboCondition

const PENALTY_STATUS := preload("res://scripts/status/ranger_dagger_damage_penalty_status.gd")

@export_range(1, 20, 1) var damage_penalty: int = 2


func _init() -> void:
	condition_name = "匕首本回合伤害加值 -2"


func can_pay(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = _get_user(context)
	return user != null and user.is_ranger()


func pay(context: Dictionary = {}) -> bool:
	if not can_pay(context):
		return false
	var user: BattleUnitState = _get_user(context)
	var controller: BattleController = _get_controller(context)
	if controller == null:
		_apply_penalty(user)
	else:
		controller.enqueue_effect(
			Callable(self, "_apply_penalty"),
			[user],
			0,
			"回锋不止：匕首伤害衰减",
			context
		)
	return true


func get_description() -> String:
	return "匕首本回合伤害加值 -%d（可叠加）" % damage_penalty


func _apply_penalty(user: BattleUnitState) -> void:
	if user == null:
		return
	var status := PENALTY_STATUS.new() as StatusEffect
	status.stacks = damage_penalty
	user.add_status(status)
