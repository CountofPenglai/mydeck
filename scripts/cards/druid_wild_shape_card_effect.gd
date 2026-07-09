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
		user.gain_temporary_mana(1)
		controller._emit_log("%s 获得 1 点本回合临时法力。" % user.get_display_name())
	else:
		user.set_druid_transformed(true)
		var drawn := user.draw_cards(draw_count, controller.rng)
		controller._emit_log("%s 进入变身状态，抽取 %d 张牌。" % [user.get_display_name(), drawn])
		controller.mark_played_card_to_mana(context)

