extends StatusEffect
class_name DruidDelayedDamageStatus


func _init() -> void:
	status_id = "druid_anomaly"
	is_corruptible_counter = true
	display_name = "异常"


func on_turn_start(unit: BattleUnitState, context: Dictionary = {}) -> void:
	if unit == null or stacks <= 0:
		return
	var loss := mini(stacks, unit.get_current_health())
	unit.set_current_health(unit.get_current_health() - stacks)
	stacks = 0
	var controller := context.get("controller") as BattleController
	if controller != null and loss > 0:
		controller._emit_log("%s 的异常爆发，失去 %d 点生命。" % [unit.get_display_name(), loss])
