extends Node

const WEAPONS := {
	"druid_brute_bear": [4, 2, 3, 1],
	"druid_wind_cheetah": [5, 3, 3, 1],
	"druid_rise_eagle": [4, 3, 2, 2],
	"druid_lantern_fire": [3, 1, 5, 2],
	"druid_chaos_viper": [2, 2, 3, 1],
	"druid_dragon": [8, 1, 1, 1],
	"druid_star_firefly": [3, 3, 0, 3],
	"druid_kaleidoscope": [5, 1, 1, 5],
	"druid_double_slime": [2, 4, 6, 1],
}

var _exit_code := 0


func _ready() -> void:
	var controller := BattleController.new()
	controller.setup(load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario)
	var druid := _find_druid(controller)
	var enemy: BattleUnitState = controller.enemy_units[0] if not controller.enemy_units.is_empty() else null
	if druid == null or enemy == null:
		_fail("DRUID_WEAPONS: missing diagnostic units")
		get_tree().quit(_exit_code)
		return
	controller.phase = BattleController.Phase.BATTLE
	controller.current_unit = druid
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	druid.turn_serial = 1
	druid.is_deployed = true
	druid.set_hex_cell(Vector2i(2, 4), controller.map_data)
	enemy.set_hex_cell(Vector2i(3, 4), controller.map_data)
	_test_resources_and_faces(druid)
	_test_mana_capacity(druid, controller)
	_test_eagle_armor_bypass(druid, enemy, controller)
	_test_chaos_conversion(druid, enemy, controller)
	_test_dragon_repeat_armor(druid, enemy, controller)
	_test_runtime_actions(druid, controller)
	_test_star_projection(druid, enemy, controller)
	_test_double_body(druid, controller)
	_test_kaleidoscope_resonance(druid)
	_test_kaleidoscope_borrowed_origin(druid, controller)
	_test_kaleidoscope_wager_charge(druid)
	_test_kaleidoscope_mirror(druid, controller)
	_test_chaos_transmutation(druid, controller)
	_test_corrosion_lifecycle(druid, enemy, controller)
	print("DRUID_WEAPONS: completed")
	get_tree().quit(_exit_code)


func _test_resources_and_faces(druid: BattleUnitState) -> void:
	for resource_name in WEAPONS:
		var weapon := load("res://resources/items/%s.tres" % resource_name) as EquipmentData
		var expected: Array = WEAPONS[resource_name]
		if weapon == null or weapon.back_face == null or not weapon.has_tag("druid_weapon"):
			_fail("DRUID_WEAPONS: invalid resource %s" % resource_name)
			continue
		if [weapon.base_damage, weapon.attack_range, weapon.back_face.base_damage, weapon.back_face.attack_range] != expected:
			_fail("DRUID_WEAPONS: values differ for %s" % resource_name)
		_set_weapon(druid, weapon)
		druid.set_druid_transformed(false)
		if druid.get_active_weapon_face_index() != 0 or druid.build_strike_profile_object().primary_range != int(expected[1]):
			_fail("DRUID_WEAPONS: upright projection failed for %s" % resource_name)
		druid.set_druid_transformed(true)
		if druid.get_active_weapon_face_index() != 1 or druid.build_strike_profile_object().primary_range != int(expected[3]):
			_fail("DRUID_WEAPONS: inverted projection failed for %s" % resource_name)
	_set_weapon(druid, load("res://resources/items/druid_kaleidoscope.tres") as EquipmentData)
	druid.set_druid_transformed(true)
	if not druid.is_flying():
		_fail("DRUID_WEAPONS: kaleidoscope inverse should grant flying")


func _test_mana_capacity(druid: BattleUnitState, controller: BattleController) -> void:
	druid.mana_zone.clear()
	druid.druid_spent_mana = 0
	druid.druid_temporary_mana = 0
	for index in range(3):
		var card := CardData.new()
		card.card_name = "mana_%d" % index
		druid.add_card_to_mana_zone(card, {"controller": controller, "reason": "diagnostic"})
	if not druid.pay_mana(2, {"controller": controller}) or druid.mana_zone.size() != 3 or druid.get_available_mana() != 1:
		_fail("DRUID_WEAPONS: mana payment consumed cards or reported wrong availability")
	druid.start_turn(controller.config)
	if druid.get_mana_capacity() != 3 or druid.get_available_mana() != 3:
		_fail("DRUID_WEAPONS: persistent mana did not refresh at turn start")


