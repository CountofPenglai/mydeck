extends StatusEffect
class_name RangerDiscardDebtStatus


func _init() -> void:
	status_id = "ranger_discard_debt"
	display_name = "弃牌债务"


func on_turn_end(unit: BattleUnitState, context: Dictionary = {}) -> void:
	if unit == null or not unit.is_ranger():
		stacks = 0
		return
	var debt := maxi(0, unit.ranger_state.discard_debt)
	if debt <= 0:
		stacks = 0
		return
	var selected := _selected_cards(unit, context, debt)
	if selected.is_empty():
		# 当前回合结束流程没有多选 UI 上下文；按手牌顺序确定性回退。
		for card: CardData in unit.hand:
			if card != null:
				selected.append(card)
				if selected.size() >= debt:
					break
	var discarded := 0
	for card: CardData in selected:
		if discarded >= debt:
			break
		if unit.discard_card(card, {
			"controller": context.get("controller"),
			"reason": "ranger_discard_debt",
			"source": unit,
		}):
			discarded += 1
	unit.ranger_state.discard_debt = 0
	stacks = 0
	var controller: BattleController = context.get("controller") as BattleController
	if controller != null:
		controller._emit_log("%s 偿还弃牌债务，弃置 %d 张牌。" % [unit.get_display_name(), discarded])


func _selected_cards(unit: BattleUnitState, context: Dictionary, maximum: int) -> Array[CardData]:
	var result: Array[CardData] = []
	var raw: Variant = context.get("ordered_discard_cards", [])
	if not (raw is Array):
		return result
	for value: Variant in raw as Array:
		if value is CardData and unit.has_card_in_hand(value as CardData):
			result.append(value as CardData)
			if result.size() >= maximum:
				break
	return result
