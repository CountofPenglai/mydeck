extends CardEffect
class_name DruidRootedInsightCardEffect

@export_range(0, 9, 1) var upright_draw_count: int = 2
@export_range(0, 9, 1) var inverted_draw_count: int = 1


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null:
		return

	var orientation := int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT))
	var draw_count := upright_draw_count
	if orientation == CardEnums.DruidOrientation.INVERTED:
		draw_count = inverted_draw_count

	var drawn := user.draw_cards(draw_count, controller.rng, context)
	controller._emit_log("%s 抽取 %d 张牌。" % [user.get_display_name(), drawn])
	user.gain_mana(1, context)
	if orientation == CardEnums.DruidOrientation.INVERTED:
		controller.mark_played_card_to_mana(context)
