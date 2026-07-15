extends StatusEffect
class_name CurseUndyingStatus

var expires_turn_serial: int = -1


func _init() -> void:
	status_id = "curse_undying"
	display_name = "不死"


func get_lethal_health_floor(unit: BattleUnitState, _context: Dictionary = {}) -> int:
	if unit != null and unit.turn_serial <= expires_turn_serial:
		return 1
	return 0


func on_turn_end(unit: BattleUnitState, _context: Dictionary = {}) -> void:
	if unit != null and unit.turn_serial >= expires_turn_serial:
		stacks = 0
