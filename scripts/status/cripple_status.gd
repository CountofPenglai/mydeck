extends StatusEffect
class_name CrippleStatus


func _init() -> void:
	status_id = "cripple"
	display_name = "致残"


func modify_move_distance_per_ap(_unit: BattleUnitState, current_distance: int, _context: Dictionary = {}) -> int:
	if stacks <= 0:
		return current_distance

	return maxi(1, ceili(float(current_distance) * 0.5))


func on_turn_start(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	stacks = maxi(0, stacks - 1)
