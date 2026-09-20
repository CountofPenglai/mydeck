extends CardEffect
class_name DruidChannelingClawsCardEffect


func _init() -> void:
	uses_strike = true


func get_target_type_for_mode(context: Dictionary = {}, _play_mode: int = CardEnums.CardPlayMode.NORMAL, default_target_type: int = CardEnums.TargetType.NONE) -> int:
	return CardEnums.TargetType.NONE if _is_upright(context) else default_target_type


func requires_weapon_choice(context: Dictionary = {}) -> bool:
	return not _is_upright(context)


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null:
		return
	if _is_upright(context):
		user.draw_cards(2, controller.rng, context)
		controller.resolution_runner.enqueue_after_current_effect_queue(Callable(self, "_request_upright_choice").bind(context, controller, user, card), [], "灵脉爪击：抽牌后选择")
		return
	if targets.size() != 1 or not (targets[0] is BattleUnitState):
		return
	controller.resolution_runner.begin_attack_scope()
	var actual := controller.perform_strike(user, targets[0] as BattleUnitState, card, "汲生爪击", str(context.get("equipment_slot", "")))
	controller.resolution_runner.end_attack_scope()
	if actual > 0:
		controller.heal_unit(user, user, actual, "汲生爪击吸血")
	_finish_inverted_strike(context, controller, user)


func _request_upright_choice(context: Dictionary, controller: BattleController, user: BattleUnitState, card: CardData) -> void:
	controller.resolution_runner.request_hand_card_choice(user, card, 1, 1, "灵脉爪击：选择 1 张其他手牌移入法力区", Callable(self, "_move_selected_to_mana").bind(context, user))


func _move_selected_to_mana(selected: Array[CardData], _context: Dictionary, user: BattleUnitState) -> void:
	if selected.size() == 1 and selected[0] != null:
		user.move_hand_card_to_mana(selected[0], {"reason": "druid_channeling_claws"})


func _finish_inverted_strike(context: Dictionary, controller: BattleController, user: BattleUnitState) -> void:
	user.gain_mana(1, context)
	controller.mark_played_card_to_mana(context)


func _is_upright(context: Dictionary) -> bool:
	return int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT)) == CardEnums.DruidOrientation.UPRIGHT
