extends CardEffect
class_name DruidCanopyCycleCardEffect

const SHELTER_STATUS := preload("res://scripts/status/druid_canopy_shelter_status.gd")

@export_range(0, 9, 1) var upright_draw_count: int = 2
@export_range(0, 9, 1) var shelter_draw_count: int = 2


func can_play(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if user == null or card == null:
		return false
	if _orientation(context) == CardEnums.DruidOrientation.INVERTED:
		return not _available_hand_cards(user, card).is_empty()
	return true


func requires_ordered_discard_choice(context: Dictionary = {}) -> bool:
	return get_ordered_discard_choice_max_count(context) > 0


func get_ordered_discard_choice_cards(context: Dictionary = {}) -> Array[CardData]:
	return _available_hand_cards(context.get("user") as BattleUnitState, context.get("card") as CardData)


func get_ordered_discard_choice_max_count(context: Dictionary = {}) -> int:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if user == null or card == null:
		return 0
	var available := _available_hand_cards(user, card).size()
	if _orientation(context) == CardEnums.DruidOrientation.INVERTED:
		return mini(1, available)
	return mini(user.get_available_mana(), available)


func get_ordered_discard_choice_min_count(context: Dictionary = {}) -> int:
	return 1 if _orientation(context) == CardEnums.DruidOrientation.INVERTED else 0


func get_ordered_discard_choice_prompt(context: Dictionary = {}) -> String:
	if _orientation(context) == CardEnums.DruidOrientation.INVERTED:
		return "古树庇护：选择 1 张额外弃置的手牌"
	return "林冠蜕变：选择至多等同于当前法力的手牌置入法力区"


func are_targets_valid(context: Dictionary = {}, _targets: Array = [], write_log: bool = true) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if user == null or card == null:
		return false
	var selected := _selected_cards(context)
	var min_count := get_ordered_discard_choice_min_count(context)
	var max_count := get_ordered_discard_choice_max_count(context)
	if selected.size() < min_count or selected.size() > max_count:
		if write_log:
			var controller: BattleController = context.get("controller") as BattleController
			if controller != null:
				controller._emit_log("%s 的手牌选择数量无效。" % card.card_name)
		return false
	for selected_card in selected:
		if selected_card == card or not user.has_card_in_hand(selected_card):
			return false
	return true


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null:
		return
	var selected := _selected_cards(context)
	if _orientation(context) == CardEnums.DruidOrientation.INVERTED:
		_play_inverted(context, controller, user, selected)
		return

	var drawn := user.draw_cards(upright_draw_count, controller.rng, context)
	var moved := 0
	for selected_card in selected:
		if user.move_hand_card_to_mana(selected_card, context):
			moved += 1
	if moved > 0:
		user.set_druid_transformed(true)
	controller._emit_log("%s 抽取 %d 张牌，将 %d 张手牌置入法力区%s。" % [
		user.get_display_name(),
		drawn,
		moved,
		"并完成变身" if moved > 0 else "",
	])


func _play_inverted(context: Dictionary, controller: BattleController, user: BattleUnitState, selected: Array[CardData]) -> void:
	if selected.is_empty() or not user.discard_card(selected[0], context):
		return
	var armor_before := user.get_armor_stacks()
	user.gain_armor(armor_before, context)
	user.remove_status("druid_canopy_shelter")
	var shelter := SHELTER_STATUS.new() as StatusEffect
	shelter.stacks = 1
	shelter.set("draw_count", shelter_draw_count)
	user.add_status(shelter)
	controller._emit_log("%s 弃置 1 张牌，将护甲翻倍至 %d；古树庇护将在下回合开始时结束。" % [user.get_display_name(), user.get_armor_stacks()])


func _orientation(context: Dictionary) -> int:
	if context.has("druid_orientation"):
		return int(context.get("druid_orientation"))
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	return user.get_druid_card_orientation(card) if user != null else CardEnums.DruidOrientation.UPRIGHT


func _available_hand_cards(user: BattleUnitState, card: CardData) -> Array[CardData]:
	var result: Array[CardData] = []
	if user == null:
		return result
	for hand_card in user.hand:
		if hand_card != null and hand_card != card:
			result.append(hand_card)
	return result


func _selected_cards(context: Dictionary) -> Array[CardData]:
	var result: Array[CardData] = []
	var raw_selected: Variant = context.get("ordered_discard_cards", [])
	if raw_selected is Array:
		for value in raw_selected:
			if value is CardData:
				result.append(value as CardData)
	return result
