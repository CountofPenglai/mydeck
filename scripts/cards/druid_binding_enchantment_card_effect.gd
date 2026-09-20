extends CardEffect
class_name DruidBindingEnchantmentCardEffect


const ARMOR_AMOUNT := 4


func is_unit_target_allowed(context: Dictionary = {}, target: BattleUnitState = null) -> bool:
	return target != null and target == context.get("user")


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null:
		return
	var inverted := int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT)) == CardEnums.DruidOrientation.INVERTED
	user.draw_cards(1 if inverted else 2, controller.rng, context)
	user.gain_armor(ARMOR_AMOUNT, context)
	if inverted:
		controller.mark_played_card_to_mana(context)


func on_zone_owner_turn_start(owner: BattleUnitState, zone_card: CardData, context: Dictionary = {}) -> void:
	if owner == null or zone_card == null or str(context.get("zone_name", "")) != "mana":
		return
	var controller := context.get("controller") as BattleController
	if controller != null:
		owner.draw_cards(1, controller.rng, context)
