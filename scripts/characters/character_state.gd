extends Resource
class_name CharacterState

@export var character_data: CharacterData
@export var current_health: int = -1
@export_range(1, 99, 1) var level: int = 1
@export var deck: Array[CardStack] = []
@export_group("Equipment")
@export var weapon_equipment: EquipmentData
@export_range(0, 1, 1) var weapon_face: int = 0
@export var armor_equipment: EquipmentData
@export var accessory_equipment_1: EquipmentData
@export var accessory_equipment_2: EquipmentData
@export_group("Legacy Equipment")
@export var main_hand_equipment: EquipmentData
@export var off_hand_equipment: EquipmentData
@export_range(0, 1, 1) var main_hand_face: int = 0
@export_range(0, 1, 1) var off_hand_face: int = 0
@export var inventory: Array[InventoryStack] = []
@export var class_resources: Array[ResourcePoolState] = []
@export var extra_ap_bonus: int = 0
@export_group("Attribute Bonuses")
@export var strength_bonus: int = 0
@export var agility_bonus: int = 0
@export var intelligence_bonus: int = 0
@export_group("Combat Bonuses")
@export var flat_damage_bonus: int = 0
@export var damage_reduction: int = 0
var main_hand_enabled: bool = true
var off_hand_enabled: bool = true
const UNARMED_POWER := 1
const INVENTORY_LIMIT := 20
const MAX_HEALTH_PER_STRENGTH := 3
const HEALTH_GROWTH_PER_STRENGTH_LEVEL := 1
const DAMAGE_PER_ATTRIBUTE := 1

func ensure_initialized() -> void:
	if character_data == null:
		return

	_migrate_legacy_equipment()
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

	var level_growth := maxi(0, level - 1) * get_strength() * HEALTH_GROWTH_PER_STRENGTH_LEVEL
	return character_data.base_max_health + get_strength() * MAX_HEALTH_PER_STRENGTH + level_growth


func get_attack() -> int:
	var profile := build_strike_profile_object()
	return profile.primary_power + profile.damage_bonus


func get_strength() -> int:
	if character_data == null:
		return 0

	return character_data.base_strength + strength_bonus


func get_damage_bonus(context: Dictionary = {}) -> int:
	var bonus := _get_attribute_damage_bonus(context)
	bonus += flat_damage_bonus + _get_equipment_damage_bonus()
	var unit = context.get("unit")
	if unit != null and unit.has_method("get_status_damage_bonus"):
		bonus += unit.get_status_damage_bonus(context)

	return bonus


func get_agility() -> int:
	if character_data == null:
		return 0

	return character_data.base_agility + agility_bonus


func get_intelligence() -> int:
	if character_data == null:
		return 0

	return character_data.base_intelligence + intelligence_bonus


func get_strength_damage_bonus() -> int:
	return get_strength() * DAMAGE_PER_ATTRIBUTE


func get_agility_damage_bonus() -> int:
	return get_agility() * DAMAGE_PER_ATTRIBUTE


func get_intelligence_damage_bonus() -> int:
	return get_intelligence() * DAMAGE_PER_ATTRIBUTE


func get_damage_reduction() -> int:
	return maxi(0, damage_reduction + _get_equipment_damage_reduction())


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
	for equipment in get_equipped_items():
		if equipment != null and equipment.has_tag(subcategory):
			return true

	return false


func needs_weapon_choice() -> bool:
	return weapon_equipment != null and weapon_equipment.can_switch_face()


