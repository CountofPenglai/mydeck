extends StatusEffect

var marker: Dictionary


func _init() -> void:
	status_id = "diagnostic_discard_listener"
	display_name = "弃牌回滚诊断"
	stacks = 1


func on_card_discarded(_unit: BattleUnitState, _card: CardData, _context: Dictionary = {}) -> void:
	if marker == null:
		return
	marker["count"] = int(marker.get("count", 0)) + 1
