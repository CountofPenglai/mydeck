extends RangerWeaponCardEffect
class_name RangerSeamlessPursuitCardEffect

const UNIVERSAL_COMBO_STATUS := preload("res://scripts/status/ranger_universal_combo_status.gd")

@export_range(1, 9, 1) var combo_discard_count: int = 2


func requires_ordered_discard_choice(context: Dictionary = {}) -> bool:
	return int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) == CardEnums.CardPlayMode.COMBO


func get_ordered_discard_choice_cards(context: Dictionary = {}) -> Array[CardData]:
	return _available_other_cards(
		context.get("user") as BattleUnitState,
		context.get("card") as CardData
	)


func get_ordered_discard_choice_max_count(context: Dictionary = {}) -> int:
	return mini(combo_discard_count, get_ordered_discard_choice_cards(context).size())


func get_ordered_discard_choice_min_count(context: Dictionary = {}) -> int:
	return combo_discard_count if requires_ordered_discard_choice(context) else 0


func get_ordered_discard_choice_prompt(_context: Dictionary = {}) -> String:
	return "无缝追击：选择 2 张其他手牌弃置"


func are_targets_valid(context: Dictionary = {}, _targets: Array = [], write_log: bool = true) -> bool:
	if not requires_ordered_discard_choice(context):
		return true
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var selected := _selected_cards(context)
	var valid := user != null and selected.size() == combo_discard_count
	for card: CardData in selected:
		valid = valid and user.has_card_in_hand(card) and card != context.get("card")
	if not valid and write_log:
		var controller: BattleController = context.get("controller") as BattleController
		if controller != null:
			controller._emit_log("无缝追击的连击需要选择 %d 张其他手牌。" % combo_discard_count)
	return valid


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null or targets.size() != 1 or not (targets[0] is BattleUnitState):
		return
	var is_combo := int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) == CardEnums.CardPlayMode.COMBO
	_enqueue_weapon_strike(context, targets[0] as BattleUnitState, "无缝追击", 0, 1.0, {}, effect_priority)
	if is_combo:
		controller.enqueue_effect(
			Callable(self, "_grant_universal_combo"),
			[user],
			-10,
			"无缝追击：获得万能接续",
			context
		)
	_enqueue_combo_completion(context, -100)


func _grant_universal_combo(user: BattleUnitState) -> void:
	if user == null or not user.is_ranger():
		return
	user.ranger_state.universal_combo_ready = true
	user.ranger_state.universal_combo_expires_turn_serial = user.turn_serial + 1
	user.remove_status("ranger_universal_combo")
	var status := UNIVERSAL_COMBO_STATUS.new() as StatusEffect
	status.stacks = 1
	user.add_status(status)


func _available_other_cards(user: BattleUnitState, source_card: CardData) -> Array[CardData]:
	var result: Array[CardData] = []
	if user == null:
		return result
	for card: CardData in user.hand:
		if card != null and card != source_card:
			result.append(card)
	return result


func _selected_cards(context: Dictionary) -> Array[CardData]:
	var result: Array[CardData] = []
	var raw: Variant = context.get("ordered_discard_cards", [])
	if raw is Array:
		for value: Variant in raw as Array:
			if value is CardData and not result.has(value as CardData):
				result.append(value as CardData)
	return result
