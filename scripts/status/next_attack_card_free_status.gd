extends StatusEffect
class_name NextAttackCardFreeStatus


func _init() -> void:
	status_id = "next_attack_card_free"
	display_name = "下一张攻击牌免费"


func modify_card_ap_cost(_unit: BattleUnitState, card: CardData, current_cost: int, _context: Dictionary = {}) -> int:
	if stacks <= 0 or card == null or not card.is_attack_card():
		return current_cost

	return 0


func on_card_ap_cost_paid(_unit: BattleUnitState, card: CardData, _context: Dictionary = {}) -> void:
	if stacks <= 0 or card == null or not card.is_attack_card():
		return

	stacks = maxi(0, stacks - 1)