func get_attack_weapon_options() -> Array:
	var options := []
	var primary_weapon := get_weapon_face(0)
	if primary_weapon != null:
		options.append(_make_equipment_option("weapon", primary_weapon, 0))
	var alternate_weapon := get_weapon_face(1)
	if alternate_weapon != null and alternate_weapon != primary_weapon:
		options.append(_make_equipment_option("weapon_alt", alternate_weapon, 1))
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
	var profile := StrikeProfile.new()
	profile.primary_slot = primary_slot
	profile.primary_power = UNARMED_POWER
	profile.primary_range = character_data.base_attack_range if character_data != null else 0.0
	profile.primary_range_type = EquipmentData.WeaponRangeType.MELEE
	profile.primary_damage_type = _resolve_damage_type(context, primary_equipment)
	var damage_context := context.duplicate()
	damage_context["resolved_damage_type"] = profile.primary_damage_type
	damage_context["equipment"] = primary_equipment
	profile.damage_bonus = get_damage_bonus(damage_context)
	if primary_equipment != null:
		profile.primary_equipment = primary_equipment
		profile.primary_power = primary_equipment.power
		profile.primary_range = primary_equipment.attack_range
		profile.primary_range_type = primary_equipment.range_type

	return profile


func get_equipment_for_attack_slot(slot: String) -> EquipmentData:
	if slot == "weapon":
		return get_weapon_face(0)
	if slot == "weapon_alt":
		return get_weapon_face(1)
	if slot == "main":
		return get_weapon_face(0)
	if slot == "off":
		return get_weapon_face(1)

	return null


func get_active_main_hand_equipment() -> EquipmentData:
	return get_weapon_face(0)


func get_active_off_hand_equipment() -> EquipmentData:
	return get_weapon_face(1)


func get_active_weapon_equipment() -> EquipmentData:
	return get_weapon_face(weapon_face)


func get_weapon_face(face_index: int) -> EquipmentData:
	if weapon_equipment == null:
		return null
	if face_index == 1 and weapon_equipment.back_face == null:
		return null

	return weapon_equipment.get_face(face_index)


func get_equipped_items() -> Array[EquipmentData]:
	var result: Array[EquipmentData] = []
	var weapon := get_active_weapon_equipment()
	if weapon != null:
		result.append(weapon)
	if armor_equipment != null:
		result.append(armor_equipment)
	if accessory_equipment_1 != null:
		result.append(accessory_equipment_1)
	if accessory_equipment_2 != null:
		result.append(accessory_equipment_2)

	return result


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
	return equip_weapon(equipment)


func equip_off_hand(equipment: EquipmentData) -> bool:
	return equip_armor(equipment)


func equip_weapon(equipment: EquipmentData) -> bool:
	if equipment == null:
		weapon_equipment = null
		weapon_face = 0
		_refresh_equipment_enabled()
		return true
	if not equipment.is_weapon():
		return false

	weapon_equipment = equipment
	weapon_face = 0
	_refresh_equipment_enabled()
	return true


func equip_armor(equipment: EquipmentData) -> bool:
	if equipment == null:
		armor_equipment = null
		_refresh_equipment_enabled()
		return true
	if not equipment.is_armor():
		return false

	armor_equipment = equipment
	_refresh_equipment_enabled()
	return true


func equip_accessory(equipment: EquipmentData, slot_index: int) -> bool:
	if equipment == null:
		if slot_index == 1:
			accessory_equipment_1 = null
		elif slot_index == 2:
			accessory_equipment_2 = null
		else:
			return false
		_refresh_equipment_enabled()
		return true
	if not equipment.is_accessory():
		return false

	if slot_index == 1:
		accessory_equipment_1 = equipment
	elif slot_index == 2:
		accessory_equipment_2 = equipment
	else:
		return false

	_refresh_equipment_enabled()
	return true


func switch_equipment_from_inventory(preferred_equipment: EquipmentData = null) -> Dictionary:
	return CharacterEquipmentModel.switch_equipment_from_inventory(self, preferred_equipment)


func switch_equipment_face(slot: String) -> bool:
	if (slot == "weapon" or slot == "main" or slot == "off") and weapon_equipment != null and weapon_equipment.can_switch_face():
		weapon_face = 1 - weapon_face
		_refresh_equipment_enabled()
		return true
	return false


func get_main_hand_label() -> String:
	var equipment := get_active_weapon_equipment()
	if equipment == null:
		return "武器：无"

	return "武器：%s 威力%d 射程%.0f %s" % [equipment.item_name, equipment.power, equipment.attack_range, equipment.get_damage_type_label()]


