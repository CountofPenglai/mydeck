extends CardEffect
class_name RelentlessCardEffect

@export_range(0, 99, 1) var damage_bonus_per_returned_card: int = 1


func _init() -> void:
	uses_strike = true


func get_target_type_for_mode(_context: Dictionary = {}, play_mode: int = CardEnums.CardPlayMode.NORMAL, default_target_type: int = CardEnums.TargetType.NONE) -> int:
	if play_mode == CardEnums.CardPlayMode.MOMENTUM:
		return CardEnums.TargetType.SINGLE

	return default_target_type


func requires_weapon_choice(context: Dictionary = {}) -> bool:
	return int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) == CardEnums.CardPlayMode.MOMENTUM


func requires_draw_pile_choice(context: Dictionary = {}) -> bool:
	return int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL)) == CardEnums.CardPlayMode.NORMAL


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
	return "选择 %d 张要放逐的弃牌堆牌" % _get_banish_count(_context)


func can_play(context: Dictionary = {}) -> bool:
	var play_mode := int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL))
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if user == null:
		return false
	if play_mode == CardEnums.CardPlayMode.NORMAL:
		return not user.draw_pile.is_empty()
	if play_mode == CardEnums.CardPlayMode.MOMENTUM:
		var card: CardData = context.get("card") as CardData
		return user.count_discard_cards_excluding(card) >= _get_banish_count(context)

	return true


func are_targets_valid(context: Dictionary = {}, targets: Array = [], write_log: bool = true) -> bool:
	var play_mode := int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL))
	if play_mode == CardEnums.CardPlayMode.NORMAL:
		var user: BattleUnitState = context.get("user") as BattleUnitState
		var selected_card: CardData = context.get("selected_draw_card") as CardData
		if user == null or selected_card == null or user.draw_pile.find(selected_card) < 0:
			var controller: BattleController = context.get("controller") as BattleController
			if write_log and controller != null:
				controller._emit_log("请选择一张牌库中的牌。")
			return false
		return true

	return targets.size() == 1 and targets[0] is BattleUnitState


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null:
		return

	var play_mode := int(context.get("play_mode", CardEnums.CardPlayMode.NORMAL))
	if play_mode == CardEnums.CardPlayMode.MOMENTUM:
		_play_momentum(context, controller, user, card, targets)
		return

	var selected_card: CardData = context.get("selected_draw_card") as CardData
	if selected_card != null and user.move_draw_card_to_discard(selected_card):
		controller._emit_log("%s 将牌库中的 %s 置入弃牌堆。" % [user.get_display_name(), selected_card.card_name])


func _play_momentum(context: Dictionary, controller: BattleController, user: BattleUnitState, card: CardData, targets: Array) -> void:
	if targets.size() != 1 or not (targets[0] is BattleUnitState):
		return

	var target: BattleUnitState = targets[0] as BattleUnitState
	var returned_count := user.shuffle_exiled_into_draw_pile(controller.rng)
	var damage_modifier := returned_count * damage_bonus_per_returned_card
	if returned_count > 0:
		controller._emit_log("%s 将 %d 张放逐牌洗回牌库，本次打击获得 +%d 伤害加值。" % [
			user.get_display_name(),
			returned_count,
			damage_modifier,
		])

	controller.perform_strike_with_modifier(
		user,
		target,
		card,
		damage_modifier,
		"百折不饶",
		str(context.get("equipment_slot", ""))
	)


func _get_banish_count(context: Dictionary) -> int:
	var card: CardData = context.get("card") as CardData
	if card != null:
		for condition in card.momentum_conditions:
			if condition is BanishDiscardCondition:
				return (condition as BanishDiscardCondition).banish_count
	return 3
