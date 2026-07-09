extends CardEffect
class_name DruidMoonlitMendCardEffect

@export_range(0, 99, 1) var base_amount: int = 4
@export_range(0, 99, 1) var resonance_extra: int = 2


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null:
		return

	var amount := base_amount + user.get_damage_bonus({
		"controller": controller,
		"unit": user,
		"card": card,
		"source": self,
	})
	if bool(context.get("druid_resonance_paid", false)):
		amount += resonance_extra

	for target in targets:
		if target == null or not (target is BattleUnitState):
			continue
		var target_unit: BattleUnitState = target as BattleUnitState
		if target_unit.faction == user.faction:
			controller.heal_unit(user, target_unit, amount, "月愈")
		else:
			controller.apply_damage(user, target_unit, amount, "月火")

