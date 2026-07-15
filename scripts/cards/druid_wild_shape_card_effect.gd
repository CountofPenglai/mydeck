extends CardEffect
class_name DruidWildShapeCardEffect

@export_range(0, 9, 1) var draw_count: int = 1
@export_range(0, 99, 1) var inverted_heal: int = 4


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null:
		return

	var orientation := int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT))
	if orientation == CardEnums.DruidOrientation.INVERTED:
		controller.heal_unit(user, user, inverted_heal, "返生")
		user.gain_temporary_mana(1, context)
		controller._emit_log("%s 获得 1 点本回合临时法力。" % user.get_display_name())
	else:
		var source_card := context.get("card") as CardData
		var form_result := controller.request_druid_form_change(user, true, context.merged({"source_card": source_card}))
		var drawn := user.draw_cards(draw_count, controller.rng, context)
		controller._emit_log("%s %s，抽取 %d 张牌。" % [user.get_display_name(), "进入变身状态" if bool(form_result.get("changed", false)) else "触发形态替代", drawn])
		controller.mark_played_card_to_mana(context)
