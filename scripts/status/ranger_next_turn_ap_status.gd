extends StatusEffect
class_name RangerNextTurnApStatus


func _init() -> void:
	status_id = "ranger_next_turn_ap"
	display_name = "潜踪整备"


func on_turn_start(unit: BattleUnitState, context: Dictionary = {}) -> void:
	if unit == null or stacks <= 0:
		return
	var granted := stacks
	unit.current_ap += granted
	stacks = 0
	var controller: BattleController = context.get("controller") as BattleController
	if controller != null:
		controller._emit_log("%s 的潜踪整备生效，获得 %d AP。" % [unit.get_display_name(), granted])
