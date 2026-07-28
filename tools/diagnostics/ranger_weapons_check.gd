extends Node

const WEAPONS := {
	"ranger_dagger_crossbow": [4, 1, 3, 3],
	"ranger_marrow_origin_pair": [3, 1, 3, 3],
	"ranger_blood_volley_pair": [4, 1, 3, 3],
	"ranger_sea_dragon_pair": [2, 1, 7, 4],
	"ranger_leaf_hunter_pair": [3, 1, 4, 3],
	"ranger_sacred_tree_pair": [4, 2, 4, 4],
	"ranger_beloved_pair": [2, 1, 5, 4],
	"ranger_wind_hunter_pair": [4, 1, 4, 3],
}

var _exit_code := 0


func _ready() -> void:
	var controller := _build_controller()
	var ranger := _find_ranger(controller)
	var enemy := controller.enemy_units[0] if controller != null and not controller.enemy_units.is_empty() else null
	if controller == null or ranger == null or enemy == null:
		_fail("RANGER_WEAPONS: missing controller or units")
		get_tree().quit(_exit_code)
		return
	_prepare(controller, ranger, enemy)
	_test_resources_and_profiles(ranger)
	_test_runtime_snapshot(ranger)
	_test_wolf_cycle(controller, ranger, enemy)
	_test_marrow_collection(controller, ranger)
	_test_blood_marks(controller, ranger, enemy)
	_test_heavy_cooldown(controller, ranger, enemy)
	_test_leaf_ambush(controller, ranger)
	_test_sacred_tree(controller, ranger)
	_test_beloved_setup_and_ammo(controller, ranger, enemy)
	_test_wind_actions(controller, ranger, enemy)
	print("RANGER_WEAPONS: completed")
	get_tree().quit(_exit_code)


func _test_resources_and_profiles(ranger: BattleUnitState) -> void:
	for resource_name in WEAPONS:
		var weapon := load("res://resources/items/%s.tres" % resource_name) as EquipmentData
		if weapon == null or weapon.paired_component == null or weapon.paired_attack_mode != EquipmentData.PairedAttackMode.SELECT_ONE:
			_fail("RANGER_WEAPONS: invalid paired resource %s" % resource_name)
			continue
		var expected: Array = WEAPONS[resource_name]
		if [weapon.base_damage, weapon.attack_range, weapon.paired_component.base_damage, weapon.paired_component.attack_range] != expected:
			_fail("RANGER_WEAPONS: values differ for %s" % resource_name)
		_set_weapon(ranger, weapon)
		var melee := ranger.build_strike_profile_object("weapon")
		var ranged := ranger.build_strike_profile_object("paired")
		if melee.add_offhand or melee.primary_range_type != EquipmentData.WeaponRangeType.MELEE or ranged.primary_range_type != EquipmentData.WeaponRangeType.RANGED:
			_fail("RANGER_WEAPONS: SELECT_ONE profile incorrect for %s" % resource_name)


func _test_runtime_snapshot(ranger: BattleUnitState) -> void:
	var weapon := load("res://resources/items/ranger_blood_volley_pair.tres") as EquipmentData
	_set_weapon(ranger, weapon)
	var runtime := ranger.get_equipment_runtime_state(weapon)
	var second_instance := weapon.duplicate(true) as EquipmentData
	var second_runtime := ranger.get_equipment_runtime_state(second_instance)
	if runtime == second_runtime:
		_fail("RANGER_WEAPONS: duplicate equipment instances share runtime state")
	runtime.set_data("diagnostic", {3: [1, 2, 3]})
	var snapshot := ranger.snapshot_equipment_runtime_states()
	ranger.equipment_runtime_states.clear()
	ranger.restore_equipment_runtime_states(snapshot)
	var restored := ranger.get_equipment_runtime_state(weapon, false)
	if restored == null or restored.get_data("diagnostic", {}) != {3: [1, 2, 3]}:
		_fail("RANGER_WEAPONS: structured runtime snapshot failed")


func _test_wolf_cycle(controller: BattleController, ranger: BattleUnitState, enemy: BattleUnitState) -> void:
	var weapon := load("res://resources/items/ranger_dagger_crossbow.tres") as EquipmentData
	_set_weapon(ranger, weapon)
	_reset_enemy(enemy)
	controller.perform_strike(ranger, enemy, null, "wolf ranged", "paired")
	if ranger.get_next_move_distance_bonus({"controller": controller}) != 1:
		_fail("RANGER_WEAPONS: tracking bow move bonus missing")
	ranger.notify_movement_completed({"controller": controller, "forced": false})
	var profile := ranger.build_strike_profile_object("weapon", {"controller": controller, "target": enemy})
	if profile.primary_damage_bonus < ranger.get_agility() + 1:
		_fail("RANGER_WEAPONS: wolf knife melee bonus missing")
	controller.perform_strike(ranger, enemy, null, "wolf melee", "weapon")
	if ranger.get_equipment_runtime_state(weapon).get_flag("next_melee_bonus"):
		_fail("RANGER_WEAPONS: wolf knife bonus was not consumed")


