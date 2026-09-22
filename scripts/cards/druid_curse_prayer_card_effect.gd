extends CardEffect
class_name DruidCursePrayerCardEffect


const EXTRA_MANA_COST := 2
const EXILE_STRIKE_BONUS := 4


func _init() -> void:
	uses_strike = true


func is_unit_target_allowed(context: Dictionary = {}, target: BattleUnitState = null) -> bool:
	var user := context.get("user") as BattleUnitState
	if user == null or target == null:
		return false
	return target.faction != user.faction if _is_inverted(context) else target.faction == user.faction


func requires_posttarget_configuration(context: Dictionary = {}, targets: Array = []) -> bool:
	var user := context.get("user") as BattleUnitState
	var target := _single_target(targets)
	if user == null or target == null:
		return false
	if not _is_inverted(context):
		return not _suppressible_curses(target).is_empty()
	return user.can_pay_mana(EXTRA_MANA_COST) and not _curse_cards_in(target.draw_pile).is_empty()


func get_posttarget_configuration(context: Dictionary = {}, targets: Array = []) -> Dictionary:
	var target := _single_target(targets)
	if target == null:
		return {}
	if _is_inverted(context):
		return {
			"title": "荒魂怒啸：可选增强",
			"options": ["额外支付2点法力，随机放逐目标牌库中的1张诅咒牌"],
			"option_values": [true],
			"minimum": 0,
			"maximum": 1,
		}
	var candidates := _suppressible_curses(target)
	var labels: Array[String] = []
	for curse in candidates:
		labels.append(curse.get_summary())
	return {
		"title": "驱咒祷词：可选压制1个报或果",
		"options": labels,
		"option_values": candidates,
		"minimum": 0,
		"maximum": 1,
	}


func can_pay_play_cost(context: Dictionary = {}) -> bool:
	if not _is_inverted(context) or not _wants_extra_payment(context):
		return true
	var user := context.get("user") as BattleUnitState
	var target := _single_target(context.get("targets", []) as Array)
	return user != null and target != null and user.can_pay_mana(EXTRA_MANA_COST) \
		and not _curse_cards_in(target.draw_pile).is_empty()


func pay_play_cost(context: Dictionary = {}) -> bool:
	if not _is_inverted(context) or not _wants_extra_payment(context):
		return true
	var user := context.get("user") as BattleUnitState
	var target := _single_target(context.get("targets", []) as Array)
	return user != null and target != null and not _curse_cards_in(target.draw_pile).is_empty() \
		and user.pay_mana(EXTRA_MANA_COST, context.merged({"reason": "druid_curse_prayer_extra"}))


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	var target := _single_target(targets)
	if controller == null or user == null or card == null or target == null:
		return
	if not _is_inverted(context):
		target.draw_cards(2, controller.rng, context)
		user.gain_mana(2, context)
		var selected := _selected_curse(context)
		if selected != null and _suppressible_curses(target).has(selected):
			target.suppress_curse_for_battle(selected)
		return
	var exiled_count := 0
	if _exile_random_curse_card(target, target.hand, controller.rng, context):
		exiled_count += 1
	if _wants_extra_payment(context) and _exile_random_curse_card(target, target.draw_pile, controller.rng, context):
		exiled_count += 1
	# Exile descendants may change the target. The continuation is deliberately
	# after the current effect queue rather than a same-frame immediate strike.
	controller.enqueue_after_current_attack(
		Callable(self, "_strike_after_exiles"),
		[controller, user, target, card, EXILE_STRIKE_BONUS * exiled_count, str(context.get("equipment_slot", ""))],
		"荒魂怒啸：放逐后打击"
	)


func _strike_after_exiles(controller: BattleController, user: BattleUnitState, target: BattleUnitState, card: CardData, damage_bonus: int, equipment_slot: String) -> void:
	if controller == null or user == null or target == null or card == null \
			or not user.is_alive() or not user.is_deployed or not target.is_alive() or not target.is_deployed \
			or target.faction == user.faction \
			or not user.can_use_attack_mode(equipment_slot, {"controller": controller, "target": target, "card": card}) \
			or not controller._targets_are_valid(user, card, [target], false, equipment_slot, CardEnums.CardPlayMode.NORMAL, {"druid_orientation": CardEnums.DruidOrientation.INVERTED}):
		return
	controller.perform_strike_with_modifier(user, target, card, damage_bonus, "荒魂怒啸", equipment_slot)


func _selected_curse(context: Dictionary) -> CurseInstance:
	var values := context.get("selected_option_values", []) as Array
	return values[0] as CurseInstance if not values.is_empty() else null


func _wants_extra_payment(context: Dictionary) -> bool:
	var values := context.get("selected_option_values", []) as Array
	return bool(values[0]) if not values.is_empty() else false


func _single_target(targets: Array) -> BattleUnitState:
	return targets[0] as BattleUnitState if targets.size() == 1 else null


func _suppressible_curses(target: BattleUnitState) -> Array[CurseInstance]:
	var result: Array[CurseInstance] = []
	if target == null:
		return result
	for curse in target.curse_zone:
		if curse != null and curse.is_active_in_curse_zone() and not target.curse_suppression.is_suppressed(curse):
			result.append(curse)
	return result


func _curse_cards_in(cards: Array[CardData]) -> Array[CardData]:
	var result: Array[CardData] = []
	for card in cards:
		if card != null and card.is_curse_card():
			result.append(card)
	return result


func _exile_random_curse_card(target: BattleUnitState, cards: Array[CardData], rng: RandomNumberGenerator, context: Dictionary = {}) -> bool:
	var candidates := _curse_cards_in(cards)
	if target == null or candidates.is_empty() or rng == null:
		return false
	return target.move_card_to_exile(candidates[rng.randi_range(0, candidates.size() - 1)], context)


func _is_inverted(context: Dictionary) -> bool:
	return int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT)) == CardEnums.DruidOrientation.INVERTED
