extends StatusEffect
class_name DruidDrawOnNextUprightStatus

@export_range(1, 9, 1) var draw_count: int = 2
@export_range(0, 9, 1) var mana_cost: int = 1


func _init() -> void:
	status_id = "druid_draw_on_next_upright"
	display_name = "观兆"


func on_card_ap_cost_paid(unit: BattleUnitState, card: CardData, context: Dictionary = {}) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	if controller == null or unit == null or card == null:
		return
	if int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT)) != CardEnums.DruidOrientation.UPRIGHT:
		return
	if mana_cost > 0 and not unit.pay_mana(mana_cost):
		return

	var drawn := unit.draw_cards(draw_count, controller.rng, context)
	controller._emit_log("%s 触发观兆，抽取 %d 张牌。" % [unit.get_display_name(), drawn])
	stacks = 0
