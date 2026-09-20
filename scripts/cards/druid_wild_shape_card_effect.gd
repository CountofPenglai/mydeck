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
	var form_context := context.merged({"source_card": context.get("card")})
	if orientation == CardEnums.DruidOrientation.INVERTED:
		controller.request_druid_form_change(user, false, form_context)
		controller.heal_unit(user, user, inverted_heal, "返生")
	else:
		user.gain_mana(2, context)
		controller.request_druid_form_change(user, true, form_context)
	user.draw_cards(draw_count, controller.rng, context)
