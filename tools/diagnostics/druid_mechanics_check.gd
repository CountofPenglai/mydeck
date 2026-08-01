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
	_test_moonlight_targets(controller, druid)

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
	_test_root_counter_damage(controller, druid)

	print("DRUID_DIAG: completed")
	get_tree().quit(_exit_code)


func _test_moonlight_targets(controller: BattleController, druid: BattleUnitState) -> void:
	var moonlight := load("res://resources/cards/druid_moonlit_mend.tres") as CardData
	var ordinary_attack := load("res://resources/cards/battle_slam.tres") as CardData
	var ally := _find_other_player(controller, druid)
	var enemy: BattleUnitState = controller.enemy_units[0] if not controller.enemy_units.is_empty() else null
	if moonlight == null or ordinary_attack == null or ally == null or enemy == null:
		_fail("DRUID_DIAG: moonlight target diagnostic resources missing")
		return

	ally.set_hex_cell(Vector2i(druid.cell.x + 1, druid.cell.y), controller.map_data)
	enemy.set_hex_cell(Vector2i(druid.cell.x + 2, druid.cell.y), controller.map_data)
	if not controller.can_preview_card_targets(druid, moonlight, [ally]):
		_fail("DRUID_DIAG: moonlight rejected an allied target")
	if not controller.can_preview_card_targets(druid, moonlight, [enemy]):
		_fail("DRUID_DIAG: moonlight rejected an enemy target")
	if controller.can_preview_card_targets(druid, ordinary_attack, [ally]):
		_fail("DRUID_DIAG: ordinary attack incorrectly accepted an allied target")

	ally.set_current_health(maxi(1, ally.get_max_health() - 6))
	var ally_health_before := ally.get_current_health()
	moonlight.effect.play({
		"controller": controller,
		"user": druid,
		"card": moonlight,
	}, [ally])
	if ally.get_current_health() <= ally_health_before:
		_fail("DRUID_DIAG: moonlight did not heal its allied target")

	enemy.set_current_health(enemy.get_max_health())
	var enemy_health_before := enemy.get_current_health()
	moonlight.effect.play({
		"controller": controller,
		"user": druid,
		"card": moonlight,
	}, [enemy])
	if enemy.get_current_health() >= enemy_health_before:
		_fail("DRUID_DIAG: moonlight did not damage its enemy target")


func _test_root_counter_damage(controller: BattleController, druid: BattleUnitState) -> void:
	var template := load("res://resources/cards/druid_verdant_strike.tres") as CardData
	var enemy: BattleUnitState = controller.enemy_units[0] if not controller.enemy_units.is_empty() else null
	if template == null or enemy == null:
		_fail("DRUID_DIAG: root counter resources missing")
		return
	druid.set_druid_transformed(true, {"controller": controller, "reason": "diagnostic"})
	if druid.get_active_weapon_face_index() != 1:
		_fail("DRUID_DIAG: transformed druid did not project the weapon back face")
		return
	var profile := druid.build_strike_profile_object()
	if profile.primary_base_damage != 3:
		_fail("DRUID_DIAG: root counter resolved base damage %d instead of bear damage 3" % profile.primary_base_damage)
	enemy.statuses.clear()
	enemy.set_current_health(enemy.get_max_health())
	enemy.set_hex_cell(Vector2i(druid.cell.x + 1, druid.cell.y), controller.map_data)
	var root_counter := template.duplicate(true) as CardData
	druid.hand.append(root_counter)
	druid.current_ap = 10
	var health_before := enemy.get_current_health()
	if not controller.play_card(druid, root_counter, [enemy]):
		_fail("DRUID_DIAG: root counter could not be played through the controller")
	if health_before - enemy.get_current_health() <= 1:
		_fail("DRUID_DIAG: root counter still dealt only one damage")
	var equipped_weapon := druid.character_state.weapon_equipment
	druid.character_state.weapon_equipment = null
	var unarmed_root_counter := template.duplicate(true) as CardData
	druid.hand.append(unarmed_root_counter)
	if controller.play_card(druid, unarmed_root_counter, [enemy]):
		_fail("DRUID_DIAG: root counter silently fell back to an unarmed strike")
	druid.character_state.weapon_equipment = equipped_weapon


func _deploy_players(controller: BattleController) -> void:
	for index in range(controller.player_units.size()):
		var unit: BattleUnitState = controller.player_units[index]
		var cell := Vector2i(index % controller.map_data.player_deployment_columns, index + 2)
		if not controller.deploy_player_unit_at_cell(unit, cell):
			_fail("DRUID_DIAG: failed to deploy %s" % unit.get_display_name())


func _find_druid(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != null and unit.is_druid():
			return unit

	return null


func _find_other_player(controller: BattleController, excluded: BattleUnitState) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != null and unit != excluded:
			return unit
	return null


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
	print("ERROR: " + message)
