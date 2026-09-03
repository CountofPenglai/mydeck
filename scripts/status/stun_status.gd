extends StatusEffect
class_name StunStatus

const INCOMING_DAMAGE_BONUS := 2
const OUTGOING_DAMAGE_PENALTY := 2


func _init() -> void:
	status_id = "stun"
	is_corruptible_counter = true
	display_name = "眩晕"


func modify_incoming_damage(_unit: BattleUnitState, context: DamageContext) -> void:
	if stacks > 0 and context != null:
		context.amount += INCOMING_DAMAGE_BONUS


func modify_outgoing_damage(_unit: BattleUnitState, context: DamageContext) -> void:
	if stacks > 0 and context != null:
		context.amount = maxi(0, context.amount - OUTGOING_DAMAGE_PENALTY)


func modify_move_distance_per_ap(
	_unit: BattleUnitState,
	current_distance: int,
	_context: Dictionary = {}
) -> int:
	return maxi(1, ceili(float(current_distance) / 2.0)) if stacks > 0 else current_distance


func on_ap_action_completed(
	unit: BattleUnitState,
	ap_spent: int,
	context: Dictionary = {}
) -> void:
	_remove_stacks(unit, ap_spent, context, "行动消耗")


func on_turn_end(unit: BattleUnitState, context: Dictionary = {}) -> void:
	_remove_stacks(unit, 1, context, "回合结束")


func _remove_stacks(
	unit: BattleUnitState,
	amount: int,
	context: Dictionary,
	reason: String
) -> void:
	if unit == null or stacks <= 0 or amount <= 0:
		return

	var removed := mini(stacks, amount)
	stacks -= removed

	var controller = context.get("controller")
	if controller != null and controller.has_method("_emit_log"):
		controller._emit_log("%s 因%s解除 %d 层眩晕。" % [unit.get_display_name(), reason, removed])
