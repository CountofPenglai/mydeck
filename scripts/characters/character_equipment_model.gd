extends RefCounted
class_name CharacterEquipmentModel


static func switch_equipment_from_inventory(state: CharacterState, preferred_equipment: EquipmentData = null) -> Dictionary:
	if state == null:
		return {"success": false}

	var found := preview_equipment_switch(state, preferred_equipment)
	var equipment: EquipmentData = found.get("equipment")
	var stack_index := int(found.get("stack_index", -1))
	var slot := str(found.get("slot", ""))
	if equipment == null or stack_index < 0 or slot.is_empty():
		return {"success": false}

	var previous: EquipmentData = null
	var previous_face := 0
	if slot == "weapon":
		previous = state.weapon_equipment
		previous_face = state.weapon_face
	elif slot == "armor":
		previous = state.armor_equipment
	elif slot == "accessory_1":
		previous = state.accessory_equipment_1
	elif slot == "accessory_2":
		previous = state.accessory_equipment_2
	else:
		return {"success": false}

	var source_stack: InventoryStack = state.inventory[stack_index]
	if previous != null and source_stack.count > 1 and not _can_add_inventory_item(state, previous):
		return {"success": false}

	if slot == "weapon":
		state.weapon_equipment = equipment
		state.weapon_face = 0
	elif slot == "armor":
		state.armor_equipment = equipment
	elif slot == "accessory_1":
		state.accessory_equipment_1 = equipment
	elif slot == "accessory_2":
		state.accessory_equipment_2 = equipment

	remove_inventory_item_at(state, stack_index)
	if previous != null:
		add_inventory_item(state, previous)

	return {
		"success": true,
		"slot": slot,
		"old_equipment": previous,
		"old_face": previous_face,
		"new_equipment": equipment,
		"new_face": state.weapon_face if slot == "weapon" else 0,
	}


static func preview_equipment_switch(state: CharacterState, preferred_equipment: EquipmentData = null) -> Dictionary:
	if state == null:
		return {"success": false}
	var found := _find_inventory_equipment(state, preferred_equipment)
	var equipment := found.get("equipment") as EquipmentData
	var stack_index := int(found.get("stack_index", -1))
	var slot := choose_switch_slot(state, equipment)
	if equipment == null or stack_index < 0 or slot.is_empty():
		return {"success": false}
	var previous: EquipmentData = null
	var previous_face := 0
	match slot:
		"weapon":
			previous = state.weapon_equipment
			previous_face = state.weapon_face
		"armor": previous = state.armor_equipment
		"accessory_1": previous = state.accessory_equipment_1
		"accessory_2": previous = state.accessory_equipment_2
	return {
		"success": true,
		"equipment": equipment,
		"stack_index": stack_index,
		"slot": slot,
		"old_equipment": previous,
		"old_face": previous_face,
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


static func _can_add_inventory_item(state: CharacterState, item: ItemData) -> bool:
	if state == null or item == null:
		return false
	for stack in state.inventory:
		if stack != null and stack.item_data == item and stack.count < item.max_stack:
			return true
	return state.inventory.size() < CharacterState.INVENTORY_LIMIT


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
