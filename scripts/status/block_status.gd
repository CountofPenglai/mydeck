extends StatusEffect
class_name BlockStatus

func _init() -> void:
	status_id = "block"
	display_name = "抵挡"


func on_before_damage(unit: BattleUnitState, damage_context: DamageContext) -> void:
	if unit == null or damage_context == null or stacks <= 0 or damage_context.prevented:
		return

	damage_context.prevent(self)
	stacks = maxi(0, stacks - 1)

	var controller = damage_context.controller
	if controller != null and controller.has_method("_emit_log"):
		controller._emit_log("%s 抵挡了伤害。" % unit.get_display_name())

	if controller != null and controller.has_method("queue_unit_status_event"):
		controller.queue_unit_status_event("on_block_spent", unit, damage_context)


func on_turn_start(unit: BattleUnitState, _context: Dictionary = {}) -> void:
	if unit != null and stacks > 0:
		var controller = _context.get("controller")
		if controller != null and controller.has_method("_emit_log"):
			controller._emit_log("%s 失去所有抵挡。" % unit.get_display_name())
	stacks = 0
