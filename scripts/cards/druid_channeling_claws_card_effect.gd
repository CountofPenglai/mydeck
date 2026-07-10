extends CardEffect
class_name DruidChannelingClawsCardEffect


func _init() -> void:
	uses_strike = true


func get_target_type_for_mode(context: Dictionary = {}, _play_mode: int = CardEnums.CardPlayMode.NORMAL, default_target_type: int = CardEnums.TargetType.NONE) -> int:
	if int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT)) == CardEnums.DruidOrientation.UPRIGHT:
		return CardEnums.TargetType.NONE

	return default_target_type


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null:
		return

	var orientation := int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT))
	if orientation == CardEnums.DruidOrientation.UPRIGHT:
		_play_upright(context, controller, user)
		return

	var total_lifesteal := 0
	var equipment_slot := str(context.get("equipment_slot", ""))
	for target in targets:
		if target == null or not (target is BattleUnitState):
			continue
		var target_unit: BattleUnitState = target as BattleUnitState
		total_lifesteal += controller.perform_strike(user, target_unit, card, "汲生爪击", equipment_slot)
	if total_lifesteal > 0:
		controller.heal_unit(user, user, total_lifesteal, "吸血")


func on_zone_card_entered_special_zone(owner: BattleUnitState, zone_card: CardData, entered_card: CardData, zone_name: String, context: Dictionary = {}) -> void:
	if owner == null or zone_card == null or entered_card != zone_card or zone_name != "mana":
		return
	if str(context.get("reason", "")) != "druid_inverted_card_played":
		return

	var gain_context := context.duplicate()
	gain_context["reason"] = "druid_channeling_claws"
	owner.gain_temporary_mana(1, gain_context)
	var controller: BattleController = context.get("controller") as BattleController
	if controller != null:
		controller._emit_log("%s 的 %s 进入法力区，获得 1 点本回合临时法力。" % [owner.get_display_name(), zone_card.card_name])


func _play_upright(context: Dictionary, controller: BattleController, user: BattleUnitState) -> void:
	var drawn_cards := user.draw_cards_detailed(1, controller.rng, context)
	if drawn_cards.is_empty():
		controller.mark_played_card_to_mana(context)
		controller._emit_log("%s 没有抽到牌，打出的牌将进入法力区。" % user.get_display_name())
		return

	var drawn_card: CardData = drawn_cards[0]
	if user.move_hand_card_to_mana(drawn_card, context):
		controller._emit_log("%s 将抽到的 %s 置入法力区，然后再抽 1 张牌。" % [user.get_display_name(), drawn_card.card_name])
		user.draw_cards(1, controller.rng, context)
	else:
		controller.mark_played_card_to_mana(context)

