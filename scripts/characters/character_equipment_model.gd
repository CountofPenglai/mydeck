extends RefCounted
class_name CharacterEquipmentModel


static func refresh_enabled(state: CharacterState) -> void:
	if state == null:
		return
	state.main_hand_enabled = state.weapon_equipment != null
	state.off_hand_enabled = state.weapon_equipment != null and state.weapon_equipment.has_back_face()


static func switch_equipment_from_inventory(state: CharacterState, preferred_equipment: EquipmentData = null) -> Dictionary:
	if state == null:
		return {"success": false}

	var found := _find_inventory_equipment(state, preferred_equipment)
	var equipment: EquipmentData = found.get("equipment")
	var stack_index := int(found.get("stack_index", -1))
	if equipment == null or stack_index < 0:
		return {"success": false}

	var slot := choose_switch_slot(state, equipment)
	if slot.is_empty():
		return {"success": false}

	var previous: EquipmentData = null
	if slot == "weapon":
		previous = state.weapon_equipment
		state.weapon_equipment = equipment
		state.weapon_face = 0
	elif slot == "armor":
		previous = state.armor_equipment
		state.armor_equipment = equipment
	elif slot == "accessory_1":
		previous = state.accessory_equipment_1
		state.accessory_equipment_1 = equipment
	elif slot == "accessory_2":
		previous = state.accessory_equipment_2
		state.accessory_equipment_2 = equipment
	else:
		return {"success": false}

	remove_inventory_item_at(state, stack_index)
	if previous != null:
		add_inventory_item(state, previous)

	refresh_enabled(state)
	return {
		"success": true,
		"slot": slot,
		"old_equipment": previous,
		"new_equipment": equipment,
		"main_hand_enabled": state.main_hand_enabled,
		"off_hand_enabled": state.off_hand_enabled,
	}


static func choose_switch_slot(state: CharacterState, equipment: EquipmentData) -> String:
	if state == null or equipment == null:
		return ""
	if equipment.is_weapon():
		return "weapon"
	if equipment.is_armor():
		return "armor"
	if equipment.is_accessory():
		if state.accessory_equipment_1 == null:
			return "accessory_1"
		if state.accessory_equipment_2 == null:
			return "accessory_2"
		return "accessory_1"
	return ""


static func remove_inventory_item_at(state: CharacterState, index: int) -> void:
	if state == null or index < 0 or index >= state.inventory.size():
		return
	var stack: InventoryStack = state.inventory[index]
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
	if state.inventory.size() < CharacterState.INVENTORY_LIMIT:
		state.inventory.append(new_stack)


static func _find_inventory_equipment(state: CharacterState, preferred_equipment: EquipmentData = null) -> Dictionary:
	for i in range(state.inventory.size()):
		var stack: InventoryStack = state.inventory[i]
		if stack == null or not (stack.item_data is EquipmentData) or stack.count <= 0:
			continue
		if preferred_equipment == null or stack.item_data == preferred_equipment:
			return {
				"equipment": stack.item_data,
				"stack_index": i,
			}

	return {
		"equipment": null,
		"stack_index": -1,
	}
