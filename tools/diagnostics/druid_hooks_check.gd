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

	_test_enchant_strike_hook(controller, druid)
	_test_forced_drain_draw_hook(controller, druid)
	_test_special_zone_enter_hook(controller, druid)

	print("HOOK_DIAG: completed")
	get_tree().quit(_exit_code)


func _test_enchant_strike_hook(controller: BattleController, druid: BattleUnitState) -> void:
	var binding := load("res://resources/cards/druid_binding_enchantment.tres") as CardData
	if binding == null:
		_fail("HOOK_DIAG: failed to load binding enchantment card")
		return

	druid.enchant_zone.clear()
	druid.statuses.clear()
	if druid.hand.is_empty():
		druid.hand.append(binding)
	druid.add_card_to_enchant_zone(binding, {"controller": controller, "reason": "diagnostic"})
	var before := _armor_stacks(druid)
	druid.notify_after_strike({
		"controller": controller,
		"attacker": druid,
		"source": binding,
		"actual_damage": 1,
	})
	var after := _armor_stacks(druid)
	if after <= before:
		_fail("HOOK_DIAG: enchant after-strike hook did not grant armor")


func _test_forced_drain_draw_hook(controller: BattleController, druid: BattleUnitState) -> void:
	var drain := load("res://resources/cards/druid_forced_drain.tres") as CardData
	var draw_card := load("res://resources/cards/druid_rooted_insight.tres") as CardData
	if drain == null or draw_card == null:
		_fail("HOOK_DIAG: failed to load forced drain test cards")
		return

	druid.mana_zone.clear()
	druid.hand.clear()
	druid.statuses.clear()
	druid.discard_pile.clear()
	druid.draw_pile.clear()
	druid.druid_temporary_mana = 0
	druid.add_card_to_mana_zone(drain, {"controller": controller, "reason": "diagnostic"})
	druid.draw_pile.append(draw_card)
	var before_health := druid.get_current_health()
	druid.draw_cards(1, controller.rng, {"controller": controller, "reason": "diagnostic_draw"})
	if druid.get_current_health() >= before_health:
		_fail("HOOK_DIAG: forced drain draw hook did not cause health loss")
	if druid.mana_zone.find(drain) < 0:
		_fail("HOOK_DIAG: forced drain paid with its own mana")


func _test_special_zone_enter_hook(controller: BattleController, druid: BattleUnitState) -> void:
	var claws := load("res://resources/cards/druid_channeling_claws.tres") as CardData
	if claws == null:
		_fail("HOOK_DIAG: failed to load channeling claws card")
		return

	druid.mana_zone.clear()
	druid.druid_temporary_mana = 0
	druid.add_card_to_mana_zone(claws, {
		"controller": controller,
		"reason": "druid_inverted_card_played",
		"source_card": claws,
	})
	if druid.druid_temporary_mana < 1:
		_fail("HOOK_DIAG: special-zone enter hook did not grant temporary mana")


func _armor_stacks(unit: BattleUnitState) -> int:
	var armor := unit.get_status("armor")
	if armor == null:
		return 0

	return armor.stacks


func _find_druid(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != null and unit.is_druid():
			return unit

	return null


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
	print("ERROR: " + message)
