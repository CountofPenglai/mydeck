extends Node

var _exit_code := 0


func _ready() -> void:
	_test_warrior_template_loadout_uses_reserve_weapon()
	_test_warrior_can_equip_and_unequip_reserve_weapon()
	_test_non_warrior_cannot_equip_or_unequip_reserve_weapon()
	_test_swap_moves_weapons_faces_and_instance_ids_without_inventory_changes()
	_test_swap_preserves_instance_id_key_presence()
	_test_swap_allows_empty_active_weapon()
	_test_swap_rejects_invalid_states_without_mutation()
	_test_controller_prepared_switch_contract_and_compatibility()
	_test_adventure_initialization_assigns_reserve_weapon_id()

	if _exit_code == 0:
		print("WARRIOR_RESERVE_WEAPON_DIAG: completed")
	get_tree().quit(_exit_code)


func _test_warrior_template_loadout_uses_reserve_weapon() -> void:
	var template := load("res://resources/characters/battle_warrior_state.tres") as CharacterState
	const ACTIVE_WEAPON_PATH := "res://resources/items/mountain_cleaver.tres"
	const RESERVE_WEAPON_PATH := "res://resources/items/ceremonial_sword_shield.tres"
	if template == null \
			or template.weapon_equipment == null \
			or template.weapon_equipment.resource_path != ACTIVE_WEAPON_PATH \
			or template.reserve_weapon_equipment == null \
			or template.reserve_weapon_equipment.resource_path != RESERVE_WEAPON_PATH \
			or template.reserve_weapon_face != 0:
		_fail("WARRIOR_RESERVE_WEAPON_DIAG: warrior template did not configure the active and reserve weapons")
		return
	for stack in template.inventory:
		if stack != null and stack.item_data != null and stack.item_data.resource_path == RESERVE_WEAPON_PATH:
			_fail("WARRIOR_RESERVE_WEAPON_DIAG: warrior template duplicated the reserve weapon in inventory")


func _test_warrior_can_equip_and_unequip_reserve_weapon() -> void:
	var state := _make_state(CardEnums.CardClass.WARRIOR)
	var reserve := _make_weapon("reserve")
	_add_inventory_weapon(state, reserve, "reserve_instance")

	var equipped := CharacterEquipmentModel.equip_inventory_item_at(state, 0, "reserve_weapon")
	if not bool(equipped.get("success", false)) \
			or state.get("reserve_weapon_equipment") != reserve \
			or int(state.get("reserve_weapon_face")) != 0 \
			or not state.inventory.is_empty() \
			or str(state.equipment_instance_ids.get("reserve_weapon", "")) != "reserve_instance":
		_fail("WARRIOR_RESERVE_WEAPON_DIAG: warrior reserve equip did not move the weapon into the reserve slot")
		return

	var unequipped := CharacterEquipmentModel.unequip_slot_to_inventory(state, "reserve_weapon")
	if not bool(unequipped.get("success", false)) \
			or state.get("reserve_weapon_equipment") != null \
			or state.inventory.size() != 1 \
			or state.inventory[0].item_data != reserve \
			or state.inventory[0].stack_id != "reserve_instance" \
			or state.equipment_instance_ids.has("reserve_weapon"):
		_fail("WARRIOR_RESERVE_WEAPON_DIAG: warrior reserve unequip did not return the original inventory stack")


func _test_non_warrior_cannot_equip_or_unequip_reserve_weapon() -> void:
	var state := _make_state(CardEnums.CardClass.MAGE)
	var reserve := _make_weapon("mage reserve")
	_add_inventory_weapon(state, reserve, "mage_reserve_instance")

	var equipped := CharacterEquipmentModel.equip_inventory_item_at(state, 0, "reserve_weapon")
	if bool(equipped.get("success", false)) \
			or state.get("reserve_weapon_equipment") != null \
			or state.inventory.size() != 1 \
			or state.inventory[0].item_data != reserve:
		_fail("WARRIOR_RESERVE_WEAPON_DIAG: non-warrior reserve equip was not rejected without mutation")

	state.set("reserve_weapon_equipment", reserve)
	state.set("reserve_weapon_face", 1)
	state.equipment_instance_ids["reserve_weapon"] = "mage_reserve_instance"
	var unequipped := CharacterEquipmentModel.unequip_slot_to_inventory(state, "reserve_weapon")
	if bool(unequipped.get("success", false)) \
			or state.get("reserve_weapon_equipment") != reserve \
			or int(state.get("reserve_weapon_face")) != 1 \
			or state.inventory.size() != 1 \
			or str(state.equipment_instance_ids.get("reserve_weapon", "")) != "mage_reserve_instance":
		_fail("WARRIOR_RESERVE_WEAPON_DIAG: non-warrior reserve unequip was not rejected without mutation")


