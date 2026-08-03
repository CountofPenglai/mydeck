extends RangerWeaponCardEffect
class_name RangerPerilousAssaultCardEffect


func requires_ordered_discard_choice(context: Dictionary = {}) -> bool:
	return _is_combo(context) and not context.has("ordered_discard_cards")


func get_ordered_discard_choice_cards(context: Dictionary = {}) -> Array[CardData]:
	var result: Array[CardData] = []
	if not requires_ordered_discard_choice(context):
		return result
	var user := context.get("user") as BattleUnitState
	var source_card := context.get("card") as CardData
	if user == null:
		return result
	for card in user.hand:
		if card != null and card != source_card:
			result.append(card)
	return result


func get_ordered_discard_choice_max_count(context: Dictionary = {}) -> int:
	return mini(1, get_ordered_discard_choice_cards(context).size())


func get_ordered_discard_choice_min_count(context: Dictionary = {}) -> int:
	var user := context.get("user") as BattleUnitState
	return 0 if user != null and user.current_ap >= 1 else 1


func get_ordered_discard_choice_prompt(_context: Dictionary = {}) -> String:
	return "险步突袭连击：选择 1 张牌弃置；不选择并确认则支付 1 AP"


func play(context: Dictionary = {}, targets: Array = []) -> void:
	if targets.size() != 1 or not (targets[0] is BattleUnitState):
		return
	_enqueue_weapon_strike(context, targets[0] as BattleUnitState, "险步突袭", 0, 1.0, {}, effect_priority)
	_enqueue_combo_completion(context)


func _is_combo(context: Dictionary) -> bool:
	return int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) == CardEnums.CardPlayMode.COMBO
