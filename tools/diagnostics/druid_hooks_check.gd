extends Node

var _exit_code := 0


func _ready() -> void:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if scenario == null:
		_fail("HOOK_DIAG: failed to load sample battle scenario")
		get_tree().quit(_exit_code)
		return

	var controller := BattleController.new()
	controller.setup(scenario)
	var druid := _find_druid(controller)
	if druid == null:
		_fail("HOOK_DIAG: no druid unit in sample battle")
		get_tree().quit(_exit_code)
		return

	_test_binding_turn_start_hook(controller, druid)
	_test_forced_drain_turn_start_hook(controller, druid)
	_test_channeling_claws_has_no_zone_entry_hook(controller, druid)

	print("HOOK_DIAG: completed")
	get_tree().quit(_exit_code)


func _test_binding_turn_start_hook(controller: BattleController, druid: BattleUnitState) -> void:
	var binding := load("res://resources/cards/druid_binding_enchantment.tres") as CardData
	if binding == null:
		_fail("HOOK_DIAG: failed to load binding enchantment card")
		return

	druid.mana_zone.clear()
	druid.statuses.clear()
	druid.draw_pile.clear()
	druid.draw_pile.append(load("res://resources/cards/druid_rooted_insight.tres") as CardData)
	druid.add_card_to_mana_zone(binding, {"controller": controller, "reason": "diagnostic"})
	var before: int = druid.hand.size()
	binding.effect.on_zone_owner_turn_start(druid, binding, {"controller": controller, "zone_name": "mana"})
	if druid.hand.size() != before + 1:
		_fail("HOOK_DIAG: binding mana turn-start hook did not draw")


func _test_forced_drain_turn_start_hook(controller: BattleController, druid: BattleUnitState) -> void:
	var drain := load("res://resources/cards/druid_forced_drain.tres") as CardData
	if drain == null or controller.enemy_units.is_empty():
		_fail("HOOK_DIAG: failed to load forced drain fixture")
		return

	druid.mana_zone.clear()
	druid.hand.clear()
	druid.statuses.clear()
	druid.clear_mana()
	druid.add_card_to_mana_zone(drain, {"controller": controller, "reason": "diagnostic"})
	var enemy := controller.enemy_units[0] as BattleUnitState
	enemy.statuses.clear()
	enemy.set_current_health(1)
	enemy.add_status((load("res://scripts/status/druid_root_status.gd") as GDScript).new())
	druid.set_current_health(maxi(1, druid.get_max_health() - 2))
	var before_health: int = druid.get_current_health()
	drain.effect.on_zone_owner_turn_start(druid, drain, {"controller": controller, "zone_name": "mana"})
	if enemy.is_alive() or druid.get_current_health() != before_health + 1:
		_fail("HOOK_DIAG: forced drain turn-start hook must lose life through armor and heal actual loss")


func _test_channeling_claws_has_no_zone_entry_hook(controller: BattleController, druid: BattleUnitState) -> void:
	var claws := load("res://resources/cards/druid_channeling_claws.tres") as CardData
	if claws == null:
		_fail("HOOK_DIAG: failed to load channeling claws card")
		return

	druid.mana_zone.clear()
	druid.clear_mana()
	druid.add_card_to_mana_zone(claws, {
		"controller": controller,
		"reason": "druid_inverted_card_played",
		"source_card": claws,
	})
	if druid.get_available_mana() != 0:
		_fail("HOOK_DIAG: channeling claws must not grant mana merely by entering a zone")


func _find_druid(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != null and unit.is_druid():
			return unit

	return null


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
	print("ERROR: " + message)
