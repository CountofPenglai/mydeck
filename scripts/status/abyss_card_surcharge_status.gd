extends StatusEffect
class_name AbyssCardSurchargeStatus

var paid_turn_serial: int = -1


func _init() -> void:
	status_id = "abyss_card_surcharge"
	display_name = "深渊压迫"
	stacks = 1


func modify_card_ap_cost(unit: BattleUnitState, card: CardData, current_cost: int, _context: Dictionary = {}) -> int:
	if unit == null or card == null or card.is_curse_card() or paid_turn_serial == unit.turn_serial:
		return current_cost
	return current_cost + 1


func on_card_ap_cost_paid(unit: BattleUnitState, card: CardData, _context: Dictionary = {}) -> void:
	if unit != null and card != null and not card.is_curse_card() and paid_turn_serial != unit.turn_serial:
		paid_turn_serial = unit.turn_serial

