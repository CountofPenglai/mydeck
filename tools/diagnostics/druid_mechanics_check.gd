extends Node

var _exit_code := 0


func _ready() -> void:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if scenario == null:
		_fail("DRUID_DIAG: failed to load sample battle scenario")
		get_tree().quit(_exit_code)
		return

	var controller := BattleController.new()
	controller.setup(scenario)
	_deploy_players(controller)
	if not controller.start_battle():
		_fail("DRUID_DIAG: failed to start battle")
		get_tree().quit(_exit_code)
		return

	var druid := _find_druid(controller)
	if druid == null:
		_fail("DRUID_DIAG: no druid unit in sample battle")
		get_tree().quit(_exit_code)
		return

	var guard := 0
	while controller.current_unit != druid and guard < 12 and controller.phase == BattleController.Phase.BATTLE:
		controller.end_current_turn()
		guard += 1

	if controller.current_unit != druid:
		_fail("DRUID_DIAG: could not advance to druid turn")
		get_tree().quit(_exit_code)
		return
	if druid.hand.is_empty():
		_fail("DRUID_DIAG: druid has empty hand")
		get_tree().quit(_exit_code)
		return

	var hand_before := druid.hand.size()
	var mana_before := druid.mana_zone.size()
	var selected_card: CardData = druid.hand.back() as CardData
	if not controller.use_druid_prepare_transform(druid, selected_card):
		_fail("DRUID_DIAG: prepare transform returned false")
		get_tree().quit(_exit_code)
		return

	if not druid.druid_transformed:
		_fail("DRUID_DIAG: druid did not transform")
	if druid.hand.size() != hand_before - 1:
		_fail("DRUID_DIAG: prepare did not consume exactly one hand card")
	if druid.mana_zone.size() != mana_before + 1:
		_fail("DRUID_DIAG: prepare did not add exactly one mana-zone card")
	elif druid.mana_zone.back() != selected_card:
		_fail("DRUID_DIAG: selected hand card was not placed into mana zone")
	if druid.get_available_mana() < 1:
		_fail("DRUID_DIAG: available mana did not update")

	print("DRUID_DIAG: completed")
	get_tree().quit(_exit_code)


func _deploy_players(controller: BattleController) -> void:
	var deploy_rect := controller.map_data.player_deployment_rect
	for index in range(controller.player_units.size()):
		var unit: BattleUnitState = controller.player_units[index]
		var position := deploy_rect.position + Vector2(64.0 + float(index) * 72.0, deploy_rect.size.y * 0.5)
		if not controller.deploy_player_unit(unit, position):
			_fail("DRUID_DIAG: failed to deploy %s" % unit.get_display_name())


func _find_druid(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != null and unit.is_druid():
			return unit

	return null


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
	print("ERROR: " + message)