func _test_eagle_armor_bypass(druid: BattleUnitState, enemy: BattleUnitState, controller: BattleController) -> void:
	_set_weapon(druid, load("res://resources/items/druid_rise_eagle.tres") as EquipmentData)
	druid.set_druid_transformed(true)
	enemy.statuses.clear()
	enemy.set_current_health(enemy.get_max_health())
	enemy.gain_armor(99, {"controller": controller})
	var before := enemy.get_current_health()
	controller.perform_strike(druid, enemy, null, "eagle diagnostic")
	if enemy.get_current_health() >= before or enemy.get_armor_stacks() != 99:
		_fail("DRUID_WEAPONS: eagle strike did not bypass armor cleanly")


func _test_chaos_conversion(druid: BattleUnitState, enemy: BattleUnitState, controller: BattleController) -> void:
	_set_weapon(druid, load("res://resources/items/druid_chaos_viper.tres") as EquipmentData)
	druid.set_druid_transformed(false)
	enemy.statuses.clear()
	enemy.set_current_health(enemy.get_max_health())
	var before := enemy.get_current_health()
	controller.perform_strike(druid, enemy, null, "chaos diagnostic")
	var anomaly := enemy.get_status("druid_anomaly")
	if enemy.get_current_health() != before or anomaly == null or anomaly.stacks <= 0:
		_fail("DRUID_WEAPONS: chaos damage was not converted to anomaly")
	druid.set_druid_transformed(true)
	controller.perform_strike(druid, enemy, null, "viper diagnostic")
	if enemy.curse_wave <= 0:
		_fail("DRUID_WEAPONS: viper damage was not converted to curse wave")


func _test_dragon_repeat_armor(druid: BattleUnitState, enemy: BattleUnitState, controller: BattleController) -> void:
	var weapon := load("res://resources/items/druid_dragon.tres") as EquipmentData
	_set_weapon(druid, weapon)
	druid.set_druid_transformed(true)
	var runtime := druid.get_equipment_runtime_state(weapon)
	runtime.set_counter("dragon_maturity", 2)
	druid.statuses.clear()
	enemy.statuses.clear()
	enemy.set_current_health(enemy.get_max_health())
	controller.perform_strike(druid, enemy, null, "dragon armor diagnostic 1")
	controller.perform_strike(druid, enemy, null, "dragon armor diagnostic 2")
	if druid.get_armor_stacks() != 4:
		_fail("DRUID_WEAPONS: dragon should gain maturity armor after every damaging strike")


func _test_runtime_actions(druid: BattleUnitState, controller: BattleController) -> void:
	_set_weapon(druid, load("res://resources/items/druid_rise_eagle.tres") as EquipmentData)
	druid.set_druid_transformed(false)
	druid.hand.clear()
	var card := CardData.new()
	card.card_name = "updraft fodder"
	druid.hand.append(card)
	druid.notify_after_card_played(CardData.new(), {"controller": controller})
	var action := _find_action(druid, "updraft", controller)
	if action.is_empty() or not _activate(druid, action, controller):
		_fail("DRUID_WEAPONS: updraft action was unavailable")
	elif not druid.mana_zone.has(card):
		_fail("DRUID_WEAPONS: updraft did not place the selected card into mana")


func _test_star_projection(druid: BattleUnitState, enemy: BattleUnitState, controller: BattleController) -> void:
	_set_weapon(druid, load("res://resources/items/druid_star_firefly.tres") as EquipmentData)
	druid.set_druid_transformed(true)
	var runtime := druid.get_equipment_runtime_state(druid.character_state.weapon_equipment)
	runtime.set_data("firefly_projections", [Vector2i(4, 4)])
	enemy.set_hex_cell(Vector2i(6, 4), controller.map_data)
	if druid.get_range_distance_to(enemy) > 3:
		_fail("DRUID_WEAPONS: firefly projection was not used as a range origin")
	controller.perform_strike(druid, enemy, null, "projection diagnostic")
	if not (runtime.get_data("firefly_projections", []) as Array).is_empty():
		_fail("DRUID_WEAPONS: successful projection strike did not consume the projection")


func _test_double_body(druid: BattleUnitState, controller: BattleController) -> void:
	_set_weapon(druid, load("res://resources/items/druid_double_slime.tres") as EquipmentData)
	druid.set_druid_transformed(false)
	druid.set_hex_cell(Vector2i(2, 4), controller.map_data)
	druid.notify_equipment_battle_started({"controller": controller})
	var occupied_before := druid.get_occupied_cells()
	if occupied_before.size() != 2:
		_fail("DRUID_WEAPONS: double-body weapon did not create a proxy body")
		return
	var active_before := druid.cell
	druid.set_druid_transformed(true, {"controller": controller})
	if druid.cell == active_before or druid.get_occupied_cells().size() != 2:
		_fail("DRUID_WEAPONS: form change did not switch the active body")
	if controller.get_unit_at_cell(active_before) != druid:
		_fail("DRUID_WEAPONS: inactive body was not targetable as the shared unit")