func _test_marrow_collection(controller: BattleController, ranger: BattleUnitState) -> void:
	var weapon := load("res://resources/items/ranger_marrow_origin_pair.tres") as EquipmentData
	_set_weapon(ranger, weapon)
	ranger.ranger_state.element_inventory.clear()
	ranger.set_current_health(maxi(1, ranger.get_max_health() - 4))
	controller.surface_state.add_residue(
		ranger.cell,
		BattleSurfaceState.Element.FIRE,
		controller.battle_round
	)
	var before := ranger.get_current_health()
	var added := controller.collect_surface_elements(ranger, ranger.cell, "diagnostic", {"from_melee_strike": true})
	if added != 2 or ranger.get_current_health() - before != 2:
		_fail("RANGER_WEAPONS: marrow double collection or healing failed")


func _test_heavy_cooldown(controller: BattleController, ranger: BattleUnitState, enemy: BattleUnitState) -> void:
	var weapon := load("res://resources/items/ranger_sea_dragon_pair.tres") as EquipmentData
	_set_weapon(ranger, weapon)
	_reset_enemy(enemy)
	controller.perform_strike(ranger, enemy, null, "heavy", "paired")
	if ranger.can_use_attack_mode("paired"):
		_fail("RANGER_WEAPONS: heavy crossbow cooldown missing")
	controller.enter_ranger_stealth(ranger, "diagnostic reload")
	if not ranger.can_use_attack_mode("paired"):
		_fail("RANGER_WEAPONS: stealth did not clear heavy cooldown")


func _test_blood_marks(controller: BattleController, ranger: BattleUnitState, enemy: BattleUnitState) -> void:
	var weapon := load("res://resources/items/ranger_blood_volley_pair.tres") as EquipmentData
	_set_weapon(ranger, weapon)
	_reset_enemy(enemy)
	controller.perform_strike(ranger, enemy, null, "blood mark", "weapon")
	var runtime := ranger.get_equipment_runtime_state(weapon)
	var marks := runtime.get_data("ranger_marks", {}) as Dictionary
	if int(marks.get(enemy.unit_id, 0)) != 1:
		_fail("RANGER_WEAPONS: melee mark was not applied")
	ranger.ranger_state.combo_points = 1
	controller.gain_ranger_combo(ranger, 1)
	controller.resolve_effect_queue()
	marks = runtime.get_data("ranger_marks", {}) as Dictionary
	if int(marks.get(enemy.unit_id, 0)) != 0:
		_fail("RANGER_WEAPONS: volley did not consume mark")


func _test_leaf_ambush(controller: BattleController, ranger: BattleUnitState) -> void:
	var weapon := load("res://resources/items/ranger_leaf_hunter_pair.tres") as EquipmentData
	_set_weapon(ranger, weapon)
	controller.enter_ranger_stealth(ranger, "leaf diagnostic")
	if not is_equal_approx(controller.consume_ranger_stealth_for_attack(ranger, 0.0, {"equipment_slot": "weapon"}), 2.0):
		_fail("RANGER_WEAPONS: leaf melee ambush is not x2")
	controller.enter_ranger_stealth(ranger, "leaf override diagnostic")
	if not is_equal_approx(controller.consume_ranger_stealth_for_attack(ranger, 3.0, {"equipment_slot": "weapon"}), 3.0):
		_fail("RANGER_WEAPONS: explicit card ambush did not override leaf weapon")