func _test_swap_moves_weapons_faces_and_instance_ids_without_inventory_changes() -> void:
	var state := _make_state(CardEnums.CardClass.WARRIOR)
	var active := _make_weapon("active")
	var reserve := _make_weapon("reserve")
	var inventory_weapon := _make_weapon("inventory")
	state.weapon_equipment = active
	state.weapon_face = 1
	state.set("reserve_weapon_equipment", reserve)
	state.set("reserve_weapon_face", 0)
	state.equipment_instance_ids["weapon"] = "active_instance"
	state.equipment_instance_ids["reserve_weapon"] = "reserve_instance"
	_add_inventory_weapon(state, inventory_weapon, "inventory_instance")

	var swapped := _swap(state)
	if not bool(swapped.get("success", false)) \
			or str(swapped.get("slot", "")) != "weapon" \
			or swapped.get("old_equipment") != active \
			or int(swapped.get("old_face", -1)) != 1 \
			or str(swapped.get("old_instance_id", "")) != "active_instance" \
			or swapped.get("new_equipment") != reserve \
			or int(swapped.get("new_face", -1)) != 0 \
			or str(swapped.get("new_instance_id", "")) != "reserve_instance" \
			or state.weapon_equipment != reserve \
			or state.weapon_face != 0 \
			or state.get("reserve_weapon_equipment") != active \
			or int(state.get("reserve_weapon_face")) != 1 \
			or str(state.equipment_instance_ids.get("weapon", "")) != "reserve_instance" \
			or str(state.equipment_instance_ids.get("reserve_weapon", "")) != "active_instance" \
			or state.inventory.size() != 1 \
			or state.inventory[0].item_data != inventory_weapon \
			or state.inventory[0].stack_id != "inventory_instance":
		_fail("WARRIOR_RESERVE_WEAPON_DIAG: swap did not exchange slot state while preserving inventory")


func _test_swap_preserves_instance_id_key_presence() -> void:
	var cases := [
		{"name": "both", "has_weapon_id": true, "has_reserve_id": true},
		{"name": "active_only", "has_weapon_id": true, "has_reserve_id": false},
		{"name": "reserve_only", "has_weapon_id": false, "has_reserve_id": true},
		{"name": "neither", "has_weapon_id": false, "has_reserve_id": false},
	]
	for case in cases:
		var state := _make_state(CardEnums.CardClass.WARRIOR)
		state.weapon_equipment = _make_weapon("active_%s" % str(case.name))
		state.set("reserve_weapon_equipment", _make_weapon("reserve_%s" % str(case.name)))
		if bool(case.has_weapon_id):
			state.equipment_instance_ids["weapon"] = "active_instance"
		if bool(case.has_reserve_id):
			state.equipment_instance_ids["reserve_weapon"] = "reserve_instance"

		var swapped := _swap(state)
		if not bool(swapped.get("success", false)) \
				or state.equipment_instance_ids.has("weapon") != bool(case.has_reserve_id) \
				or state.equipment_instance_ids.has("reserve_weapon") != bool(case.has_weapon_id):
			_fail("WARRIOR_RESERVE_WEAPON_DIAG: swap did not preserve instance ID key presence for %s" % str(case.name))
			continue
		if state.equipment_instance_ids.has("weapon") \
				and str(state.equipment_instance_ids.get("weapon", "")) != "reserve_instance":
			_fail("WARRIOR_RESERVE_WEAPON_DIAG: swap did not move the reserve instance ID for %s" % str(case.name))
		if state.equipment_instance_ids.has("reserve_weapon") \
				and str(state.equipment_instance_ids.get("reserve_weapon", "")) != "active_instance":
			_fail("WARRIOR_RESERVE_WEAPON_DIAG: swap did not move the active instance ID for %s" % str(case.name))


