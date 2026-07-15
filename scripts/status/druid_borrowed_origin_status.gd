extends StatusEffect
class_name DruidBorrowedOriginStatus

var source_unit: BattleUnitState
var source_turn_serial: int = -1


func _init() -> void:
	display_name = "借域"


func get_alternate_range_origins(_unit: BattleUnitState, _context: Dictionary = {}) -> Array[Vector2i]:
	if should_remove():
		return []
	return [source_unit.cell]


func should_remove() -> bool:
	return stacks <= 0 \
		or source_unit == null \
		or not source_unit.is_alive() \
		or not source_unit.is_deployed \
		or source_unit.turn_serial != source_turn_serial