func _test_sacred_tree(controller: BattleController, ranger: BattleUnitState) -> void:
	var weapon := load("res://resources/items/ranger_sacred_tree_pair.tres") as EquipmentData
	_set_weapon(ranger, weapon)
	ranger.ranger_state.element_inventory.clear()
	ranger.statuses.clear()
	ranger.notify_equipment_battle_started({"controller": controller})
	if ranger.ranger_state.get_element_total() != 2:
		_fail("RANGER_WEAPONS: sacred tree battle-start elements incorrect")
	ranger.notify_ranger_payload_completed({"controller": controller, "is_melee": true, "ingredients": [BattleSurfaceState.Element.FIRE, BattleSurfaceState.Element.WATER]})
	if not ranger.has_status("block"):
		_fail("RANGER_WEAPONS: sacred melee payload did not grant block")
	var before := ranger.ranger_state.get_element_total()
	ranger.notify_ranger_payload_completed({"controller": controller, "is_melee": false, "ingredients": [BattleSurfaceState.Element.FIRE, BattleSurfaceState.Element.WATER]})
	if ranger.ranger_state.get_element_total() != before + 1:
		_fail("RANGER_WEAPONS: sacred ranged payload did not refund ingredient")


func _test_beloved_setup_and_ammo(controller: BattleController, ranger: BattleUnitState, enemy: BattleUnitState) -> void:
	var weapon := load("res://resources/items/ranger_beloved_pair.tres") as EquipmentData
	_set_weapon(ranger, weapon)
	var context := {"controller": controller, "unit": ranger, "phase": "deployment"}
	for blend in [BattleSurfaceState.Element.STEAM, BattleSurfaceState.Element.LAVA, BattleSurfaceState.Element.STEAM]:
		var action_id := "ammo_%d" % blend
		var action := _find_action(ranger, context, action_id)
		if action.is_empty() or not _activate_direct(ranger, action, controller, action_id, "deployment"):
			_fail("RANGER_WEAPONS: failed to configure beloved ammo")
	if not ranger.is_equipment_setup_ready(context):
		_fail("RANGER_WEAPONS: beloved setup did not become ready")
	_reset_enemy(enemy)
	controller.perform_strike(ranger, enemy, null, "beloved", "paired")
	var runtime := ranger.get_equipment_runtime_state(weapon)
	if (runtime.get_data("preloaded_ammo", []) as Array).size() != 2:
		_fail("RANGER_WEAPONS: beloved did not consume front ammo")


func _test_wind_actions(controller: BattleController, ranger: BattleUnitState, enemy: BattleUnitState) -> void:
	var weapon := load("res://resources/items/ranger_wind_hunter_pair.tres") as EquipmentData
	_set_weapon(ranger, weapon)
	ranger.notify_equipment_battle_started({"controller": controller})
	ranger.notify_movement_completed({"controller": controller, "forced": false})
	var direction := BattleHexGrid.direction_index(ranger.cell, enemy.cell)
	var action_id := "wind_%d" % direction
	var context := {"controller": controller, "unit": ranger, "phase": "battle"}
	var action := _find_action(ranger, context, action_id)
	if action.is_empty() or not _activate_direct(ranger, action, controller, action_id, "battle"):
		_fail("RANGER_WEAPONS: wind direction action failed")
	elif controller.get_effective_attack_range_against(ranger, enemy, "paired") != 4:
		_fail("RANGER_WEAPONS: downwind range bonus failed")


func _find_action(owner: BattleUnitState, context: Dictionary, action_id: String) -> Dictionary:
	for action in owner.get_equipment_actions(context):
		if str(action.get("action_id", "")) == action_id:
			return action
	return {}


func _activate_direct(owner: BattleUnitState, action: Dictionary, controller: BattleController, action_id: String, phase_name: String) -> bool:
	var effect := action.get("effect") as EquipmentEffect
	return effect != null and effect.activate(owner, action.get("root") as EquipmentData, action.get("component") as EquipmentData, action.get("runtime") as EquipmentRuntimeState, {
		"controller": controller,
		"unit": owner,
		"equipment_action_id": action_id,
		"phase": phase_name,
	})


func _build_controller() -> BattleController:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	var controller := BattleController.new()
	controller.setup(scenario)
	return controller


func _find_ranger(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != null and unit.is_ranger():
			return unit
	return null


func _prepare(controller: BattleController, ranger: BattleUnitState, enemy: BattleUnitState) -> void:
	controller.phase = BattleController.Phase.BATTLE
	controller.current_unit = ranger
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	ranger.turn_serial = 1
	ranger.set_hex_cell(Vector2i(2, 4), controller.map_data)
	enemy.set_hex_cell(Vector2i(3, 4), controller.map_data)


func _set_weapon(owner: BattleUnitState, equipment: EquipmentData) -> void:
	owner.character_state.weapon_equipment = equipment
	owner.character_state.weapon_face = 0
	owner.equipment_runtime_states.clear()


func _reset_enemy(enemy: BattleUnitState) -> void:
	enemy.set_current_health(enemy.get_max_health())
	enemy.statuses.clear()


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
	print("ERROR: " + message)
