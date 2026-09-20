extends RefCounted
class_name DruidTurnRules


static func resolve_turn_start(unit: BattleUnitState, context: Dictionary = {}) -> int:
	if unit == null or not unit.is_druid() or unit.is_druid_transformed():
		return 0
	var total := 0
	for zone_card in unit.mana_zone.duplicate():
		if zone_card == null:
			continue
		var production := 1
		if zone_card.effect != null:
			production = zone_card.effect.get_mana_production(unit, zone_card, context)
		var gained := unit.gain_mana(maxi(0, production), context.merged({
			"reason": "druid_mana_zone_production",
			"zone_card": zone_card,
		}))
		total += gained
	return total


static func resolve_turn_end(controller: BattleController, unit: BattleUnitState, context: Dictionary = {}) -> void:
	if controller == null or unit == null or not unit.is_druid():
		return
	if not unit.is_druid_transformed():
		unit.clear_mana(context.merged({"reason": "druid_human_turn_end"}))
		return
	if unit.pay_mana(1, context.merged({"reason": "druid_transformed_upkeep"})):
		return
	unit.set_druid_transformed(false, context.merged({
		"reason": "druid_transformed_upkeep_unpaid",
		"source": unit,
		"bypass_form_replacement": true,
	}))
