extends CardPlayCondition
class_name RangerOtherHandCountCondition

@export_range(0, 20, 1) var minimum_other_cards: int = 6


func _init() -> void:
	condition_name = "其他手牌数量"


func can_pay(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = _get_user(context)
	var source_card: CardData = context.get("card") as CardData
	if user == null:
		return false
	var count := 0
	for card: CardData in user.hand:
		if card != null and card != source_card:
			count += 1
	return count >= minimum_other_cards


func get_description() -> String:
	return "其他手牌不少于 %d 张" % minimum_other_cards
