extends StatusEffect
class_name NextMoveApDiscountStatus

@export_range(0, 99, 1) var discount_amount: int = 1


func _init() -> void:
	status_id = "next_move_ap_discount"
	display_name = "下次移动减费"


func modify_move_ap_cost(_unit: BattleUnitState, current_cost: int, _context: Dictionary = {}) -> int:
	if stacks <= 0:
		return current_cost

	return maxi(0, current_cost - discount_amount)


func on_move_ap_cost_paid(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	if stacks <= 0:
		return

	stacks = maxi(0, stacks - 1)
