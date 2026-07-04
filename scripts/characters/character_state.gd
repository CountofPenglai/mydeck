extends Resource
class_name CharacterState

@export var character_data: CharacterData
@export var current_health: int = -1
@export var deck: Array[CardStack] = []
@export var main_hand_equipment: EquipmentData
@export var off_hand_equipment: EquipmentData
@export_range(0, 1, 1) var main_hand_face: int = 0
@export_range(0, 1, 1) var off_hand_face: int = 0
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

	if _class_resources_need_reset():
		reset_class_resources()


func reset_class_resources() -> void:
	class_resources.clear()

	if character_data == null:
		return

	for pool_data in character_data.get_resource_pool_definitions():
		var pool_state := ResourcePoolState.new()
		pool_state.setup(pool_data)
		class_resources.append(pool_state)


func get_class_resource(resource_name: String) -> ResourcePoolState:
	for pool_state in class_resources:
		if pool_state != null and pool_state.get_resource_name() == resource_name:
			return pool_state

	return null


func get_class_resource_value(resource_name: String) -> int:
	var pool_state := get_class_resource(resource_name)
	if pool_state == null:
		return 0

	return pool_state.current_value


func gain_class_resource(resource_name: String, amount: int) -> int:
	var pool_state := get_class_resource(resource_name)
	if pool_state == null:
		return 0

	return pool_state.gain(amount)


func consume_class_resource(resource_name: String, amount: int) -> bool:
	var pool_state := get_class_resource(resource_name)
	if pool_state == null:
		return false

	return pool_state.consume(amount)


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
	var profile := build_strike_profile_object()
	return profile.primary_power + profile.damage_bonus


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


func get_collision_radius() -> float:
	if character_data == null:
		return 0.0

	return character_data.collision_radius


func get_attack_range(equipment_slot: String = "") -> float:
	if character_data == null:
		return 0.0

	var equipment := get_equipment_for_attack_slot(_resolve_primary_attack_slot(equipment_slot))
	if equipment != null:
		return equipment.attack_range

	return character_data.base_attack_range


func has_equipment_subcategory(subcategory: String) -> bool:
	if get_active_main_hand_equipment() != null and main_hand_enabled and get_active_main_hand_equipment().has_tag(subcategory):
		return true
	if get_active_off_hand_equipment() != null and off_hand_enabled:
		return get_active_off_hand_equipment().has_tag(subcategory)

	return false


func needs_weapon_choice() -> bool:
	var main_equipment := get_active_main_hand_equipment()
	var off_equipment := get_active_off_hand_equipment()
	if main_equipment == null or off_equipment == null:
		return false
	if not main_hand_enabled or not off_hand_enabled:
		return false

	return main_equipment.range_type != off_equipment.range_type


func get_attack_weapon_options() -> Array:
	var options := []
	var main_equipment := get_active_main_hand_equipment()
	var off_equipment := get_active_off_hand_equipment()
	if main_equipment != null and main_hand_enabled:
		options.append(_make_equipment_option("main", main_equipment))
	if off_equipment != null and off_hand_enabled and needs_weapon_choice():
		options.append(_make_equipment_option("off", off_equipment))
	if options.is_empty():
		options.append({
			"slot": "unarmed",
			"label": "空手",
			"weapon": null,
			"equipment": null,
			"power": UNARMED_POWER,
			"range": character_data.base_attack_range if character_data != null else 0.0,
			"range_type": EquipmentData.WeaponRangeType.MELEE,
		})

	return options


func build_strike_profile_object(equipment_slot: String = "", context: Dictionary = {}) -> StrikeProfile:
	var primary_slot := _resolve_primary_attack_slot(equipment_slot)
	var primary_equipment := get_equipment_for_attack_slot(primary_slot)
	var disable_offhand := bool(context.get("disable_offhand", false))
	var profile := StrikeProfile.new()
	profile.primary_slot = primary_slot
	profile.damage_bonus = get_damage_bonus(context)
	profile.primary_power = UNARMED_POWER
	profile.primary_range = character_data.base_attack_range if character_data != null else 0.0
	profile.primary_range_type = EquipmentData.WeaponRangeType.MELEE
	if primary_equipment != null:
		profile.primary_equipment = primary_equipment
		profile.primary_power = primary_equipment.power
		profile.primary_range = primary_equipment.attack_range
		profile.primary_range_type = primary_equipment.range_type

	var off_equipment := get_active_off_hand_equipment()
	if not disable_offhand and primary_slot == "main" and primary_equipment != null and off_equipment != null and off_hand_enabled:
		if primary_equipment.range_type == off_equipment.range_type:
			profile.offhand_equipment = off_equipment
			profile.offhand_power = off_equipment.power
			profile.add_offhand = true

	return profile


