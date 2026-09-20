extends Node

class StealthListener extends EquipmentEffect:
	var calls := 0
	var opportunity_seen := false

	func on_ranger_stealth_entered(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
		calls += 1
		opportunity_seen = _owner.ranger_state.get("blend_opportunity_available") == true


var _exit_code := 0


func _ready() -> void:
	_test_stealth_modifies_only_ranger_threat_and_not_traps()
	_test_real_stealth_entry_refreshes_before_listener_and_repeat_is_inert()
	_test_turn_start_and_battle_reset_supply_one_non_accumulating_opportunity()
	_test_blend_is_free_visible_and_consumes_one_opportunity()
	_test_invalid_blends_preserve_elements_payload_and_opportunity()
	_test_blend_rejects_unavailable_weapon_and_resolution_notification()
	_test_reenter_refreshes_after_consumption_and_action_stack_blocks_preparation()
	print("RANGER_STEALTH_BLEND_DIAG: completed")
	get_tree().quit(_exit_code)


func _test_stealth_modifies_only_ranger_threat_and_not_traps() -> void:
	var f := _fixture()
	var base_threat: int = f.r.get_threat_level()
	if not f.r.enter_stealth():
		_fail("threat: fixture ranger could not enter stealth")
		return
	if f.r.get_threat_level() != maxi(0, base_threat - 1):
		_fail("threat: stealth did not contribute exactly -1 to computed ranger threat")
	f.r.threat_level_modifier = -9
	if f.r.get_threat_level() != 0:
		_fail("threat: stealth did not retain the computed-threat lower clamp")
	f.r.is_deployed = true
	f.r.set_hex_cell(Vector2i(2, 2), f.c.map_data)
	f.c.apply_advanced_surface(Vector2i(3, 2), BattleSurfaceState.Element.ICE)
	var trap: BattleObjectState = f.c.place_elemental_trap(f.r, Vector2i(3, 2))
	if trap == null or trap.get_threat_level() != 1:
		_fail("threat: elemental trap was coupled to its stealthed owner's threat")


func _test_real_stealth_entry_refreshes_before_listener_and_repeat_is_inert() -> void:
	var f := _fixture()
	var listener := StealthListener.new()
	var equipment := EquipmentData.new()
	equipment.passive_effects.append(listener)
	f.r.character_state.weapon_equipment = equipment
	f.r.get_equipment_runtime_state(equipment)
	f.r.ranger_state.set("blend_opportunity_available", false)
	f.r.turn_serial = 7
	if not f.r.enter_stealth():
		_fail("stealth entry: real entry was rejected")
		return
	var expiry: int = f.r.ranger_state.stealth_expires_turn_serial
	if not _blend_available(f.r) or listener.calls != 1 or not listener.opportunity_seen:
		_fail("stealth entry: opportunity was not refreshed before exactly one listener callback")
	if f.r.enter_stealth() or f.r.ranger_state.stealth_expires_turn_serial != expiry or listener.calls != 1 or not _blend_available(f.r):
		_fail("stealth entry: repeated entry refreshed duration/opportunity or notified listeners")


func _test_turn_start_and_battle_reset_supply_one_non_accumulating_opportunity() -> void:
	var f := _fixture()
	if not _blend_available(f.r):
		_fail("opportunity: battle reset did not initialize an available blend opportunity")
	f.r.ranger_state.set("blend_opportunity_available", false)
	f.r.start_turn(f.c.config)
	if not _blend_available(f.r):
		_fail("opportunity: own turn start did not restore one available opportunity")
	f.r.ranger_state.set("blend_opportunity_available", true)
	f.r.leave_stealth()
	if not f.r.enter_stealth() or not _blend_available(f.r):
		_fail("opportunity: entering stealth did not cap refresh at one available opportunity")


func _test_blend_is_free_visible_and_consumes_one_opportunity() -> void:
	var f := _fixture()
	f.r.ranger_state.add_element(BattleSurfaceState.Element.FIRE)
	if _can_prepare(f.c, f.r):
		_fail("blend: visible eligibility accepted fewer than two element types")
	_seed_two_types(f.r)
	var ap: int = f.r.current_ap
	if not _can_prepare(f.c, f.r):
		_fail("blend: visible eligibility rejected an active living ranger with two element types")
		return
	if not _prepare(f.c, f.r, BattleSurfaceState.Element.STEAM, "weapon"):
		_fail("blend: valid non-stealthed preparation was rejected")
		return
	if f.r.current_ap != ap or _blend_available(f.r) or f.r.ranger_state.prepared_blend != BattleSurfaceState.Element.STEAM:
		_fail("blend: successful preparation charged AP, kept opportunity, or failed to load payload")
	if _can_prepare(f.c, f.r) or _prepare(f.c, f.r, BattleSurfaceState.Element.STEAM, "weapon"):
		_fail("blend: consumed opportunity permitted a second preparation")


func _test_invalid_blends_preserve_elements_payload_and_opportunity() -> void:
	var f := _fixture()
	_seed_two_types(f.r)
	var before: Dictionary = f.r.ranger_state.element_inventory.duplicate(true)
	if _prepare(f.c, f.r, BattleSurfaceState.Element.STEAM, "weapon", BattleSurfaceState.Element.EARTH):
		_fail("blend validation: recipe accepted a catalyst missing from inventory")
	if not _blend_available(f.r) or f.r.ranger_state.prepared_blend != BattleSurfaceState.Element.NONE or f.r.ranger_state.element_inventory != before:
		_fail("blend validation: failed catalyst payment consumed opportunity, elements, or changed payload")
	if _prepare(f.c, f.r, BattleSurfaceState.Element.NONE, "weapon"):
		_fail("blend validation: invalid recipe was accepted")
	if not _blend_available(f.r) or f.r.ranger_state.prepared_blend != BattleSurfaceState.Element.NONE or f.r.ranger_state.element_inventory != before:
		_fail("blend validation: invalid recipe consumed opportunity, elements, or changed payload")
	if not _prepare(f.c, f.r, BattleSurfaceState.Element.STEAM, "weapon"):
		_fail("blend validation: fixture failed to create a loaded payload")
		return
	var loaded: int = f.r.ranger_state.prepared_blend
	var remaining: Dictionary = f.r.ranger_state.element_inventory.duplicate(true)
	f.r.ranger_state.set("blend_opportunity_available", true)
	if _prepare(f.c, f.r, BattleSurfaceState.Element.LAVA, "weapon"):
		_fail("blend validation: existing payload was overwritten")
	if not _blend_available(f.r) or f.r.ranger_state.prepared_blend != loaded or f.r.ranger_state.element_inventory != remaining:
		_fail("blend validation: loaded payload rejection consumed opportunity or inventory")


func _test_blend_rejects_unavailable_weapon_and_resolution_notification() -> void:
	var f := _fixture()
	_seed_two_types(f.r)
	var before: Dictionary = f.r.ranger_state.element_inventory.duplicate(true)
	if _prepare(f.c, f.r, BattleSurfaceState.Element.STEAM, "not-a-real-weapon-slot"):
		_fail("blend safety: unavailable weapon slot created a dead blend payload")
	if not _blend_available(f.r) or f.r.ranger_state.element_inventory != before:
		_fail("blend safety: unavailable weapon slot spent elements or opportunity")
	var options: Array = f.r.get_attack_weapon_options()
	if options.is_empty():
		_fail("blend safety: fixture ranger had no usable weapon option")
		return
	var slot := str((options[0] as Dictionary).get("slot", ""))
	f.c.resolution_state_notification_active = true
	if _can_prepare(f.c, f.r) or _prepare(f.c, f.r, BattleSurfaceState.Element.STEAM, slot):
		_fail("blend safety: blend was allowed during resolution-state notification")
	if not _blend_available(f.r) or f.r.ranger_state.element_inventory != before:
		_fail("blend safety: resolution-state rejection spent elements or opportunity")
	f.c.resolution_state_notification_active = false


func _test_reenter_refreshes_after_consumption_and_action_stack_blocks_preparation() -> void:
	var f := _fixture()
	_seed_two_types(f.r)
	if not _prepare(f.c, f.r, BattleSurfaceState.Element.STEAM, "weapon"):
		_fail("refresh: setup preparation was rejected")
		return
	f.r.ranger_state.prepared_blend = BattleSurfaceState.Element.NONE
	f.r.ranger_state.prepared_weapon_slot = ""
	if not f.r.enter_stealth() or not _blend_available(f.r):
		_fail("refresh: actual entry did not restore an already-consumed opportunity")
		return
	_seed_two_types(f.r)
	if not _prepare(f.c, f.r, BattleSurfaceState.Element.STEAM, "weapon"):
		_fail("refresh: second setup preparation was rejected")
		return
	f.r.ranger_state.prepared_blend = BattleSurfaceState.Element.NONE
	f.r.ranger_state.prepared_weapon_slot = ""
	if not f.r.leave_stealth() or not f.r.enter_stealth() or not _blend_available(f.r):
		_fail("refresh: leave then real reentry did not restore an already-consumed opportunity")
		return
	f.c.action_resolution_active = true
	if _can_prepare(f.c, f.r) or _prepare(f.c, f.r, BattleSurfaceState.Element.STEAM, "weapon"):
		_fail("free time: blend preparation was allowed while the action stack was resolving")
	if not _blend_available(f.r) or f.r.ranger_state.prepared_blend != BattleSurfaceState.Element.NONE:
		_fail("free time: rejected action-stack preparation mutated opportunity or payload")
	f.c.action_resolution_active = false


func _fixture() -> Dictionary:
	var scenario := (load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario).duplicate(true) as BattleScenario
	var controller := BattleController.new()
	controller.setup(scenario)
	var ranger := _find_ranger(controller)
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.current_unit = ranger
	ranger.is_deployed = true
	ranger.current_ap = 6
	ranger.turn_serial = 1
	return {"c": controller, "r": ranger}


func _find_ranger(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit.is_ranger():
			return unit
	return null


func _seed_two_types(ranger: BattleUnitState) -> void:
	ranger.ranger_state.element_inventory.clear()
	ranger.ranger_state.add_element(BattleSurfaceState.Element.FIRE)
	ranger.ranger_state.add_element(BattleSurfaceState.Element.WATER)


func _blend_available(ranger: BattleUnitState) -> bool:
	return ranger.ranger_state.get("blend_opportunity_available") == true


func _can_prepare(controller: BattleController, ranger: BattleUnitState) -> bool:
	return controller.has_method("can_prepare_ranger_blend") and controller.call("can_prepare_ranger_blend", ranger) == true


func _prepare(controller: BattleController, ranger: BattleUnitState, blend: int, slot: String, catalyst: int = BattleSurfaceState.Element.NONE) -> bool:
	return controller.has_method("prepare_ranger_blend") and controller.call("prepare_ranger_blend", ranger, blend, slot, catalyst) == true


func _fail(message: String) -> void:
	_exit_code = 1
	push_error("RANGER_STEALTH_BLEND_DIAG: " + message)
	print("ERROR: " + message)
