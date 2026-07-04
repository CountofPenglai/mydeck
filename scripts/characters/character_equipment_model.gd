extends RefCounted
class_name CharacterEquipmentModel


static func refresh_enabled(state: CharacterState) -> void:
	if state == null:
		return
	state.main_hand_enabled = state.main_hand_equipment != null
	state.off_hand_enabled = state.off_hand_equipment != null
	if state.main_hand_equipment != null and state.main_hand_equipment.is_two_handed():
		state.off_hand_enabled = false


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
	if slot == "main":
		previous = state.main_hand_equipment
		state.main_hand_equipment = equipment
		state.main_hand_face = 0
	elif slot == "off":
		previous = state.off_hand_equipment
		state.off_hand_equipment = equipment
		state.off_hand_face = 0
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
	if equipment.equip_category == EquipmentData.EquipCategory.TWO_HAND:
		return "main"
	if equipment.equip_category == EquipmentData.EquipCategory.OFF_HAND:
		return "off"
	if state.main_hand_equipment == null and equipment.can_equip_main_hand():
		return "main"
	if state.off_hand_equipment == null and equipment.can_equip_off_hand():
		return "off"
	if equipment.can_equip_main_hand():
		return "main"
	if equipment.can_equip_off_hand():
		return "off"
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
