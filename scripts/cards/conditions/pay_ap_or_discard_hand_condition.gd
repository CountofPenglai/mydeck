extends CardPlayCondition
class_name PayAPOrDiscardHandCondition

@export_range(0, 99, 1) var ap_amount: int = 1
@export_range(1, 99, 1) var discard_count: int = 1


func _init() -> void:
	condition_name = "支付 AP 或弃置手牌"


func can_pay(context: Dictionary = {}) -> bool:
	var user := _get_user(context)
	if user == null:
		return false
	if context.has("ordered_discard_cards"):
		var selected := _selected_cards(context)
		if selected.size() == discard_count:
			return _selection_is_valid(user, context, selected)
		return selected.is_empty() and user.current_ap >= ap_amount
	return user.current_ap >= ap_amount or _available_cards(user, context).size() >= discard_count


func pay(context: Dictionary = {}) -> bool:
	if not can_pay(context):
		return false
	var user := _get_user(context)
	var controller := _get_controller(context)
	var selected := _selected_cards(context)
	if selected.size() == discard_count:
		var discard_context := context.duplicate()
		discard_context["reason"] = "special_play_cost"
		for card in selected:
			user.discard_card(card, discard_context)
		if controller != null:
			controller._emit_log("%s 弃置 %d 张手牌。" % [user.get_display_name(), selected.size()])
		return true
	user.current_ap -= ap_amount
	if controller != null:
		controller._emit_log("%s 支付 %d AP。" % [user.get_display_name(), ap_amount])
	return true


func get_description() -> String:
	return "支付 %d AP 或弃置 %d 张牌" % [ap_amount, discard_count]


func _selected_cards(context: Dictionary) -> Array[CardData]:
	var result: Array[CardData] = []
	for value in context.get("ordered_discard_cards", []):
		if value is CardData:
			result.append(value as CardData)
	return result


func _selection_is_valid(user: BattleUnitState, context: Dictionary, selected: Array[CardData]) -> bool:
	var seen := {}
	var available := _available_cards(user, context)
	for card in selected:
		if card == null or seen.has(card) or not available.has(card):
			return false
		seen[card] = true
	return true


func _available_cards(user: BattleUnitState, context: Dictionary) -> Array[CardData]:
	var result: Array[CardData] = []
	var source_card := context.get("card") as CardData
	for card in user.hand:
		if card != null and card != source_card:
			result.append(card)
	return result
