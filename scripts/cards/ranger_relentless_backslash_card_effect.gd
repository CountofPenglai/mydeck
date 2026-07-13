extends RangerWeaponCardEffect
class_name RangerRelentlessBackslashCardEffect


func requires_weapon_choice(_context: Dictionary = {}) -> bool:
	return false


func can_play(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and _is_dagger_slot(user, "weapon")


func play(context: Dictionary = {}, targets: Array = []) -> void:
	if targets.size() != 1 or not (targets[0] is BattleUnitState):
		return
	var dagger_context := context.duplicate()
	dagger_context["equipment_slot"] = "weapon"
	_enqueue_weapon_strike(dagger_context, targets[0] as BattleUnitState, "回锋不止", 0, 1.0, {}, effect_priority)
	_enqueue_combo_completion(context)


func can_activate_from_discard(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	return user != null and card != null and user.has_card_in_discard(card) and not _other_hand_cards(user, card).is_empty()


func get_discard_action_label(_context: Dictionary = {}) -> String:
	return "弃 1 张手牌：将回锋不止返回手牌"


func requires_ordered_discard_choice(context: Dictionary = {}) -> bool:
	return bool(context.get("ranger_discard_activation", false))


func get_ordered_discard_choice_cards(context: Dictionary = {}) -> Array[CardData]:
	return _other_hand_cards(
		context.get("user") as BattleUnitState,
		context.get("card") as CardData
	) if requires_ordered_discard_choice(context) else []


func get_ordered_discard_choice_max_count(context: Dictionary = {}) -> int:
	return 1 if requires_ordered_discard_choice(context) else 0


func get_ordered_discard_choice_min_count(context: Dictionary = {}) -> int:
	return 1 if requires_ordered_discard_choice(context) else 0


func get_ordered_discard_choice_prompt(_context: Dictionary = {}) -> String:
	return "回锋不止：选择 1 张手牌弃置"


func activate_from_discard(context: Dictionary = {}) -> bool:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	var selected := _selected_card(context)
	if controller == null or not can_activate_from_discard(context) or selected == null:
		return false
	return controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_discard_activation"),
		[controller, user, card, selected],
		0,
		"回锋不止：弃牌回收",
		context
	))


func _resolve_discard_activation(
		controller: BattleController,
		user: BattleUnitState,
		card: CardData,
		selected: CardData
	) -> void:
	if user == null or card == null or selected == null:
		return
	if not user.has_card_in_discard(card) or not user.discard_card(selected, {
		"controller": controller,
		"reason": "ranger_relentless_backslash_recover",
		"source_card": card,
	}):
		return
	if user.move_discard_card_to_hand(card):
		controller._emit_log("%s 弃置 %s，将回锋不止返回手牌。" % [user.get_display_name(), selected.card_name])
		controller.state_changed.emit()


func _other_hand_cards(user: BattleUnitState, source_card: CardData) -> Array[CardData]:
	var result: Array[CardData] = []
	if user == null:
		return result
	for card: CardData in user.hand:
		if card != null and card != source_card:
			result.append(card)
	return result


func _selected_card(context: Dictionary) -> CardData:
	var raw: Variant = context.get("ordered_discard_cards", [])
	if not (raw is Array) or (raw as Array).size() != 1:
		return null
	var value: Variant = (raw as Array)[0]
	return value as CardData if value is CardData else null
