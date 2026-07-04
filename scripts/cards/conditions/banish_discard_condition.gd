extends CardPlayCondition
class_name BanishDiscardCondition

@export_range(0, 99, 1) var banish_count: int = 1


func _init() -> void:
	condition_name = "放逐弃牌堆"


func can_pay(context: Dictionary = {}) -> bool:
	var user := _get_user(context)
	if user == null:
		return false

	var card_to_exclude: CardData = context.get("card") as CardData
	return user.count_discard_cards_excluding(card_to_exclude) >= banish_count


func pay(context: Dictionary = {}) -> bool:
	if not can_pay(context):
		return false

	var user := _get_user(context)
	var card_to_exclude: CardData = context.get("card") as CardData
	var banished := user.banish_discard_cards(banish_count, card_to_exclude)

	var controller := _get_controller(context)
	if controller != null:
		controller._emit_log("%s 从弃牌堆放逐 %d 张牌。" % [user.get_display_name(), banished.size()])
	return banished.size() == banish_count


func get_description() -> String:
	return "从弃牌堆放逐 %d 张牌" % banish_count
