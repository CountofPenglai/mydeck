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
	if context.has("ordered_discard_cards"):
		return _get_valid_selected_cards(context, user, card_to_exclude).size() == banish_count
	return user.count_discard_cards_excluding(card_to_exclude) >= banish_count


func pay(context: Dictionary = {}) -> bool:
	if not context.has("ordered_discard_cards") or not can_pay(context):
		return false

	var user := _get_user(context)
	var card_to_exclude: CardData = context.get("card") as CardData
	var banished: Array[CardData] = []
	for selected in _get_valid_selected_cards(context, user, card_to_exclude):
		if user.banish_discard_card(selected):
			banished.append(selected)

	var controller := _get_controller(context)
	if controller != null:
		controller._emit_log("%s 从弃牌堆放逐 %d 张牌。" % [user.get_display_name(), banished.size()])
	return banished.size() == banish_count


func get_description() -> String:
	return "从弃牌堆放逐 %d 张牌" % banish_count


func _get_valid_selected_cards(
	context: Dictionary,
	user: BattleUnitState,
	excluded_card: CardData
) -> Array[CardData]:
	var result: Array[CardData] = []
	var raw_selected = context.get("ordered_discard_cards", [])
	if not (raw_selected is Array) or (raw_selected as Array).size() != banish_count:
		return result
	var seen: Dictionary = {}
	for value in raw_selected as Array:
		if not (value is CardData):
			return []
		var selected := value as CardData
		if selected == excluded_card or seen.has(selected.get_instance_id()) \
				or not user.has_card_in_discard(selected):
			return []
		seen[selected.get_instance_id()] = true
		result.append(selected)
	return result