func _test_swap_allows_empty_active_weapon() -> void:
	var state := _make_state(CardEnums.CardClass.WARRIOR)
	var reserve := _make_weapon("reserve")
	state.set("reserve_weapon_equipment", reserve)
	state.set("reserve_weapon_face", 1)
	state.equipment_instance_ids["reserve_weapon"] = "reserve_instance"

	var swapped := _swap(state)
	if not bool(swapped.get("success", false)) \
			or state.weapon_equipment != reserve \
			or state.weapon_face != 1 \
			or state.get("reserve_weapon_equipment") != null \
			or int(state.get("reserve_weapon_face")) != 0 \
			or str(state.equipment_instance_ids.get("weapon", "")) != "reserve_instance" \
			or state.equipment_instance_ids.has("reserve_weapon"):
		_fail("WARRIOR_RESERVE_WEAPON_DIAG: swap did not promote a reserve weapon into an empty active slot")


func _test_swap_rejects_invalid_states_without_mutation() -> void:
	var null_swap := _swap(null)
	if bool(null_swap.get("success", false)):
		_fail("WARRIOR_RESERVE_WEAPON_DIAG: null state swap was not rejected")

	var non_warrior := _make_state(CardEnums.CardClass.RANGER)
	var active := _make_weapon("active")
	var reserve := _make_weapon("reserve")
	non_warrior.weapon_equipment = active
	non_warrior.weapon_face = 1
	non_warrior.set("reserve_weapon_equipment", reserve)
	non_warrior.set("reserve_weapon_face", 0)
	non_warrior.equipment_instance_ids["weapon"] = "active_instance"
	non_warrior.equipment_instance_ids["reserve_weapon"] = "reserve_instance"
	var non_warrior_swap := _swap(non_warrior)
	if bool(non_warrior_swap.get("success", false)) \
			or non_warrior.weapon_equipment != active \
			or non_warrior.weapon_face != 1 \
			or non_warrior.get("reserve_weapon_equipment") != reserve \
			or int(non_warrior.get("reserve_weapon_face")) != 0 \
			or str(non_warrior.equipment_instance_ids.get("weapon", "")) != "active_instance" \
			or str(non_warrior.equipment_instance_ids.get("reserve_weapon", "")) != "reserve_instance":
		_fail("WARRIOR_RESERVE_WEAPON_DIAG: non-warrior swap was not rejected without mutation")

	var empty_reserve := _make_state(CardEnums.CardClass.WARRIOR)
	empty_reserve.weapon_equipment = active
	empty_reserve.weapon_face = 1
	empty_reserve.equipment_instance_ids["weapon"] = "active_instance"
	var empty_swap := _swap(empty_reserve)
	if bool(empty_swap.get("success", false)) \
			or empty_reserve.weapon_equipment != active \
			or empty_reserve.weapon_face != 1 \
			or str(empty_reserve.equipment_instance_ids.get("weapon", "")) != "active_instance" \
			or empty_reserve.equipment_instance_ids.has("reserve_weapon"):
		_fail("WARRIOR_RESERVE_WEAPON_DIAG: empty reserve swap was not rejected without mutation")


