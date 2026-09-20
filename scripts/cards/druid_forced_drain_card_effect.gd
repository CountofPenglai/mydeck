extends CardEffect
class_name DruidForcedDrainCardEffect


const ROOT_STATUS := preload("res://scripts/status/druid_root_status.gd")


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1 or not (targets[0] is BattleUnitState):
		return
	var target := targets[0] as BattleUnitState
	var inverted := int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT)) == CardEnums.DruidOrientation.INVERTED
	_deal_intelligence_damage(controller, user, target, card, 3 if inverted else 6, "根系汲取" if inverted else "强制汲取")
	target.add_status(ROOT_STATUS.new())
	if inverted:
		controller.mark_played_card_to_mana(context)


func on_zone_owner_turn_start(owner: BattleUnitState, zone_card: CardData, context: Dictionary = {}) -> void:
	if owner == null or zone_card == null or str(context.get("zone_name", "")) != "mana":
		return
	var controller := context.get("controller") as BattleController
	if controller == null:
		return
	var total_lost := 0
	for unit in controller.units:
		var target := unit as BattleUnitState
		if target != null and target.is_alive() and target.faction != owner.faction and target.has_status("druid_root"):
			total_lost += controller.lose_life(owner, target, 1, "根系汲取")
	if total_lost > 0:
		controller.heal_unit(owner, owner, total_lost, "根系汲取")


func _deal_intelligence_damage(controller: BattleController, user: BattleUnitState, target: BattleUnitState, card: CardData, base: int, label: String) -> int:
	var damage_context := {"controller": controller, "card": card, "target": target, "resolved_damage_type": CardEnums.DamageType.INTELLIGENCE, "source_card": card}
	return controller.apply_damage(user, target, base + user.get_damage_bonus(damage_context), label, damage_context)
