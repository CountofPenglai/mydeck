extends Resource
class_name CharacterState

@export var character_data: CharacterData
@export var current_health: int = -1
@export var deck: Array[CardStack] = []
@export var main_hand_weapon: WeaponData
@export var off_hand_weapon: WeaponData
@export var inventory: Array[InventoryStack] = []
@export var class_resources: Array[ResourcePoolState] = []
@export var extra_ap_bonus: int = 0
var main_hand_enabled: bool = true
var off_hand_enabled: bool = true
const UNARMED_POWER := 1

func ensure_initialized() -> void:
	if character_data == null:
		return

	_refresh_equipment_enabled()

	if current_health < 0:
		current_health = get_max_health()

	if class_resources.is_empty():
		reset_class_resources()


func reset_class_resources() -> void:
	class_resources.clear()

	if character_data == null:
		return

	for pool_data in character_data.get_resource_pool_definitions():
		var pool_state := ResourcePoolState.new()
		pool_state.setup(pool_data)
		class_resources.append(pool_state)


func get_character_name() -> String:
	if character_data == null:
		return "未绑定角色"

	return character_data.character_name


func get_class_label() -> String:
	if character_data == null:
		return "-"

	return character_data.get_class_label()


func get_max_health() -> int:
	if character_data == null:
		return 0

	return character_data.base_max_health


func get_attack() -> int:
	var profile := build_strike_profile()
	return int(profile.get("primary_power", 0)) + int(profile.get("damage_bonus", 0))


func get_strength() -> int:
	if character_data == null:
		return 0

	return character_data.base_strength


func get_damage_bonus(context: Dictionary = {}) -> int:
	var bonus := get_strength()
	var unit = context.get("unit")
	if unit != null and unit.has_method("get_status_damage_bonus"):
		bonus += unit.get_status_damage_bonus(context)

	return bonus


func get_agility() -> int:
	if character_data == null:
		return 0

	return character_data.base_agility


func get_speed() -> int:
	return get_agility()


func get_collision_radius() -> float:
	if character_data == null:
		return 0.0

	return character_data.collision_radius


func get_attack_range(weapon_slot: String = "") -> float:
	if character_data == null:
		return 0.0

	var weapon := get_weapon_for_attack_slot(_resolve_primary_attack_slot(weapon_slot))
	if weapon != null:
		return weapon.attack_range

	return character_data.base_attack_range


func has_equipment_tag(tag: String) -> bool:
	if main_hand_weapon != null and main_hand_enabled and main_hand_weapon.has_tag(tag):
		return true
	if off_hand_weapon != null and off_hand_enabled:
		return off_hand_weapon.has_tag(tag)

	return false


func needs_weapon_choice() -> bool:
	if main_hand_weapon == null or off_hand_weapon == null:
		return false
	if not main_hand_enabled or not off_hand_enabled:
		return false

	return main_hand_weapon.weapon_type != off_hand_weapon.weapon_type


func get_attack_weapon_options() -> Array:
	var options := []
	if main_hand_weapon != null and main_hand_enabled:
		options.append(_make_weapon_option("main", main_hand_weapon))
	if off_hand_weapon != null and off_hand_enabled and needs_weapon_choice():
		options.append(_make_weapon_option("off", off_hand_weapon))
	if options.is_empty():
		options.append({
			"slot": "unarmed",
			"label": "空手",
			"weapon": null,
			"power": UNARMED_POWER,
			"range": character_data.base_attack_range if character_data != null else 0.0,
			"weapon_type": WeaponData.WeaponType.MELEE,
		})

	return options


func build_strike_profile(weapon_slot: String = "", context: Dictionary = {}) -> Dictionary:
	var primary_slot := _resolve_primary_attack_slot(weapon_slot)
	var primary_weapon := get_weapon_for_attack_slot(primary_slot)
	var damage_bonus := get_damage_bonus(context)
	var primary_power := UNARMED_POWER
	var primary_range := character_data.base_attack_range if character_data != null else 0.0
	var primary_type := WeaponData.WeaponType.MELEE
	if primary_weapon != null:
		primary_power = primary_weapon.weapon_power
		primary_range = primary_weapon.attack_range
		primary_type = primary_weapon.weapon_type

	var offhand_weapon: WeaponData = null
	var offhand_power := 0
	var add_offhand := false
	if primary_slot == "main" and primary_weapon != null and off_hand_weapon != null and off_hand_enabled:
		if primary_weapon.weapon_type == off_hand_weapon.weapon_type:
			offhand_weapon = off_hand_weapon
			offhand_power = off_hand_weapon.weapon_power
			add_offhand = true

	return {
		"primary_slot": primary_slot,
		"primary_weapon": primary_weapon,
		"primary_power": primary_power,
		"primary_range": primary_range,
		"primary_weapon_type": primary_type,
		"damage_bonus": damage_bonus,
		"add_offhand": add_offhand,
		"offhand_weapon": offhand_weapon,
		"offhand_power": offhand_power,
	}


func get_weapon_for_attack_slot(slot: String) -> WeaponData:
	if slot == "main" and main_hand_enabled:
		return main_hand_weapon
	if slot == "off" and off_hand_enabled:
		return off_hand_weapon

	return null


