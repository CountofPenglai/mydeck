extends RangerCardEffectBase
class_name RangerStealthPreparationCardEffect

const NEXT_TURN_AP_STATUS := preload("res://scripts/status/ranger_next_turn_ap_status.gd")

const MAX_DISCARD_COUNT := 2


func can_play(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and user.is_ranger()


func requires_ordered_discard_choice(_context: Dictionary = {}) -> bool:
	return true


func get_ordered_discard_choice_cards(context: Dictionary = {}) -> Array[CardData]:
	return _available_other_cards(
		context.get("user") as BattleUnitState,
		context.get("card") as CardData
	)


func get_ordered_discard_choice_max_count(context: Dictionary = {}) -> int:
	return mini(MAX_DISCARD_COUNT, get_ordered_discard_choice_cards(context).size())


func get_ordered_discard_choice_min_count(_context: Dictionary = {}) -> int:
	return 0


func get_ordered_discard_choice_prompt(_context: Dictionary = {}) -> String:
	return "潜踪整备：选择至多 2 张其他手牌弃置"


func are_targets_valid(context: Dictionary = {}, _targets: Array = [], write_log: bool = true) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var source_card: CardData = context.get("card") as CardData
	var selected := _selected_cards(context)
	var valid := user != null and source_card != null and _has_valid_selected_payload(context) \
		and selected.size() <= MAX_DISCARD_COUNT
	for card: CardData in selected:
		valid = valid and card != source_card and user.has_card_in_hand(card)
	if not valid and write_log:
		var controller: BattleController = context.get("controller") as BattleController
		if controller != null:
			controller._emit_log("潜踪整备只能弃置至多 2 张仍在手中的其他牌。")
	return valid


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var source_card: CardData = context.get("card") as CardData
	if controller == null or user == null or source_card == null:
		return
	var selected := _selected_cards(context)
	if not _has_valid_selected_payload(context) or not _selected_cards_are_live(user, source_card, selected):
		return
	controller.enqueue_effect(
		Callable(self, "_resolve_preparation"),
		[controller, user, source_card, selected, context],
		effect_priority,
		"潜踪整备：弃牌、抽牌并进入潜行",
		context
	)


func _resolve_preparation(controller: BattleController, user: BattleUnitState, source_card: CardData, selected: Array[CardData], context: Dictionary) -> void:
	if controller == null or user == null or source_card == null:
		return
	if not _selected_cards_are_live(user, source_card, selected):
		return
	var discarded_count := 0
	for card: CardData in selected:
		if user.discard_card(card, {
			"controller": controller,
			"source": user,
			"source_card": source_card,
			"reason": "ranger_stealth_preparation",
		}):
			discarded_count += 1
	var draw_context := context.duplicate()
	draw_context["reason"] = "ranger_stealth_preparation"
	user.draw_cards(discarded_count, controller.rng, draw_context)
	controller.enter_ranger_stealth(user, "潜踪整备")
	var status := NEXT_TURN_AP_STATUS.new() as StatusEffect
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
	if not raw is Array:
		return result
	for value: Variant in raw as Array:
		if not value is CardData:
			return []
		var card := value as CardData
		if result.has(card):
			return []
		result.append(card)
	return result


func _selected_cards_are_live(user: BattleUnitState, source_card: CardData, selected: Array[CardData]) -> bool:
	if user == null or source_card == null or selected.size() > MAX_DISCARD_COUNT:
		return false
	for card: CardData in selected:
		if card == null or card == source_card or not user.has_card_in_hand(card):
			return false
	return true


func _has_valid_selected_payload(context: Dictionary) -> bool:
	var raw: Variant = context.get("ordered_discard_cards", [])
	if not raw is Array:
		return false
	var seen: Array[CardData] = []
	for value: Variant in raw as Array:
		if not value is CardData:
			return false
		var card := value as CardData
		if seen.has(card):
			return false
		seen.append(card)
	return seen.size() <= MAX_DISCARD_COUNT
