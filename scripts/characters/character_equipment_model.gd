extends RefCounted
class_name CharacterEquipmentModel

const SLOT_WEAPON := "weapon"
const SLOT_ARMOR := "armor"
const SLOT_ACCESSORY_1 := "accessory_1"
const SLOT_ACCESSORY_2 := "accessory_2"
const VALID_SLOTS := [SLOT_WEAPON, SLOT_ARMOR, SLOT_ACCESSORY_1, SLOT_ACCESSORY_2]


static func switch_equipment_from_inventory(state: CharacterState, preferred_equipment: EquipmentData = null) -> Dictionary:
	if state == null:
		return _result(false, "角色状态不存在。")

	var preview := preview_equipment_switch(state, preferred_equipment)
	if not bool(preview.get("success", false)):
		return preview
	return equip_inventory_item_at(state, int(preview.get("stack_index", -1)), str(preview.get("slot", "")))


static func equip_inventory_stack_to_slot(state: CharacterState, stack_id: String, slot: String) -> Dictionary:
	if state == null or stack_id.is_empty():
		return _result(false, "背包物品不存在。")
	for index in range(state.inventory.size()):
		var stack := state.inventory[index]
		if stack != null and stack.stack_id == stack_id:
			return equip_inventory_item_at(state, index, slot)
	return _result(false, "背包物品不存在。")


static func equip_inventory_item_at(state: CharacterState, stack_index: int, slot: String) -> Dictionary:
	if state == null or stack_index < 0 or stack_index >= state.inventory.size():
		return _result(false, "背包物品不存在。")
	if not VALID_SLOTS.has(slot):
		return _result(false, "装备槽位无效。")

	var source_stack := state.inventory[stack_index]
	var equipment := source_stack.item_data as EquipmentData if source_stack != null else null
	if source_stack == null or source_stack.count <= 0 or equipment == null:
		return _result(false, "该物品不能装备。")
	if not _equipment_fits_slot(equipment, slot):
		return _result(false, "%s不能装备到该槽位。" % equipment.item_name)
	if state.character_data != null and not equipment.is_available_to_class(state.character_data.character_class):
		return _result(false, "%s无法使用这件装备。" % state.get_character_name())

	var previous := _get_slot_equipment(state, slot)
	var previous_face := state.weapon_face if slot == SLOT_WEAPON else 0
	var previous_id := str(state.equipment_instance_ids.get(slot, ""))
	if previous != null and source_stack.count > 1 and not _can_add_inventory_item(state, previous, previous_id):
		return _result(false, "背包已满，无法收起当前装备。")

	var incoming_id := _take_inventory_item_at(state, stack_index)
	if previous != null and not add_inventory_item(state, previous, previous_id):
		return _result(false, "背包已满，无法收起当前装备。")
	_set_slot_equipment(state, slot, equipment)
	state.equipment_instance_ids[slot] = incoming_id

	return {
		"success": true,
		"message": "已装备%s。" % equipment.item_name,
		"slot": slot,
		"old_equipment": previous,
		"old_face": previous_face,
		"new_equipment": equipment,
		"new_face": state.weapon_face if slot == SLOT_WEAPON else 0,
		"old_instance_id": previous_id,
		"new_instance_id": incoming_id,
	}


static func unequip_slot_to_inventory(state: CharacterState, slot: String) -> Dictionary:
	if state == null or not VALID_SLOTS.has(slot):
		return _result(false, "装备槽位无效。")
	var equipment := _get_slot_equipment(state, slot)
	if equipment == null:
		return _result(false, "该槽位没有装备。")
	var instance_id := str(state.equipment_instance_ids.get(slot, ""))
	if not _can_add_inventory_item(state, equipment, instance_id):
		return _result(false, "背包已满，无法卸下装备。")
	if not add_inventory_item(state, equipment, instance_id):
		return _result(false, "背包已满，无法卸下装备。")
	_set_slot_equipment(state, slot, null)
	state.equipment_instance_ids.erase(slot)
	return {
		"success": true,
		"message": "已卸下%s。" % equipment.item_name,
		"slot": slot,
		"old_equipment": equipment,
		"old_instance_id": instance_id,
	}


