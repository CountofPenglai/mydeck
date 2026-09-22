extends RefCounted
class_name DruidExpansionFixture


static func make(card_id: String, inverted: bool) -> Dictionary:
	var scenario := (load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario).duplicate(true) as BattleScenario
	var controller := BattleController.new()
	controller.setup(scenario)
	var druid: BattleUnitState = null
	for unit_value in controller.player_units:
		var unit := unit_value as BattleUnitState
		if unit != null and unit.is_druid():
			druid = unit
	if druid == null or controller.enemy_units.is_empty():
		return {}
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.current_unit = druid
	druid.is_deployed = true
	druid.set_hex_cell(Vector2i(4, 4), controller.map_data)
	druid.current_ap = 10
	druid.hand.clear()
	druid.draw_pile.clear()
	druid.discard_pile.clear()
	druid.mana_zone.clear()
	druid.statuses.clear()
	druid.clear_mana()
	druid.set_druid_transformed(inverted)
	var card := (load("res://resources/cards/%s.tres" % card_id) as CardData).duplicate(true) as CardData
	if card == null:
		return {}
	druid.hand.append(card)
	var enemy := controller.enemy_units[0] as BattleUnitState
	enemy.statuses.clear()
	enemy.is_deployed = true
	enemy.set_hex_cell(Vector2i(5, 4), controller.map_data)
	enemy.set_current_health(enemy.get_max_health())
	return {"c": controller, "u": druid, "card": card, "enemy": enemy}
