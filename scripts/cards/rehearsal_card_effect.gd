extends CardEffect
class_name RehearsalCardEffect

@export_range(0, 99, 1) var mill_count: int = 5
@export_range(0, 99, 1) var heal_amount: int = 5
@export_range(-99, 0, 1) var temporary_ap_delta: int = -2


func requires_ordered_discard_choice(context: Dictionary = {}) -> bool:
	return int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) == CardEnums.CardPlayMode.MOMENTUM


func get_ordered_discard_choice_cards(context: Dictionary = {}) -> Array[CardData]:
	var result: Array[CardData] = []
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var source_card: CardData = context.get("card") as CardData
	if user == null:
		return result
	for card in user.discard_pile:
		if card != null and card != source_card:
			result.append(card)
	return result


func get_ordered_discard_choice_max_count(_context: Dictionary = {}) -> int:
	return 1


func get_ordered_discard_choice_min_count(_context: Dictionary = {}) -> int:
	return 1


func get_ordered_discard_choice_prompt(_context: Dictionary = {}) -> String:
	return "选择 1 张其他弃牌加入手牌；本回合费用 -2，回合结束前必定放逐。"


func can_play(context: Dictionary = {}) -> bool:
	if int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) != CardEnums.CardPlayMode.MOMENTUM:
		return true
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if user == null:
		return false
	var selected := _selected_card(context)
	if selected == null and not context.has("ordered_discard_cards"):
		return not get_ordered_discard_choice_cards(context).is_empty()
	return selected != null and user.has_card_in_discard(selected)


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null:
		return
	if int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) == CardEnums.CardPlayMode.MOMENTUM:
		_play_momentum(controller, user, context)
		return

	var milled := user.mill_cards(mill_count, context)
	controller._emit_log("%s 预演并磨了 %d 张牌。" % [user.get_display_name(), milled.size()])
	controller.heal_unit(user, user, heal_amount, "预演治疗")


func _play_momentum(controller: BattleController, user: BattleUnitState, context: Dictionary) -> void:
	var selected := _selected_card(context)
	if selected == null or not user.move_discard_card_to_hand(selected):
		return
	user.mark_temporary_card(selected, temporary_ap_delta, true, true)
	controller._emit_log("%s 复演 %s：本回合 AP 消耗 -%d，回合结束前必定放逐。" % [
		user.get_display_name(),
		selected.card_name,
		absi(temporary_ap_delta),
	])


func _selected_card(context: Dictionary) -> CardData:
	var selected_value = context.get("ordered_discard_cards", [])
	if not (selected_value is Array):
		return null
	var selected := selected_value as Array
	if selected.size() != 1 or not (selected[0] is CardData):
		return null
	return selected[0] as CardData
