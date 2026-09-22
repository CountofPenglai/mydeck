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
	druid.current_ap = 20
	if not controller.play_card(druid, card, [druid]):
		_fail("DRUID_REMAINING: canopy upright play failed")
	var selected: Array[CardData] = [fodder]
	if not controller.resolution_runner.submit_hand_card_choice(selected):
		_fail("DRUID_REMAINING: canopy upright selection failed")
	elif not druid.druid_transformed or not druid.mana_zone.has(fodder):
		_fail("DRUID_REMAINING: canopy upright did not move selected card and transform")

	_reset_druid(druid, true)
	card = template.duplicate() as CardData
	druid.hand.assign([card])
	druid.add_card_to_mana_zone(_dummy_card(), {"controller": controller, "reason": "diagnostic"})
	druid.draw_pile.append(_dummy_card())
	druid.current_ap = 20
	if not controller.play_card(druid, card, [druid]):
		_fail("DRUID_REMAINING: canopy inverted play failed")
		return
	if druid.get_armor_stacks() != 5 or not druid.mana_zone.has(card):
		_fail("DRUID_REMAINING: canopy inverted must count existing mana, draw, and enter mana")


func _test_bloodwood_covenant(controller: BattleController, druid: BattleUnitState, ally: BattleUnitState, enemy: BattleUnitState) -> void:
	var template := load("res://resources/cards/druid_bloodwood_covenant.tres") as CardData
	_reset_druid(druid, false)
	ally.statuses.clear()
	var card := template.duplicate() as CardData
	druid.hand.assign([card])
	druid.gain_mana(3, {"controller": controller})
	druid.current_ap = 20
	if not controller.play_card(druid, card, [ally]):
		_fail("DRUID_REMAINING: bloodwood ally play failed")
	elif ally.get_status_damage_bonus() != 3 or not ally.has_status("druid_root"):
		_fail("DRUID_REMAINING: covenant must use stored mana and apply root")

	_reset_druid(druid, true)
	enemy.statuses.clear()
	enemy.set_current_health(enemy.get_max_health())
	card = template.duplicate() as CardData
	druid.hand.assign([card])
	druid.add_status((load("res://scripts/status/druid_root_status.gd") as GDScript).new())
	enemy.add_status((load("res://scripts/status/druid_root_status.gd") as GDScript).new())
	druid.current_ap = 20
	if not controller.play_card(druid, card, [enemy]):
		_fail("DRUID_REMAINING: bloodwood inverted play failed")
	elif enemy.get_current_health() >= enemy.get_max_health() or druid.mana_zone.has(card):
		_fail("DRUID_REMAINING: root strike must discard rather than enter mana")


func _test_overgrowth_graft(controller: BattleController, druid: BattleUnitState, ally: BattleUnitState, enemy: BattleUnitState) -> void:
	var template := load("res://resources/cards/druid_overgrowth_graft.tres") as CardData
	_reset_druid(druid, false)
	druid.mana_zone.clear()
	var card := template.duplicate() as CardData
	druid.hand.assign([card])
	druid.current_ap = 20
	var ap_before: int = druid.current_ap
	if controller.play_card(druid, card, [druid]) or druid.current_ap != ap_before or not druid.hand.has(card):
		_fail("DRUID_REMAINING: graft upright must reject self without spending")
	if not controller.play_card(druid, card, [ally]):
		_fail("DRUID_REMAINING: graft upright other-target play failed")
	elif not druid.mana_zone.has(card) or not ally.has_status("druid_root"):
		_fail("DRUID_REMAINING: graft upright must root another target and enter owner mana")

	_reset_druid(druid, true)
	enemy.statuses.clear()
	enemy.set_current_health(enemy.get_max_health())
	card = template.duplicate() as CardData
	druid.hand.assign([card])
	druid.gain_mana(2, {"controller": controller})
	druid.add_status((load("res://scripts/status/druid_root_status.gd") as GDScript).new())
	druid.set_current_health(maxi(1, druid.get_max_health() - 10))
	var health_before := druid.get_current_health()
	druid.current_ap = 20
	if not controller.play_card(druid, card, [enemy]):
		_fail("DRUID_REMAINING: graft inverted play failed")
		return
	if enemy.get_current_health() >= enemy.get_max_health() or druid.get_current_health() <= health_before or druid.has_status("druid_root"):
		_fail("DRUID_REMAINING: graft must perform rooted third lifesteal strike")


func _reset_druid(druid: BattleUnitState, transformed: bool) -> void:
	druid.hand.clear()
	druid.discard_pile.clear()
	druid.mana_zone.clear()
	druid.enchant_zone.clear()
	druid.statuses.clear()
	druid.clear_mana()
	druid.set_druid_transformed(transformed)
	druid.set_current_health(druid.get_max_health())


func _dummy_card() -> CardData:
	return (load("res://resources/cards/battle_slam.tres") as CardData).duplicate() as CardData


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