static func sort_inventory(state: CharacterState) -> bool:
	if state == null:
		return false
	state.inventory.sort_custom(_inventory_stack_before)
	return true


static func transfer_inventory_stack(
	source: CharacterState,
	target: CharacterState,
	stack_id: String
) -> Dictionary:
	if source == null or target == null or source == target:
		return _result(false, "请选择另一名接收者。")
	if stack_id.is_empty():
		return _result(false, "背包物品不存在。")
	if target.inventory.size() >= CharacterState.INVENTORY_LIMIT:
		return _result(false, "%s 的背包已满。" % target.get_character_name())

	for index in range(source.inventory.size()):
		var stack := source.inventory[index]
		if stack == null or stack.stack_id != stack_id or stack.item_data == null:
			continue
		if not (stack.item_data is EquipmentData):
			return _result(false, "目前只能转交装备。")
		source.inventory.remove_at(index)
		target.inventory.append(stack)
		if source.equipment_adventure_modifiers.has(stack_id):
			target.equipment_adventure_modifiers[stack_id] = \
				source.equipment_adventure_modifiers.get(stack_id, {}).duplicate(true)
			source.equipment_adventure_modifiers.erase(stack_id)
		return _result(true, "%s 已转交给 %s。" % [
			stack.item_data.item_name,
			target.get_character_name(),
		])
	return _result(false, "背包物品不存在。")


static func preview_equipment_switch(state: CharacterState, preferred_equipment: EquipmentData = null) -> Dictionary:
	if state == null:
		return _result(false, "角色状态不存在。")
	var found := _find_inventory_equipment(state, preferred_equipment)
	var equipment := found.get("equipment") as EquipmentData
	var stack_index := int(found.get("stack_index", -1))
	var slot := choose_switch_slot(state, equipment)
	if equipment == null or stack_index < 0 or slot.is_empty():
		return _result(false, "没有可切换的装备。")
	if state.character_data != null and not equipment.is_available_to_class(state.character_data.character_class):
		return _result(false, "%s无法使用这件装备。" % state.get_character_name())
	var previous := _get_slot_equipment(state, slot)
	var source_stack := state.inventory[stack_index]
	var previous_id := str(state.equipment_instance_ids.get(slot, ""))
	if previous != null and source_stack.count > 1 and not _can_add_inventory_item(state, previous, previous_id):
		return _result(false, "背包已满，无法收起当前装备。")
	return {
		"success": true,
		"equipment": equipment,
		"stack_index": stack_index,
		"slot": slot,
		"old_equipment": previous,
		"old_face": state.weapon_face if slot == SLOT_WEAPON else 0,
	}


static func choose_switch_slot(state: CharacterState, equipment: EquipmentData) -> String:
	if state == null or equipment == null:
		return ""
	if equipment.is_weapon():
		return SLOT_WEAPON
	if equipment.is_armor():
		return SLOT_ARMOR
	if equipment.is_accessory():
		if state.accessory_equipment_1 == null:
			return SLOT_ACCESSORY_1
		if state.accessory_equipment_2 == null:
			return SLOT_ACCESSORY_2
		return SLOT_ACCESSORY_1
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


static func add_inventory_item(state: CharacterState, item: ItemData, instance_id: String = "") -> bool:
	if state == null or item == null:
		return false

	if instance_id.is_empty():
		for stack in state.inventory:
			if stack != null and stack.item_data == item and stack.count < item.max_stack:
				stack.count += 1
				return true
	if state.inventory.size() >= CharacterState.INVENTORY_LIMIT:
		return false

	var new_stack := InventoryStack.new()
	new_stack.item_data = item
	new_stack.count = 1
	new_stack.stack_id = instance_id
	if new_stack.stack_id.is_empty():
		new_stack.stack_id = _new_runtime_item_id(state, new_stack)
	state.inventory.append(new_stack)
	return true