func get_equipment_for_attack_slot(slot: String) -> EquipmentData:
	if slot == "main" and main_hand_enabled:
		return get_active_main_hand_equipment()
	if slot == "off" and off_hand_enabled:
		return get_active_off_hand_equipment()

	return null


func get_active_main_hand_equipment() -> EquipmentData:
	if main_hand_equipment == null:
		return null
	return main_hand_equipment.get_face(main_hand_face)


func get_active_off_hand_equipment() -> EquipmentData:
	if off_hand_equipment == null:
		return null
	return off_hand_equipment.get_face(off_hand_face)


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


func equip_main_hand(equipment: EquipmentData) -> bool:
	if equipment == null:
		main_hand_equipment = null
		main_hand_face = 0
		_refresh_equipment_enabled()
		return true

	if not equipment.can_equip_main_hand():
		return false

	main_hand_equipment = equipment
	main_hand_face = 0
	_refresh_equipment_enabled()

	return true


func equip_off_hand(equipment: EquipmentData) -> bool:
	if equipment == null:
		off_hand_equipment = null
		off_hand_face = 0
		_refresh_equipment_enabled()
		return true

	if not equipment.can_equip_off_hand():
		return false

	off_hand_equipment = equipment
	off_hand_face = 0
	_refresh_equipment_enabled()
	return true


func switch_equipment_from_inventory(preferred_equipment: EquipmentData = null) -> Dictionary:
	return CharacterEquipmentModel.switch_equipment_from_inventory(self, preferred_equipment)


func switch_equipment_face(slot: String) -> bool:
	if slot == "main" and main_hand_equipment != null and main_hand_equipment.can_switch_face():
		main_hand_face = 1 - main_hand_face
		_refresh_equipment_enabled()
		return true
	if slot == "off" and off_hand_equipment != null and off_hand_equipment.can_switch_face():
		off_hand_face = 1 - off_hand_face
		_refresh_equipment_enabled()
		return true
	return false


func get_main_hand_label() -> String:
	var equipment := get_active_main_hand_equipment()
	if equipment == null:
		return "主手：无"

	return "主手：%s 威力%d%s" % [equipment.item_name, equipment.power, "" if main_hand_enabled else "（未生效）"]


func get_off_hand_label() -> String:
	var equipment := get_active_off_hand_equipment()
	if equipment == null:
		return "副手：无"

	return "副手：%s 威力%d%s" % [equipment.item_name, equipment.power, "" if off_hand_enabled else "（未生效）"]


func _make_equipment_option(slot: String, equipment: EquipmentData) -> Dictionary:
	return {
		"slot": slot,
		"label": "%s：%s 威力%d 射程%.0f" % ["主手" if slot == "main" else "副手", equipment.item_name, equipment.power, equipment.attack_range],
		"equipment": equipment,
		"power": equipment.power,
		"range": equipment.attack_range,
		"range_type": equipment.range_type,
	}


func _resolve_primary_attack_slot(equipment_slot: String = "") -> String:
	if equipment_slot == "main":
		return "main" if get_active_main_hand_equipment() != null and main_hand_enabled else "unarmed"
	if equipment_slot == "off":
		return "off" if get_active_off_hand_equipment() != null and off_hand_enabled else "unarmed"
	if get_active_main_hand_equipment() != null and main_hand_enabled:
		return "main"
	if get_active_off_hand_equipment() != null and off_hand_enabled:
		return "off"

	return "unarmed"


func _refresh_equipment_enabled() -> void:
	CharacterEquipmentModel.refresh_enabled(self)


func _class_resources_need_reset() -> bool:
	if character_data == null:
		return false

	var definitions := character_data.get_resource_pool_definitions()
	if class_resources.size() != definitions.size():
		return true

	for definition in definitions:
		if definition == null:
			continue
		if get_class_resource(definition.pool_name) == null:
			return true

	return false
