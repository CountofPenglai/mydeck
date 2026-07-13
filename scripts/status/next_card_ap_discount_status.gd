extends StatusEffect
class_name NextCardApDiscountStatus


func _init() -> void:
	status_id = "next_card_ap_discount"
	display_name = "下一张牌 AP 减免"


func modify_card_ap_cost(_unit: BattleUnitState, _card: CardData, current_cost: int, _context: Dictionary = {}) -> int:
	return maxi(0, current_cost - stacks)


func on_card_ap_cost_paid(_unit: BattleUnitState, _card: CardData, _context: Dictionary = {}) -> void:
	stacks = 0
