extends Node

var _exit_code := 0


func _ready() -> void:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	var controller := BattleController.new()
	controller.setup(scenario)
	_deploy_players(controller)
	if not controller.start_battle():
		_fail("DRUID_REMAINING: failed to start battle")
		_finish()
		return
	var druid := _find_druid(controller)
	var ally := _find_ally(controller, druid)
	var enemy: BattleUnitState = controller.enemy_units[0] if not controller.enemy_units.is_empty() else null
	if druid == null or ally == null or enemy == null:
		_fail("DRUID_REMAINING: required units missing")
		_finish()
		return
	druid.set_hex_cell(Vector2i(3, 4), controller.map_data)
	ally.set_hex_cell(Vector2i(3, 5), controller.map_data)
	enemy.set_hex_cell(Vector2i(4, 4), controller.map_data)
	controller.phase = BattleController.Phase.BATTLE
	controller.current_unit = druid
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE

	_test_canopy_cycle(controller, druid)
	_test_bloodwood_covenant(controller, druid, ally, enemy)
	_test_overgrowth_graft(controller, druid, ally, enemy)
	print("DRUID_REMAINING: completed")
	_finish()


func _test_canopy_cycle(controller: BattleController, druid: BattleUnitState) -> void:
	var template := load("res://resources/cards/druid_canopy_cycle.tres") as CardData
	var fodder := _dummy_card()
	_reset_druid(druid, false)
	var card := template.duplicate() as CardData
	druid.hand.assign([card, fodder])
	druid.add_card_to_mana_zone(_dummy_card(), {"controller": controller, "reason": "diagnostic"})
	druid.current_ap = 20
	if not controller.play_card(druid, card, [druid], {"ordered_discard_cards": [fodder]}):
		_fail("DRUID_REMAINING: canopy upright play failed")
	elif not druid.druid_transformed or not druid.mana_zone.has(fodder):
		_fail("DRUID_REMAINING: canopy upright did not move selected card and transform")

	_reset_druid(druid, true)
	card = template.duplicate() as CardData
	fodder = _dummy_card()
	druid.hand.assign([card, fodder])
	druid.gain_armor(4, {"controller": controller})
	druid.current_ap = 20
	if not controller.play_card(druid, card, [druid], {"ordered_discard_cards": [fodder]}):
		_fail("DRUID_REMAINING: canopy inverted play failed")
		return
	if druid.get_armor_stacks() != 8 or not druid.has_status("druid_canopy_shelter"):
		_fail("DRUID_REMAINING: canopy inverted armor setup incorrect")
	var shelter := druid.get_status("druid_canopy_shelter")
	var hand_before := druid.hand.size()
	shelter.on_turn_start(druid, {"controller": controller})
	druid.remove_expired_statuses()
	if druid.get_armor_stacks() != 4 or druid.hand.size() < hand_before:
		_fail("DRUID_REMAINING: canopy shelter expiry incorrect")


func _test_bloodwood_covenant(controller: BattleController, druid: BattleUnitState, ally: BattleUnitState, enemy: BattleUnitState) -> void:
	var template := load("res://resources/cards/druid_bloodwood_covenant.tres") as CardData
	_reset_druid(druid, false)
	ally.statuses.clear()
	var card := template.duplicate() as CardData
	druid.hand.assign([card, _dummy_card()])
	druid.current_ap = 20
	if not controller.play_card(druid, card, [ally]):
		_fail("DRUID_REMAINING: bloodwood ally play failed")
	elif ally.get_status_damage_bonus() <= 0:
		_fail("DRUID_REMAINING: bloodwood ally buff missing")

	_reset_druid(druid, true)
	enemy.statuses.clear()
	enemy.set_current_health(enemy.get_max_health())
	card = template.duplicate() as CardData
	var first := _dummy_card()
	var second := _dummy_card()
	druid.hand.assign([card, first, second])
	druid.current_ap = 20
	if not controller.play_card(druid, card, [enemy], {"ordered_discard_cards": [first, second]}):
		_fail("DRUID_REMAINING: bloodwood inverted play failed")
	elif enemy.get_current_health() >= enemy.get_max_health() or not druid.mana_zone.has(card):
		_fail("DRUID_REMAINING: bloodwood inverted strike or mana destination failed")


func _test_overgrowth_graft(controller: BattleController, druid: BattleUnitState, ally: BattleUnitState, enemy: BattleUnitState) -> void:
	var template := load("res://resources/cards/druid_overgrowth_graft.tres") as CardData
	_reset_druid(druid, false)
	ally.mana_zone.clear()
	ally.enchant_zone.clear()
	var card := template.duplicate() as CardData
	var selected := _dummy_card()
	druid.hand.assign([card, selected])
	druid.current_ap = 20
	if not controller.play_card(druid, card, [ally], {"ordered_discard_cards": [selected]}):
		_fail("DRUID_REMAINING: graft upright play failed")
	elif not ally.mana_zone.has(card) or not ally.mana_zone.has(selected) or ally.druid_temporary_mana != 1:
		_fail("DRUID_REMAINING: graft upright zone transfer failed")

	_reset_druid(druid, true)
	enemy.statuses.clear()
	enemy.set_current_health(enemy.get_max_health())
	card = template.duplicate() as CardData
	druid.hand.assign([card])
	druid.set_current_health(maxi(1, druid.get_max_health() - 10))
	var health_before := druid.get_current_health()
	druid.current_ap = 20
	if not controller.play_card(druid, card, [enemy]):
		_fail("DRUID_REMAINING: graft inverted play failed")
		return
	if enemy.get_current_health() >= enemy.get_max_health() or druid.get_current_health() <= health_before:
		_fail("DRUID_REMAINING: graft inverted strikes or lifesteal failed")
	var temporary_before := druid.druid_temporary_mana
	var other_mana := _dummy_card()
	druid.add_card_to_mana_zone(other_mana, {
		"controller": controller,
		"reason": "diagnostic_other_mana",
		"source_card": other_mana,
	})
	if druid.druid_temporary_mana != temporary_before + 1:
		_fail("DRUID_REMAINING: graft mana gain hook failed")


func _reset_druid(druid: BattleUnitState, transformed: bool) -> void:
	druid.hand.clear()
	druid.discard_pile.clear()
	druid.mana_zone.clear()
	druid.enchant_zone.clear()
	druid.statuses.clear()
	druid.druid_temporary_mana = 0
	druid.set_druid_transformed(transformed)
	druid.set_current_health(druid.get_max_health())


func _dummy_card() -> CardData:
	return (load("res://resources/cards/battle_strike.tres") as CardData).duplicate() as CardData


func _deploy_players(controller: BattleController) -> void:
	for index in range(controller.player_units.size()):
		var cell := Vector2i(index % controller.map_data.player_deployment_columns, index + 2)
		if not controller.deploy_player_unit_at_cell(controller.player_units[index], cell):
			_fail("DRUID_REMAINING: failed to deploy player")


func _find_druid(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit.is_druid():
			return unit
	return null


func _find_ally(controller: BattleController, druid: BattleUnitState) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != druid:
			return unit
	return null


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)


func _finish() -> void:
	get_tree().quit(_exit_code)
