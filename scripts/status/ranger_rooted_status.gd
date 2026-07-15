extends StatusEffect
class_name RangerRootedStatus

var expires_on_turn_serial: int = -1


func _init() -> void:
	status_id = "ranger_rooted"
	display_name = "定身"


func can_start_voluntary_movement(_unit: BattleUnitState) -> bool:
	return false


func on_turn_end(unit: BattleUnitState, _context: Dictionary = {}) -> void:
	if unit != null and expires_on_turn_serial >= 0 and unit.turn_serial >= expires_on_turn_serial:
		stacks = 0
