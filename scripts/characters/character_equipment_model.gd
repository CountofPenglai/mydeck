extends RefCounted
class_name CharacterEquipmentModel


static func refresh_enabled(state: CharacterState) -> void:
	if state == null:
		return
	state.main_hand_enabled = state.main_hand_weapon != null
	state.off_hand_enabled = state.off_hand_weapon != null
	if state.main_hand_weapon != null and state.main_hand_weapon.is_two_handed():
		state.off_hand_enabled = false


static func switch_weapon_from_inventory(state: CharacterState, preferred_weapon: WeaponData = null) -> Dictionary:
	if state == null:
		return {"success": false}

	var found := _find_inventory_weapon(state, preferred_weapon)
	var weapon: WeaponData = found.get("weapon")
	var stack_index := int(found.get("stack_index", -1))
	if weapon == null or stack_index < 0:
		return {"success": false}

	var slot := choose_switch_slot(state, weapon)
	if slot.is_empty():
		return {"success": false}

	var previous: WeaponData = null
	if slot == "main":
		previous = state.main_hand_weapon
		state.main_hand_weapon = weapon
	elif slot == "off":
		previous = state.off_hand_weapon
		state.off_hand_weapon = weapon
	else:
		return {"success": false}

	remove_inventory_item_at(state, stack_index)
	if previous != null:
		add_inventory_item(state, previous)

	refresh_enabled(state)
	return {
		"success": true,
		"slot": slot,
		"old_weapon": previous,
		"new_weapon": weapon,
		"main_hand_enabled": state.main_hand_enabled,
		"off_hand_enabled": state.off_hand_enabled,
	}


static func choose_switch_slot(state: CharacterState, weapon: WeaponData) -> String:
	if state == null or weapon == null:
		return ""
	if weapon.grip_type == WeaponData.GripType.TWO_HAND or weapon.grip_type == WeaponData.GripType.MAIN_HAND:
		return "main"
	if weapon.grip_type == WeaponData.GripType.OFF_HAND:
		return "off"
	if state.main_hand_weapon == null and weapon.can_equip_main_hand():
		return "main"
	if state.off_hand_weapon == null and weapon.can_equip_off_hand():
		return "off"
	if weapon.can_equip_main_hand():
		return "main"
	if weapon.can_equip_off_hand():
		return "off"
	return ""


static func remove_inventory_item_at(state: CharacterState, index: int) -> void:
	if state == null or index < 0 or index >= state.inventory.size():
		return
	var stack := state.inventory[index]
	if stack == null:
		return

	stack.count -= 1
	if stack.count <= 0:
		state.inventory.remove_at(index)


static func add_inventory_item(state: CharacterState, item: ItemData) -> void:
	if state == null or item == null:
		return

	for stack in state.inventory:
		if stack != null and stack.item_data == item and stack.count < item.max_stack:
			stack.count += 1
			return

	var new_stack := InventoryStack.new()
	new_stack.item_data = item
	new_stack.count = 1
	state.inventory.append(new_stack)


static func _find_inventory_weapon(state: CharacterState, preferred_weapon: WeaponData = null) -> Dictionary:
	for i in range(state.inventory.size()):
		var stack := state.inventory[i]
		if stack == null or not (stack.item_data is WeaponData) or stack.count <= 0:
			continue
		if preferred_weapon == null or stack.item_data == preferred_weapon:
			return {
				"weapon": stack.item_data,
				"stack_index": i,
			}

	return {
		"weapon": null,
		"stack_index": -1,
	}