func get_off_hand_label() -> String:
	var parts := PackedStringArray()
	parts.append("防具：%s" % (armor_equipment.item_name if armor_equipment != null else "无"))
	parts.append("饰品1：%s" % (accessory_equipment_1.item_name if accessory_equipment_1 != null else "无"))
	parts.append("饰品2：%s" % (accessory_equipment_2.item_name if accessory_equipment_2 != null else "无"))

	return " / ".join(parts)


func _make_equipment_option(slot: String, equipment: EquipmentData, face_index: int = 0) -> Dictionary:
	var slot_label := "武器"
	if face_index == 1:
		slot_label = "武器形态2"
	return {
		"slot": slot,
		"label": "%s：%s 威力%d 射程%.0f %s" % [slot_label, equipment.item_name, equipment.power, equipment.attack_range, equipment.get_damage_type_label()],
		"equipment": equipment,
		"power": equipment.power,
		"range": equipment.attack_range,
		"range_type": equipment.range_type,
		"damage_type": equipment.damage_type,
	}


func _resolve_primary_attack_slot(equipment_slot: String = "") -> String:
	if equipment_slot == "weapon":
		return "weapon" if get_weapon_face(0) != null else "unarmed"
	if equipment_slot == "weapon_alt":
		return "weapon_alt" if get_weapon_face(1) != null else "unarmed"
	if equipment_slot == "main":
		return "weapon" if get_weapon_face(0) != null else "unarmed"
	if equipment_slot == "off":
		return "weapon_alt" if get_weapon_face(1) != null else "unarmed"
	if get_active_weapon_equipment() != null:
		return "weapon" if weapon_face == 0 else "weapon_alt"

	return "unarmed"


func _refresh_equipment_enabled() -> void:
	CharacterEquipmentModel.refresh_enabled(self)


func _get_attribute_damage_bonus(context: Dictionary = {}) -> int:
	var equipment: EquipmentData = null
	var equipment_value = context.get("equipment")
	if equipment_value is EquipmentData:
		equipment = equipment_value as EquipmentData
	match _resolve_damage_type(context, equipment):
		CardEnums.DamageType.AGILITY:
			return get_agility_damage_bonus()
		CardEnums.DamageType.INTELLIGENCE:
			return get_intelligence_damage_bonus()
		_:
			return get_strength_damage_bonus()


func _resolve_damage_type(context: Dictionary = {}, equipment: EquipmentData = null) -> int:
	if context.has("resolved_damage_type"):
		return int(context.get("resolved_damage_type"))

	var card := _get_context_card(context)
	var card_damage_type := CardEnums.DamageType.WEAPON
	if card != null:
		card_damage_type = card.damage_type

	if card_damage_type == CardEnums.DamageType.WEAPON:
		if equipment != null:
			return equipment.damage_type
		return CardEnums.DamageType.STRENGTH

	return card_damage_type


func _get_equipment_damage_bonus() -> int:
	var bonus := 0
	for equipment in get_equipped_items():
		if equipment != null:
			bonus += equipment.damage_bonus

	return bonus


func _get_equipment_damage_reduction() -> int:
	var reduction := 0
	for equipment in get_equipped_items():
		if equipment != null:
			reduction += equipment.damage_reduction

	return reduction


func _migrate_legacy_equipment() -> void:
	if weapon_equipment == null and main_hand_equipment != null:
		weapon_equipment = main_hand_equipment
		weapon_face = main_hand_face
	if armor_equipment == null and off_hand_equipment != null and off_hand_equipment.is_armor():
		armor_equipment = off_hand_equipment
	elif off_hand_equipment != null and off_hand_equipment != weapon_equipment:
		CharacterEquipmentModel.add_inventory_item(self, off_hand_equipment)

	main_hand_equipment = null
	off_hand_equipment = null
	main_hand_face = 0
	off_hand_face = 0


func _get_context_card(context: Dictionary = {}) -> CardData:
	var card = context.get("card")
	if card is CardData:
		return card as CardData

	var source = context.get("source")
	if source is CardData:
		return source as CardData

	return null


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
