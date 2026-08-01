extends CardEffect
class_name HiddenBladeAgainCardEffect

@export_range(0, 99, 1) var momentum_damage_bonus: int = 2


func _init() -> void:
	uses_strike = true


func requires_ordered_discard_choice(context: Dictionary = {}) -> bool:
	return int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) == CardEnums.CardPlayMode.MOMENTUM \
		and not context.has("ordered_discard_cards")


func get_ordered_discard_choice_cards(context: Dictionary = {}) -> Array[CardData]:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	return user.get_discard_cards_excluding(card) if user != null else []


func get_ordered_discard_choice_max_count(_context: Dictionary = {}) -> int:
	return _get_banish_count(_context)


func get_ordered_discard_choice_min_count(_context: Dictionary = {}) -> int:
	return _get_banish_count(_context)


func get_ordered_discard_choice_prompt(_context: Dictionary = {}) -> String:
	return "选择 %d 张要额外放逐的弃牌堆牌" % _get_banish_count(_context)


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1:
		return
	if not (targets[0] is BattleUnitState):
		return

	var target := targets[0] as BattleUnitState
	var play_mode := int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL))
	var damage_bonus := momentum_damage_bonus if play_mode == CardEnums.CardPlayMode.MOMENTUM else 0
	controller.enqueue_effect(
		Callable(controller, "perform_strike_with_modifier"),
		[user, target, card, damage_bonus, "藏锋再起", str(context.get("equipment_slot", ""))],
		effect_priority,
		"藏锋再起：武器打击",
		context
	)


func _get_banish_count(context: Dictionary) -> int:
	var card: CardData = context.get("card") as CardData
	if card != null:
		for condition in card.momentum_conditions:
			if condition is BanishDiscardCondition:
				return (condition as BanishDiscardCondition).banish_count
	return 1