func _test_kaleidoscope_resonance(druid: BattleUnitState) -> void:
	_set_weapon(druid, load("res://resources/items/druid_kaleidoscope.tres") as EquipmentData)
	druid.set_druid_transformed(true)
	var choice := CardData.new()
	choice.description = "选择一项执行。"
	choice.resonance_cost = 3
	if druid.get_card_resonance_cost(choice) != 1:
		_fail("DRUID_WEAPONS: unifier did not override choice-card resonance to 1")


func _test_kaleidoscope_borrowed_origin(druid: BattleUnitState, controller: BattleController) -> void:
	var weapon := load("res://resources/items/druid_kaleidoscope.tres") as EquipmentData
	_set_weapon(druid, weapon)
	druid.set_druid_transformed(false)
	for candidate in controller.player_units:
		if candidate != druid:
			candidate.is_deployed = true
			candidate.set_hex_cell(Vector2i(1, 4), controller.map_data)
			break
	var allies := controller.get_units_by_filter(druid, BattleController.UnitFilter.ALLIES)
	if allies.is_empty():
		_fail("DRUID_WEAPONS: borrowed-origin diagnostic needs an ally")
		return
	var runtime := druid.get_equipment_runtime_state(weapon)
	runtime.set_data("phenomena", [0])
	var effect := weapon.activated_effects[0] as EquipmentEffect
	if not effect.activate(druid, weapon, weapon, runtime, {
		"controller": controller,
		"equipment_action_id": "phenomenon_0",
		"phase": "battle",
	}):
		_fail("DRUID_WEAPONS: borrowed-origin phenomenon did not activate")
		return
	var origins := druid.get_alternate_range_origins()
	var found_ally_origin := false
	var found_reciprocal_origin := false
	for ally in allies:
		if origins.has(ally.cell):
			found_ally_origin = true
		if ally.get_alternate_range_origins().has(druid.cell):
			found_reciprocal_origin = true
	if not found_ally_origin:
		_fail("DRUID_WEAPONS: borrowed range did not expose an ally cell as an origin")
	if not found_reciprocal_origin:
		_fail("DRUID_WEAPONS: borrowed range did not expose the druid cell to the ally")


func _test_kaleidoscope_wager_charge(druid: BattleUnitState) -> void:
	var weapon := load("res://resources/items/druid_kaleidoscope.tres") as EquipmentData
	_set_weapon(druid, weapon)
	druid.set_druid_transformed(false)
	var runtime := druid.get_equipment_runtime_state(weapon)
	runtime.set_data("wager_elements", [BattleSurfaceState.Element.WATER])
	var strike_context := {}
	var effect := weapon.passive_effects[0] as EquipmentEffect
	effect.on_before_strike(druid, weapon, weapon, runtime, strike_context)
	if int(strike_context.get("surface_element", BattleSurfaceState.Element.NONE)) != BattleSurfaceState.Element.WATER:
		_fail("DRUID_WEAPONS: wager element was not attached to the next strike")
	if not (runtime.get_data("wager_elements", []) as Array).is_empty():
		_fail("DRUID_WEAPONS: wager element was not consumed by the strike")


func _test_kaleidoscope_mirror(druid: BattleUnitState, controller: BattleController) -> void:
	if controller.enemy_units.size() < 2:
		_fail("DRUID_WEAPONS: mirror diagnostic needs two enemies")
		return
	var first := controller.enemy_units[0] as BattleUnitState
	var second := controller.enemy_units[1] as BattleUnitState
	druid.set_hex_cell(Vector2i(2, 4), controller.map_data)
	first.is_deployed = true
	second.is_deployed = true
	first.set_hex_cell(Vector2i(3, 4), controller.map_data)
	second.set_hex_cell(Vector2i(2, 3), controller.map_data)
	var weapon := load("res://resources/items/druid_kaleidoscope.tres") as EquipmentData
	_set_weapon(druid, weapon)
	druid.set_druid_transformed(false)
	var runtime := druid.get_equipment_runtime_state(weapon)
	runtime.set_counter("swap_profile_turn", druid.turn_serial)
	var card := load("res://resources/cards/battle_slam.tres") as CardData
	var context := {
		"controller": controller,
		"user": druid,
		"card": card,
		"equipment_slot": "",
		"play_mode": CardEnums.CardPlayMode.NORMAL,
	}
	var duplicate_targets := druid.get_equipment_card_duplicate_targets(card, [first], context)
	if duplicate_targets.size() != 1 or duplicate_targets[0] != second:
		_fail("DRUID_WEAPONS: mirror did not select a second legal target")
		return
	second.statuses.clear()
	second.curse_wave = 0
	var damage_context := DamageContext.create(controller, druid, second, 3, "mirror diagnostic")
	damage_context.metadata["action_id"] = controller.get_current_action_id()
	druid.modify_outgoing_damage(damage_context)
	if not bool(damage_context.metadata.get("converted_to_status", false)):
		_fail("DRUID_WEAPONS: mirror damage was not converted")
	if second.get_status("druid_anomaly") == null or second.curse_wave <= 0:
		_fail("DRUID_WEAPONS: mirror damage did not create both anomaly and curse wave")


