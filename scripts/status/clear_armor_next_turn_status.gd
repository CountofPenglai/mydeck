extends StatusEffect
class_name ClearArmorNextTurnStatus


func _init() -> void:
	status_id = "clear_armor_next_turn"
	display_name = "伤铸壁垒"


func on_turn_start(unit: BattleUnitState, context: Dictionary = {}) -> void:
	if unit == null or stacks <= 0:
		return
	var controller: BattleController = context.get("controller") as BattleController
	var removed := unit.clear_armor({
		"controller": controller,
		"reason": "wound_forged_bulwark_expired",
	})
	if controller != null and removed > 0:
		controller._emit_log("%s 的伤铸壁垒到期，失去 %d 护甲。" % [unit.get_display_name(), removed])
	stacks = 0