func _test_controller_prepared_switch_contract_and_compatibility() -> void:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	var controller := BattleController.new()
	controller.setup(scenario)
	var warrior: BattleUnitState
	for unit in controller.player_units:
		if unit != null and unit.get_character_class() == CardEnums.CardClass.WARRIOR:
			warrior = unit
			break
	if warrior == null or warrior.character_state == null:
		_fail("WARRIOR_RESERVE_WEAPON_DIAG: controller diagnostic warrior missing")
		return

	var active := _make_weapon("controller active")
	var reserve := _make_weapon("controller reserve")
	var inventory_weapon := _make_weapon("controller inventory sentinel")
	warrior.character_state.weapon_equipment = active
	warrior.character_state.weapon_face = 1
	warrior.character_state.reserve_weapon_equipment = reserve
	warrior.character_state.reserve_weapon_face = 0
	warrior.character_state.equipment_instance_ids = {
		"weapon": "controller_active_id",
		"reserve_weapon": "controller_reserve_id",
		"unrelated": {"nested": [1, 2, 3]},
	}
	warrior.character_state.inventory.clear()
	_add_inventory_weapon(warrior.character_state, inventory_weapon, "inventory_sentinel_id")
	var backpack_before := _inventory_bytes(warrior.character_state)

	if not controller.has_method("can_switch_prepared_weapon") \
			or not bool(controller.call("can_switch_prepared_weapon", warrior)) \
			or not controller.can_switch_weapon_from_inventory(warrior):
		_fail("WARRIOR_RESERVE_WEAPON_DIAG: prepared and compatibility availability ignored the reserve slot")
		return
	var switched := controller.call("switch_prepared_weapon", warrior) as Dictionary
	if not _is_compatible_switch_result(
		switched,
		active,
		1,
		"controller_active_id",
		reserve,
		0,
		"controller_reserve_id"
	) \
			or warrior.character_state.weapon_equipment != reserve \
			or warrior.character_state.reserve_weapon_equipment != active \
			or _inventory_bytes(warrior.character_state) != backpack_before:
		_fail("WARRIOR_RESERVE_WEAPON_DIAG: prepared controller switch broke the result contract or backpack isolation")
		return

	var switched_back := controller.switch_weapon_from_inventory(warrior)
	if not _is_compatible_switch_result(
		switched_back,
		reserve,
		0,
		"controller_reserve_id",
		active,
		1,
		"controller_active_id"
	) \
			or warrior.character_state.weapon_equipment != active \
			or warrior.character_state.reserve_weapon_equipment != reserve \
			or _inventory_bytes(warrior.character_state) != backpack_before:
		_fail("WARRIOR_RESERVE_WEAPON_DIAG: warrior inventory compatibility API did not delegate to prepared switching")


func _is_compatible_switch_result(
	result: Dictionary,
	old_equipment: EquipmentData,
	old_face: int,
	old_instance_id: String,
	new_equipment: EquipmentData,
	new_face: int,
	new_instance_id: String
) -> bool:
	return bool(result.get("success", false)) \
		and str(result.get("slot", "")) == CharacterEquipmentModel.SLOT_WEAPON \
		and result.get("old_equipment") == old_equipment \
		and int(result.get("old_face", -1)) == old_face \
		and str(result.get("old_instance_id", "")) == old_instance_id \
		and result.get("new_equipment") == new_equipment \
		and int(result.get("new_face", -1)) == new_face \
		and str(result.get("new_instance_id", "")) == new_instance_id


func _inventory_bytes(state: CharacterState) -> PackedByteArray:
	var payload: Array[Dictionary] = []
	for stack in state.inventory:
		payload.append({
			"stack_object_id": stack.get_instance_id() if stack != null else 0,
			"item_object_id": stack.item_data.get_instance_id() if stack != null and stack.item_data != null else 0,
			"item_path": stack.item_data.resource_path if stack != null and stack.item_data != null else "",
			"count": stack.count if stack != null else 0,
			"stack_id": stack.stack_id if stack != null else "",
		})
	return var_to_bytes(payload)


func _test_adventure_initialization_assigns_reserve_weapon_id() -> void:
	var state := _make_state(CardEnums.CardClass.WARRIOR)
	state.ensure_adventure_instance_ids(7)
	if str(state.equipment_instance_ids.get("reserve_weapon", "")).is_empty():
		_fail("WARRIOR_RESERVE_WEAPON_DIAG: adventure initialization did not assign a reserve weapon instance id")


func _swap(state: CharacterState) -> Dictionary:
	var model := CharacterEquipmentModel.new()
	if not model.has_method("swap_active_and_reserve_weapons"):
		return {"success": false}
	return model.call("swap_active_and_reserve_weapons", state) as Dictionary


func _make_state(character_class: int) -> CharacterState:
	var state := CharacterState.new()
	var character_data := CharacterData.new()
	character_data.character_class = character_class
	state.character_data = character_data
	return state


func _make_weapon(item_name: String) -> EquipmentData:
	var weapon := EquipmentData.new()
	weapon.item_name = item_name
	weapon.equip_slot = EquipmentData.EquipSlot.WEAPON
	return weapon


func _add_inventory_weapon(state: CharacterState, weapon: EquipmentData, stack_id: String) -> void:
	var stack := InventoryStack.new()
	stack.item_data = weapon
	stack.count = 1
	stack.stack_id = stack_id
	state.inventory.append(stack)


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
	print("ERROR: " + message)