func _test_chaos_transmutation(druid: BattleUnitState, controller: BattleController) -> void:
	var weapon := load("res://resources/items/druid_chaos_viper.tres") as EquipmentData
	_set_weapon(druid, weapon)
	druid.set_druid_transformed(false)
	controller.surface_state.add_persistent_source(
		druid.cell,
		BattleSurfaceState.Element.FIRE,
		"diagnostic:chaos",
		"diagnostic"
	)
	var action := _find_action(druid, "transmute", controller)
	if action.is_empty() or not _activate(druid, action, controller):
		_fail("DRUID_WEAPONS: chaos transmutation was unavailable")
		return
	var changed_elements := controller.surface_state.get_readable_elements(druid.cell)
	changed_elements.erase(BattleSurfaceState.Element.FIRE)
	if changed_elements.is_empty():
		_fail("DRUID_WEAPONS: chaos transmutation did not add a new readable element")
		return
	var changed_element := changed_elements[0]
	var strike_context := {}
	var effect := weapon.passive_effects[0] as EquipmentEffect
	effect.on_before_strike(druid, weapon, weapon, druid.get_equipment_runtime_state(weapon), strike_context)
	if int(strike_context.get("surface_element", BattleSurfaceState.Element.NONE)) != changed_element:
		_fail("DRUID_WEAPONS: transmuted element was not attached to the strike context")


func _test_corrosion_lifecycle(druid: BattleUnitState, enemy: BattleUnitState, controller: BattleController) -> void:
	_set_weapon(druid, load("res://resources/items/druid_chaos_viper.tres") as EquipmentData)
	druid.set_druid_transformed(true)
	druid.set_hex_cell(Vector2i(2, 4), controller.map_data)
	enemy.set_hex_cell(Vector2i(3, 4), controller.map_data)
	enemy.hand.clear()
	enemy.draw_pile.clear()
	enemy.discard_pile.clear()
	enemy.curse_zone.clear()
	enemy.exiled_pile.clear()
	enemy.curse_wave = 0
	druid.notify_observed_unit_turn_start(enemy, {"controller": controller})
	if enemy.discard_pile.is_empty():
		_fail("DRUID_WEAPONS: viper did not inject corrosion at enemy turn start")
		return
	enemy.draw_pile.append(enemy.discard_pile.pop_back())
	var health_before := enemy.get_current_health()
	enemy.draw_cards(1, controller.rng, {"controller": controller, "reason": "diagnostic"})
	var pending: StatusEffect = null
	for status in enemy.statuses:
		if status != null and status.status_id.begins_with("druid_corrosion_pending"):
			pending = status
			break
	if pending == null:
		_fail("DRUID_WEAPONS: drawing corrosion did not create its pending trigger")
		return
	pending.on_turn_end(enemy, {"controller": controller})
	if enemy.exiled_pile.is_empty() or enemy.curse_wave != 1 or enemy.get_current_health() != health_before - 1:
		_fail("DRUID_WEAPONS: corrosion was not exiled with 1 life loss and 1 curse wave")


func _find_action(owner: BattleUnitState, action_id: String, controller: BattleController) -> Dictionary:
	for action in owner.get_equipment_actions({"controller": controller, "phase": "battle"}):
		if str(action.get("action_id", "")) == action_id:
			return action
	return {}


func _activate(owner: BattleUnitState, action: Dictionary, controller: BattleController) -> bool:
	var effect := action.get("effect") as EquipmentEffect
	return effect != null and effect.activate(owner, action.get("root") as EquipmentData, action.get("component") as EquipmentData, action.get("runtime") as EquipmentRuntimeState, {
		"controller": controller,
		"equipment_action_id": str(action.get("action_id", "")),
		"phase": "battle",
	})


func _set_weapon(owner: BattleUnitState, weapon: EquipmentData) -> void:
	owner.character_state.weapon_equipment = weapon
	owner.character_state.weapon_face = 0
	owner.equipment_runtime_states.clear()


func _find_druid(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != null and unit.is_druid():
			return unit
	return null


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
	print("ERROR: " + message)
