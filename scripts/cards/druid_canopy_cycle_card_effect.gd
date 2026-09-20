extends CardEffect
class_name DruidCanopyCycleCardEffect


func is_unit_target_allowed(context: Dictionary = {}, target: BattleUnitState = null) -> bool:
	return target != null and target == context.get("user")


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null:
		return
	if _is_upright(context):
		controller.resolution_runner.request_hand_card_choice(user, card, 0, 2, "蓄翠化形：选择至多 2 张其他手牌移入法力区", Callable(self, "_resolve_upright_choice").bind(context, controller, user, card))
		return
	user.gain_armor(4 + user.mana_zone.size(), context)
	user.draw_cards(1, controller.rng, context)
	controller.mark_played_card_to_mana(context)


func _resolve_upright_choice(selected: Array[CardData], context: Dictionary, controller: BattleController, user: BattleUnitState, card: CardData) -> void:
	var moved := 0
	for selected_card in selected:
		if selected_card != null and selected_card != card and user.move_hand_card_to_mana(selected_card, {"reason": "druid_canopy_cycle"}):
			moved += 1
	user.draw_cards(moved, controller.rng, context)
	controller.request_druid_form_change(user, true, context.merged({"source_card": card}))


func _is_upright(context: Dictionary) -> bool:
	return int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT)) == CardEnums.DruidOrientation.UPRIGHT
