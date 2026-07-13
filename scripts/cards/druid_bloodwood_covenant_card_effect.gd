extends CardEffect
class_name DruidBloodwoodCovenantCardEffect

const TURN_DAMAGE_BONUS_STATUS := preload("res://scripts/status/druid_turn_damage_bonus_status.gd")


func _init() -> void:
	uses_strike = true


func requires_weapon_choice(context: Dictionary = {}) -> bool:
	return _orientation(context) == CardEnums.DruidOrientation.INVERTED


func is_unit_target_allowed(context: Dictionary = {}, target: BattleUnitState = null) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and target != null and target != user


func requires_ordered_discard_choice(context: Dictionary = {}) -> bool:
	return _orientation(context) == CardEnums.DruidOrientation.INVERTED and not get_ordered_discard_choice_cards(context).is_empty()


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
	return get_ordered_discard_choice_cards(context).size()


func get_ordered_discard_choice_min_count(_context: Dictionary = {}) -> int:
	return 0


func get_ordered_discard_choice_prompt(_context: Dictionary = {}) -> String:
	return "汲生猛袭：按顺序选择可能置入法力区的手牌（可不选）"


func are_targets_valid(context: Dictionary = {}, targets: Array = [], _write_log: bool = true) -> bool:
	if targets.size() != 1 or not (targets[0] is BattleUnitState):
		return false
	var target := targets[0] as BattleUnitState
	if not is_unit_target_allowed(context, target):
		return false
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	for selected in _selected_cards(context):
		if selected == card or user == null or not user.has_card_in_hand(selected):
			return false
	return true


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null or targets.is_empty():
		return
	var target := targets[0] as BattleUnitState
	if _orientation(context) == CardEnums.DruidOrientation.UPRIGHT:
		_play_upright(context, controller, user, target)
		return

	var actual_damage := controller.perform_strike(user, target, card, "汲生猛袭", str(context.get("equipment_slot", "")))
	var move_limit := maxi(0, actual_damage - user.get_available_mana())
	var moved := 0
	for selected in _selected_cards(context):
		if moved >= move_limit:
			break
		if user.move_hand_card_to_mana(selected, context):
			moved += 1
	controller._emit_log("%s 的汲生猛袭造成 %d 点实际伤害，并将 %d 张手牌置入法力区。" % [user.get_display_name(), actual_damage, moved])


func _play_upright(context: Dictionary, controller: BattleController, user: BattleUnitState, target: BattleUnitState) -> void:
	var amount := user.hand.size() + user.get_available_mana()
	if target.faction != user.faction:
		controller.apply_damage(user, target, amount, "血木盟约")
		return
	var status := TURN_DAMAGE_BONUS_STATUS.new() as StatusEffect
	status.stacks = amount
	target.add_status(status)
	controller._emit_log("%s 使 %s 获得 %d 点伤害加值，持续到其下回合开始。" % [user.get_display_name(), target.get_display_name(), amount])


func _orientation(context: Dictionary) -> int:
	if context.has("druid_orientation"):
		return int(context.get("druid_orientation"))
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	return user.get_druid_card_orientation(card) if user != null else CardEnums.DruidOrientation.UPRIGHT


func _selected_cards(context: Dictionary) -> Array[CardData]:
	var result: Array[CardData] = []
	var raw_selected: Variant = context.get("ordered_discard_cards", [])
	if raw_selected is Array:
		for value in raw_selected:
			if value is CardData:
				result.append(value as CardData)
	return result