func get_max_ap(config = null) -> int:
	var base_ap := 4
	if config != null:
		base_ap = int(config.get("base_ap"))

	return base_ap + extra_ap_bonus


func get_deck_card_count() -> int:
	var total := 0
	for stack in deck:
		if stack != null:
			total += stack.count

	return total


func get_inventory_item_count() -> int:
	var total := 0
	for stack in inventory:
		if stack != null:
			total += stack.count

	return total


func equip_main_hand(weapon: WeaponData) -> bool:
	if weapon == null:
		main_hand_weapon = null
		_refresh_equipment_enabled()
		return true

	if not weapon.can_equip_main_hand():
		return false

	main_hand_weapon = weapon
	_refresh_equipment_enabled()

	return true


func equip_off_hand(weapon: WeaponData) -> bool:
	if weapon == null:
		off_hand_weapon = null
		_refresh_equipment_enabled()
		return true

	if not weapon.can_equip_off_hand():
		return false

	off_hand_weapon = weapon
	_refresh_equipment_enabled()
	return true


func switch_weapon_from_inventory(preferred_weapon: WeaponData = null) -> Dictionary:
	var weapon := preferred_weapon
	var stack_index := -1
	if weapon == null:
		for i in range(inventory.size()):
			var stack := inventory[i]
			if stack != null and stack.item_data is WeaponData and stack.count > 0:
				weapon = stack.item_data
				stack_index = i
				break
	else:
		for i in range(inventory.size()):
			var stack := inventory[i]
			if stack != null and stack.item_data == weapon and stack.count > 0:
				stack_index = i
				break

	if weapon == null or stack_index < 0:
		return {"success": false}

	var slot := _choose_switch_slot(weapon)
	if slot.is_empty():
		return {"success": false}

	var previous: WeaponData = null
	if slot == "main":
		previous = main_hand_weapon
		main_hand_weapon = weapon
	elif slot == "off":
		previous = off_hand_weapon
		off_hand_weapon = weapon
	else:
		return {"success": false}

	_remove_inventory_item_at(stack_index)
	if previous != null:
		_add_inventory_item(previous)

	_refresh_equipment_enabled()
	return {
		"success": true,
		"slot": slot,
		"old_weapon": previous,
		"new_weapon": weapon,
		"main_hand_enabled": main_hand_enabled,
		"off_hand_enabled": off_hand_enabled,
	}


func get_main_hand_label() -> String:
	if main_hand_weapon == null:
		return "主手：无"

	return "主手：%s 威力%d%s" % [main_hand_weapon.item_name, main_hand_weapon.weapon_power, "" if main_hand_enabled else "（未生效）"]


func get_off_hand_label() -> String:
	if off_hand_weapon == null:
		return "副手：无"

	return "副手：%s 威力%d%s" % [off_hand_weapon.item_name, off_hand_weapon.weapon_power, "" if off_hand_enabled else "（未生效）"]


func _make_weapon_option(slot: String, weapon: WeaponData) -> Dictionary:
	return {
		"slot": slot,
		"label": "%s：%s 威力%d 射程%.0f" % ["主手" if slot == "main" else "副手", weapon.item_name, weapon.weapon_power, weapon.attack_range],
		"weapon": weapon,
		"power": weapon.weapon_power,
		"range": weapon.attack_range,
		"weapon_type": weapon.weapon_type,
	}


func _resolve_primary_attack_slot(weapon_slot: String = "") -> String:
	if weapon_slot == "main" and main_hand_weapon != null and main_hand_enabled:
		return "main"
	if weapon_slot == "off" and off_hand_weapon != null and off_hand_enabled:
		return "off"
	if main_hand_weapon != null and main_hand_enabled:
		return "main"
	if off_hand_weapon != null and off_hand_enabled:
		return "off"

	return "unarmed"


func _choose_switch_slot(weapon: WeaponData) -> String:
	if weapon.grip_type == WeaponData.GripType.TWO_HAND or weapon.grip_type == WeaponData.GripType.MAIN_HAND:
		return "main"
	if weapon.grip_type == WeaponData.GripType.OFF_HAND:
		return "off"
	if main_hand_weapon == null and weapon.can_equip_main_hand():
		return "main"
	if off_hand_weapon == null and weapon.can_equip_off_hand():
		return "off"
	if weapon.can_equip_main_hand():
		return "main"
	if weapon.can_equip_off_hand():
		return "off"

	return ""


func _refresh_equipment_enabled() -> void:
	main_hand_enabled = main_hand_weapon != null
	off_hand_enabled = off_hand_weapon != null
	if main_hand_weapon != null and main_hand_weapon.is_two_handed():
		off_hand_enabled = false


func _remove_inventory_item_at(index: int) -> void:
	if index < 0 or index >= inventory.size():
		return
	var stack := inventory[index]
	if stack == null:
		return

	stack.count -= 1
	if stack.count <= 0:
		inventory.remove_at(index)


func _add_inventory_item(item: ItemData) -> void:
	if item == null:
		return

	for stack in inventory:
		if stack != null and stack.item_data == item and stack.count < item.max_stack:
			stack.count += 1
			return

	var new_stack := InventoryStack.new()
	new_stack.item_data = item
	new_stack.count = 1
	inventory.append(new_stack)
