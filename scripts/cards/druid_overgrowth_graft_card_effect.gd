extends CardEffect
class_name DruidOvergrowthGraftCardEffect


func _init() -> void:
	uses_strike = true


func requires_weapon_choice(context: Dictionary = {}) -> bool:
	return _orientation(context) == CardEnums.DruidOrientation.INVERTED


func is_unit_target_allowed(context: Dictionary = {}, target: BattleUnitState = null) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if user == null or target == null or target == user:
		return false
	if _orientation(context) == CardEnums.DruidOrientation.INVERTED:
		return target.faction != user.faction
	return true


func requires_ordered_discard_choice(context: Dictionary = {}) -> bool:
	return _orientation(context) == CardEnums.DruidOrientation.UPRIGHT and not get_ordered_discard_choice_cards(context).is_empty()


func get_ordered_discard_choice_cards(context: Dictionary = {}) -> Array[CardData]:
	var result: Array[CardData] = []
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if user != null:
		for hand_card in user.hand:
			if hand_card != null and hand_card != card:
				result.append(hand_card)
	return result


func get_ordered_discard_choice_max_count(context: Dictionary = {}) -> int:
	return mini(1, get_ordered_discard_choice_cards(context).size())


func get_ordered_discard_choice_min_count(_context: Dictionary = {}) -> int:
	return 0


func get_ordered_discard_choice_prompt(_context: Dictionary = {}) -> String:
	return "繁生嫁接：可以选择 1 张额外移植的手牌"


func are_targets_valid(context: Dictionary = {}, targets: Array = [], _write_log: bool = true) -> bool:
	if targets.size() != 1 or not (targets[0] is BattleUnitState):
		return false
	if not is_unit_target_allowed(context, targets[0] as BattleUnitState):
		return false
	var selected := _selected_card(context)
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	return selected == null or (selected != card and user != null and user.has_card_in_hand(selected))


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null or targets.is_empty():
		return
	var target := targets[0] as BattleUnitState
	if _orientation(context) == CardEnums.DruidOrientation.UPRIGHT:
		_play_upright(context, controller, user, target, card)
		return

	var total_lifesteal := controller.perform_strike(user, target, card, "过量生长", str(context.get("equipment_slot", "")))
	if total_lifesteal > 0 and target.is_alive():
		total_lifesteal += controller.perform_strike(user, target, card, "过量生长连击", str(context.get("equipment_slot", "")))
	if total_lifesteal > 0:
		controller.heal_unit(user, user, total_lifesteal, "过量生长吸血")


func on_zone_owner_mana_gained(owner: BattleUnitState, zone_card: CardData, _amount: int, context: Dictionary = {}) -> void:
	if owner == null or zone_card == null or str(context.get("zone_name", "")) != "mana":
		return
	if str(context.get("reason", "")) == "druid_overgrowth_bonus":
		return
	if context.get("source_card") == zone_card:
		return
	var bonus_context := context.duplicate()
	bonus_context["reason"] = "druid_overgrowth_bonus"
	bonus_context["source_card"] = zone_card
	owner.gain_temporary_mana(1, bonus_context)
	var controller: BattleController = context.get("controller") as BattleController
	if controller != null:
		controller._emit_log("%s 的 %s 触发，额外获得 1 点本回合临时法力。" % [owner.get_display_name(), zone_card.card_name])


func _play_upright(context: Dictionary, controller: BattleController, user: BattleUnitState, target: BattleUnitState, card: CardData) -> void:
	var zone_context := context.duplicate()
	zone_context["source_card"] = card
	var card_index := user.hand.find(card)
	if card_index < 0:
		return
	user.hand.remove_at(card_index)
	target.add_card_to_mana_zone(card, zone_context)
	var selected := _selected_card(context)
	var destination := ""
	if selected != null and user.has_card_in_hand(selected):
		var selected_context := context.duplicate()
		selected_context["source_card"] = selected
		if selected.card_type == CardEnums.CardType.ATTACK:
			if _remove_from_hand(user, selected):
				target.add_card_to_mana_zone(selected, selected_context)
				destination = "法力区"
		else:
			if _remove_from_hand(user, selected):
				target.add_card_to_enchant_zone(selected, selected_context)
				destination = "附魔区"
	var drawn := user.draw_cards(1, controller.rng, context) if not destination.is_empty() else 0
	controller._emit_log("%s 将繁生嫁接置入 %s 的法力区%s。" % [
		user.get_display_name(),
		target.get_display_name(),
		"，并把所选牌移入%s后抽取 %d 张牌" % [destination, drawn] if not destination.is_empty() else "",
	])


func _orientation(context: Dictionary) -> int:
	if context.has("druid_orientation"):
		return int(context.get("druid_orientation"))
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	return user.get_druid_card_orientation(card) if user != null else CardEnums.DruidOrientation.UPRIGHT


func _selected_card(context: Dictionary) -> CardData:
	var raw_selected: Variant = context.get("ordered_discard_cards", [])
	if not (raw_selected is Array):
		return null
	var selected := raw_selected as Array
	if selected.is_empty() or not (selected[0] is CardData):
		return null
	return selected[0] as CardData


func _remove_from_hand(user: BattleUnitState, card: CardData) -> bool:
	var index := user.hand.find(card)
	if index < 0:
		return false
	user.hand.remove_at(index)
	return true
