extends CardPlayCondition
class_name RangerOnlyHandComboCondition


func _init() -> void:
	condition_name = "本牌是唯一手牌"


func can_pay(context: Dictionary = {}) -> bool:
	var user := _get_user(context)
	var card: CardData = context.get("card") as CardData
	return user != null and card != null and user.hand.size() == 1 and user.hand[0] == card


func get_description() -> String:
	return "本牌是唯一手牌"
