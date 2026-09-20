extends CardEffect
class_name DruidMoonlitMendCardEffect

@export_range(0, 99, 1) var base_amount: int = 4
@export_range(0, 99, 1) var inverted_base_amount: int = 6
@export_range(0, 99, 1) var resonance_extra: int = 2


func is_unit_target_allowed(_context: Dictionary = {}, target: BattleUnitState = null) -> bool:
	return target != null


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null:
		return

	var inverted := int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT)) == CardEnums.DruidOrientation.INVERTED
	var amount := inverted_base_amount if inverted else base_amount
	if inverted and user.pay_mana(1, context):
		amount += resonance_extra

	for target in targets:
		if target == null or not (target is BattleUnitState):
			continue
		var target_unit: BattleUnitState = target as BattleUnitState
		if target_unit.faction == user.faction:
			controller.heal_unit(user, target_unit, amount, "月愈")
		else:
			var damage_context := context.merged({"source_card": card, "damage_type": CardEnums.DamageType.INTELLIGENCE})
			controller.apply_damage(user, target_unit, maxi(0, amount + user.get_damage_bonus(damage_context)), "月火", damage_context)
