extends StatusEffect
class_name RangerMoveSurchargeStatus

@export_range(1, 9, 1) var surcharge: int = 1
var expires_at_turn_end: bool = true


func _init() -> void:
	status_id = "ranger_move_surcharge"
	display_name = "冻结"


func modify_move_ap_cost(_unit: BattleUnitState, current_cost: int, _context: Dictionary = {}) -> int:
	return current_cost + surcharge if stacks > 0 else current_cost


func on_move_ap_cost_paid(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	stacks = 0


func on_turn_end(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	if expires_at_turn_end:
		stacks = 0