static func _take_inventory_item_at(state: CharacterState, index: int) -> String:
	var stack := state.inventory[index]
	var instance_id := stack.stack_id
	if instance_id.is_empty():
		instance_id = _new_runtime_item_id(state, stack)
	if stack.count <= 1:
		state.inventory.remove_at(index)
	else:
		stack.count -= 1
		instance_id = "%s_split_%d" % [instance_id, Time.get_ticks_usec()]
	return instance_id


static func _can_add_inventory_item(state: CharacterState, item: ItemData, instance_id: String = "") -> bool:
	if state == null or item == null:
		return false
	if instance_id.is_empty():
		for stack in state.inventory:
			if stack != null and stack.item_data == item and stack.count < item.max_stack:
				return true
	return state.inventory.size() < CharacterState.INVENTORY_LIMIT


static func _find_inventory_equipment(state: CharacterState, preferred_equipment: EquipmentData = null) -> Dictionary:
	for index in range(state.inventory.size()):
		var stack := state.inventory[index]
		if stack == null or not (stack.item_data is EquipmentData) or stack.count <= 0:
			continue
		if preferred_equipment == null or stack.item_data == preferred_equipment:
			return {"equipment": stack.item_data, "stack_index": index}
	return {"equipment": null, "stack_index": -1}


static func _equipment_fits_slot(equipment: EquipmentData, slot: String) -> bool:
	match slot:
		SLOT_WEAPON:
			return equipment.is_weapon()
		SLOT_ARMOR:
			return equipment.is_armor()
		SLOT_ACCESSORY_1, SLOT_ACCESSORY_2:
			return equipment.is_accessory()
	return false


static func _get_slot_equipment(state: CharacterState, slot: String) -> EquipmentData:
	match slot:
		SLOT_WEAPON:
			return state.weapon_equipment
		SLOT_ARMOR:
			return state.armor_equipment
		SLOT_ACCESSORY_1:
			return state.accessory_equipment_1
		SLOT_ACCESSORY_2:
			return state.accessory_equipment_2
	return null


static func _set_slot_equipment(state: CharacterState, slot: String, equipment: EquipmentData) -> void:
	match slot:
		SLOT_WEAPON:
			state.weapon_equipment = equipment
			state.weapon_face = 0
		SLOT_ARMOR:
			state.armor_equipment = equipment
		SLOT_ACCESSORY_1:
			state.accessory_equipment_1 = equipment
		SLOT_ACCESSORY_2:
			state.accessory_equipment_2 = equipment


static func _new_runtime_item_id(state: CharacterState, stack: InventoryStack) -> String:
	var owner_id := state.adventure_character_id if not state.adventure_character_id.is_empty() else "combatant"
	return "%s_item_runtime_%d" % [owner_id, stack.get_instance_id()]


static func _inventory_stack_before(left: InventoryStack, right: InventoryStack) -> bool:
	if left == null:
		return false
	if right == null:
		return true
	var left_equipment := left.item_data as EquipmentData
	var right_equipment := right.item_data as EquipmentData
	var left_group := left_equipment.equip_slot if left_equipment != null else 99
	var right_group := right_equipment.equip_slot if right_equipment != null else 99
	if left_group != right_group:
		return left_group < right_group
	var left_rarity := left_equipment.rarity if left_equipment != null else 99
	var right_rarity := right_equipment.rarity if right_equipment != null else 99
	if left_rarity != right_rarity:
		return left_rarity < right_rarity
	var left_name := left.item_data.item_name if left.item_data != null else ""
	var right_name := right.item_data.item_name if right.item_data != null else ""
	return left_name.naturalnocasecmp_to(right_name) < 0


static func _result(success: bool, message: String) -> Dictionary:
	return {"success": success, "message": message}
