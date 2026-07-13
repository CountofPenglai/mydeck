extends CardPlayCondition
class_name RangerSelectedDiscardComboCondition

@export_range(1, 9, 1) var discard_count: int = 2


func _init() -> void:
	condition_name = "弃置 2 张其他手牌"


func can_pay(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = _get_user(context)
	var source_card: CardData = context.get("card") as CardData
	if user == null:
		return false
	var selected := _selected_cards(context)
	if not selected.is_empty():
		return selected.size() == discard_count and selected.all(func(card: CardData) -> bool:
			return card != source_card and user.has_card_in_hand(card)
		)
	var available := 0
	for card: CardData in user.hand:
		if card != null and card != source_card:
			available += 1
	return available >= discard_count


func pay(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = _get_user(context)
	var source_card: CardData = context.get("card") as CardData
	var controller: BattleController = context.get("controller") as BattleController
	var selected := _selected_cards(context)
	if user == null or selected.size() != discard_count:
		return false
	for card in selected:
		if card == source_card or not user.has_card_in_hand(card):
			return false
	for card in selected:
		if not user.discard_card(card, {
			"controller": controller,
			"reason": "ranger_seamless_pursuit_combo",
			"source_card": source_card,
		}):
			return false
	return true


func _selected_cards(context: Dictionary) -> Array[CardData]:
	var result: Array[CardData] = []
	var raw: Variant = context.get("ordered_discard_cards", [])
	if raw is Array:
		for value in raw as Array:
			if value is CardData and not result.has(value as CardData):
				result.append(value as CardData)
	return result


func get_description() -> String:
	return "选择并弃置 %d 张其他手牌" % discard_count
