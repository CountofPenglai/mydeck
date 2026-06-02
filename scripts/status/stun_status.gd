extends StatusEffect
class_name StunStatus

func _init() -> void:
	status_id = "stun"
	display_name = "眩晕"


func on_turn_start(unit: BattleUnitState, _context: Dictionary = {}) -> void:
	if unit == null:
		return

	var lost_ap := mini(unit.current_ap, stacks)
	unit.current_ap = maxi(0, unit.current_ap - stacks)
	stacks = 0

	var controller = _context.get("controller")
	if lost_ap > 0 and controller != null and controller.has_method("_emit_log"):
		controller._emit_log("%s 因眩晕失去 %d AP。" % [unit.get_display_name(), lost_ap])
