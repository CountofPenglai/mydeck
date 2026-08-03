extends Resource
class_name CharacterState

@export var character_data: CharacterData
@export var current_health: int = -1
@export_range(1, 99, 1) var level: int = 1
@export var deck: Array[CardStack] = []
@export_group("Adventure Identity")
@export var adventure_character_id: String = ""
@export var adventure_source_path: String = ""
@export var equipment_instance_ids: Dictionary = {}
@export var equipment_adventure_modifiers: Dictionary = {}
@export var card_adventure_modifiers: Dictionary = {}
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
@export var ranger_element_inventory: Dictionary = {}
@export var extra_ap_bonus: int = 0
@export_group("Curses")
@export var curse_instances: Array[CurseInstance] = []
@export_range(1, 12, 1) var base_curse_load_limit: int = 3
@export var curse_load_limit_bonus: int = 0
@export var sealed_curse_id: String = ""
@export var distortion_progress: int = 0
@export var selected_distortion_fields: PackedStringArray = []
@export var claimed_distortion_milestones: PackedInt32Array = []
@export_range(0, 4, 1) var distortion_grace_count: int = 0
@export var persistent_max_health_modifier: int = 0
@export var adventure_damage_bonus: int = 0
@export_group("Attribute Bonuses")
@export var strength_bonus: int = 0
@export var agility_bonus: int = 0
@export var intelligence_bonus: int = 0
@export_group("Combat Bonuses")
@export var flat_damage_bonus: int = 0
@export var damage_reduction: int = 0
const UNARMED_BASE_DAMAGE := 1
const UNARMED_ATTACK_RANGE := 1
const INVENTORY_LIMIT := 20
const MAX_HEALTH_PER_STRENGTH := 3
const HEALTH_GROWTH_PER_STRENGTH_LEVEL := 1

func ensure_initialized() -> void:
	if character_data == null:
		return

	_migrate_legacy_equipment()
	_normalize_curses()

	if current_health < 0:
		current_health = get_max_health()

	if _class_resources_need_reset():
		reset_class_resources()


func ensure_adventure_instance_ids(character_index: int = 0) -> void:
	if adventure_character_id.is_empty():
		adventure_character_id = "hero_%02d" % character_index
	var used_ids := {}
	for slot in ["weapon", "armor", "accessory_1", "accessory_2"]:
		var equipment_id := str(equipment_instance_ids.get(slot, ""))
		if equipment_id.is_empty() or used_ids.has(equipment_id):
			equipment_id = _unique_instance_id("%s_equipment_%s" % [adventure_character_id, slot], used_ids)
			equipment_instance_ids[slot] = equipment_id
		used_ids[equipment_id] = true
	for index in range(deck.size()):
		var stack := deck[index]
		if stack != null:
			var stack_id := stack.stack_id
			if stack_id.is_empty() or used_ids.has(stack_id):
				stack_id = _unique_instance_id("%s_card_%03d" % [adventure_character_id, index], used_ids)
				stack.stack_id = stack_id
			used_ids[stack_id] = true
	for index in range(inventory.size()):
		var stack := inventory[index]
		if stack != null:
			var stack_id := stack.stack_id
			if stack_id.is_empty() or used_ids.has(stack_id):
				stack_id = _unique_instance_id("%s_item_%03d" % [adventure_character_id, index], used_ids)
				stack.stack_id = stack_id
			used_ids[stack_id] = true


func _unique_instance_id(base_id: String, used_ids: Dictionary) -> String:
	var candidate := base_id
	var suffix := 2
	while used_ids.has(candidate):
		candidate = "%s_%d" % [base_id, suffix]
		suffix += 1
	return candidate


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
	return maxi(1, character_data.base_max_health + get_strength() * MAX_HEALTH_PER_STRENGTH + level_growth + persistent_max_health_modifier)


func get_attack() -> int:
	var profile := build_strike_profile_object()
	var total := profile.primary_base_damage + profile.primary_damage_bonus
	if profile.add_offhand:
		total += profile.offhand_base_damage + profile.offhand_damage_bonus
	return total


func get_strength() -> int:
	if character_data == null:
		return 0

	return character_data.base_strength + strength_bonus


func get_damage_bonus(context: Dictionary = {}) -> int:
	var bonus := _get_attribute_damage_bonus(context)
	bonus += flat_damage_bonus + adventure_damage_bonus + _get_equipment_damage_bonus()
	bonus += _get_equipment_instance_damage_bonus(context)
	var unit = context.get("unit")
	if unit != null and unit.has_method("get_status_damage_bonus"):
		bonus += unit.get_status_damage_bonus(context)
	if unit != null and unit.has_method("get_next_card_damage_bonus"):
		bonus += unit.get_next_card_damage_bonus(context)
	if unit != null and unit.has_method("get_equipment_effect_damage_bonus"):
		bonus += unit.get_equipment_effect_damage_bonus(context)

	return bonus


func get_equipment_instance_id(equipment: EquipmentData) -> String:
	if equipment == null:
		return ""
	if weapon_equipment != null and equipment in weapon_equipment.get_active_components(weapon_face):
		return str(equipment_instance_ids.get("weapon", ""))
	if equipment == armor_equipment:
		return str(equipment_instance_ids.get("armor", ""))
	if equipment == accessory_equipment_1:
		return str(equipment_instance_ids.get("accessory_1", ""))
	if equipment == accessory_equipment_2:
		return str(equipment_instance_ids.get("accessory_2", ""))
	return ""


func _get_equipment_instance_damage_bonus(context: Dictionary) -> int:
	var equipment := context.get("equipment") as EquipmentData
	var instance_id := get_equipment_instance_id(equipment)
	if instance_id.is_empty():
		return 0
	var modifiers := equipment_adventure_modifiers.get(instance_id, {}) as Dictionary
	return int(modifiers.get("damage_bonus", 0))


func get_agility() -> int:
	if character_data == null:
		return 0

	return character_data.base_agility + agility_bonus


func get_intelligence() -> int:
	if character_data == null:
		return 0

	return character_data.base_intelligence + intelligence_bonus


func get_strength_damage_bonus() -> int:
	return CharacterAttributeRules.get_damage_bonus(get_strength())


func get_agility_damage_bonus() -> int:
	return CharacterAttributeRules.get_damage_bonus(get_agility())


func get_intelligence_damage_bonus() -> int:
	return CharacterAttributeRules.get_damage_bonus(get_intelligence())


func get_damage_reduction(context: Dictionary = {}) -> int:
	var result := damage_reduction + _get_equipment_damage_reduction()
	var unit = context.get("unit")
	if unit != null and unit.has_method("get_equipment_effect_damage_reduction"):
		result += unit.get_equipment_effect_damage_reduction(context)
	return maxi(0, result)


func get_battle_token_radius() -> float:
	if character_data == null:
		return 0.0

	return character_data.battle_token_radius


func get_attack_range(equipment_slot: String = "", face_index: int = -1) -> int:
	var equipment := get_equipment_for_attack_slot(_resolve_primary_attack_slot(equipment_slot), face_index)
	if equipment != null:
		return equipment.attack_range

	return UNARMED_ATTACK_RANGE


func has_equipment_subcategory(subcategory: String) -> bool:
	for equipment in get_equipped_items():
		if equipment != null and equipment.has_tag(subcategory):
			return true

	return false


func needs_weapon_choice(face_index: int = -1) -> bool:
	var weapon := get_weapon_face(_resolve_weapon_face_index(face_index))
	return weapon != null \
		and weapon.paired_component != null \
		and weapon.paired_attack_mode == EquipmentData.PairedAttackMode.SELECT_ONE


func get_attack_weapon_options(face_index: int = -1) -> Array:
	var options := []
	var resolved_face := _resolve_weapon_face_index(face_index)
	var primary_weapon := get_weapon_face(resolved_face)
	if primary_weapon != null:
		options.append(_make_equipment_option("weapon", primary_weapon, resolved_face))
		if primary_weapon.paired_component != null \
				and primary_weapon.paired_attack_mode == EquipmentData.PairedAttackMode.SELECT_ONE:
			options.append(_make_equipment_option("paired", primary_weapon.paired_component, 0))
	if options.is_empty():
		options.append({
			"slot": "unarmed",
			"label": "空手",
			"weapon": null,
			"equipment": null,
			"base_damage": UNARMED_BASE_DAMAGE,
			"range": UNARMED_ATTACK_RANGE,
			"range_type": EquipmentData.WeaponRangeType.MELEE,
		})

	return options


func build_strike_profile_object(equipment_slot: String = "", context: Dictionary = {}) -> StrikeProfile:
	var resolved_face := _resolve_weapon_face_index(int(context.get("weapon_face_override", -1)))
	var primary_slot := _resolve_primary_attack_slot(equipment_slot)
	var primary_equipment := get_equipment_for_attack_slot(primary_slot, resolved_face)
	var profile := StrikeProfile.new()
	profile.primary_slot = primary_slot
	profile.primary_base_damage = UNARMED_BASE_DAMAGE
	profile.primary_range = UNARMED_ATTACK_RANGE
	profile.primary_range_type = EquipmentData.WeaponRangeType.MELEE
	profile.primary_damage_type = _resolve_damage_type(context, primary_equipment)
	var damage_context := context.duplicate()
	damage_context["resolved_damage_type"] = profile.primary_damage_type
	damage_context["equipment"] = primary_equipment
	profile.primary_damage_bonus = get_damage_bonus(damage_context)
	if primary_equipment != null:
		profile.primary_equipment = primary_equipment
		profile.primary_base_damage = primary_equipment.base_damage
		profile.primary_range = primary_equipment.attack_range
		profile.primary_range_type = primary_equipment.range_type

	var secondary := get_off_hand_equipment_for_face(resolved_face)
	if primary_slot != "paired" \
			and weapon_equipment != null \
			and weapon_equipment.has_secondary_damage_segment(resolved_face) \
			and secondary != null:
		profile.add_offhand = true
		profile.offhand_equipment = secondary
		profile.offhand_base_damage = secondary.base_damage
		profile.offhand_damage_type = secondary.damage_type
		var secondary_context := context.duplicate()
		secondary_context["resolved_damage_type"] = secondary.damage_type
		secondary_context["equipment"] = secondary
		profile.offhand_damage_bonus = get_damage_bonus(secondary_context)

	return profile


func get_equipment_for_attack_slot(slot: String, face_index: int = -1) -> EquipmentData:
	if slot == "paired":
		return get_off_hand_equipment_for_face(_resolve_weapon_face_index(face_index))
	if slot in ["weapon", "weapon_alt", "main", "off"]:
		return get_weapon_face(_resolve_weapon_face_index(face_index))

	return null


func get_active_main_hand_equipment() -> EquipmentData:
	return get_active_weapon_equipment()


func get_active_off_hand_equipment() -> EquipmentData:
	return get_off_hand_equipment_for_face(weapon_face)


func get_off_hand_equipment_for_face(face_index: int) -> EquipmentData:
	var weapon := get_weapon_face(face_index)
	return weapon.paired_component if weapon != null else null


func get_active_weapon_equipment() -> EquipmentData:
	return get_weapon_face(weapon_face)


func _resolve_weapon_face_index(face_index: int) -> int:
	return weapon_face if face_index < 0 else clampi(face_index, 0, 1)


func get_weapon_face(face_index: int) -> EquipmentData:
	if weapon_equipment == null:
		return null
	if face_index == 1 and weapon_equipment.back_face == null:
		return null

	return weapon_equipment.get_face(face_index)


func get_equipped_items() -> Array[EquipmentData]:
	var result: Array[EquipmentData] = []
	if weapon_equipment != null:
		result.append_array(weapon_equipment.get_active_components(weapon_face))
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
		return true
	if not equipment.is_weapon():
		return false

	weapon_equipment = equipment
	weapon_face = 0
	return true


func equip_armor(equipment: EquipmentData) -> bool:
	if equipment == null:
		armor_equipment = null
		return true
	if not equipment.is_armor():
		return false

	armor_equipment = equipment
	return true


func equip_accessory(equipment: EquipmentData, slot_index: int) -> bool:
	if equipment == null:
		if slot_index == 1:
			accessory_equipment_1 = null
		elif slot_index == 2:
			accessory_equipment_2 = null
		else:
			return false
		return true
	if not equipment.is_accessory():
		return false

	if slot_index == 1:
		accessory_equipment_1 = equipment
	elif slot_index == 2:
		accessory_equipment_2 = equipment
	else:
		return false

	return true


func switch_equipment_from_inventory(preferred_equipment: EquipmentData = null) -> Dictionary:
	return CharacterEquipmentModel.switch_equipment_from_inventory(self, preferred_equipment)


func switch_equipment_face(slot: String) -> bool:
	if (slot == "weapon" or slot == "main" or slot == "off") and weapon_equipment != null and weapon_equipment.can_switch_face():
		weapon_face = 1 - weapon_face
		return true
	return false


func get_main_hand_label() -> String:
	var equipment := get_active_weapon_equipment()
	if equipment == null:
		return "武器：无"

	return "武器：%s 基础伤害%d 范围%d %s" % [equipment.item_name, equipment.base_damage, equipment.attack_range, equipment.get_damage_type_label()]


func get_off_hand_label() -> String:
	var parts := PackedStringArray()
	parts.append("防具：%s" % (armor_equipment.item_name if armor_equipment != null else "无"))
	parts.append("饰品1：%s" % (accessory_equipment_1.item_name if accessory_equipment_1 != null else "无"))
	parts.append("饰品2：%s" % (accessory_equipment_2.item_name if accessory_equipment_2 != null else "无"))

	return " / ".join(parts)


func _make_equipment_option(slot: String, equipment: EquipmentData, face_index: int = 0) -> Dictionary:
	var slot_label := "远程模式" if equipment.range_type == EquipmentData.WeaponRangeType.RANGED else "近战模式"
	if face_index == 1:
		slot_label = "武器形态2"
	return {
		"slot": slot,
		"label": "%s：%s 基础伤害%d 范围%d %s" % [slot_label, equipment.item_name, equipment.base_damage, equipment.attack_range, equipment.get_damage_type_label()],
		"equipment": equipment,
		"base_damage": equipment.base_damage,
		"range": equipment.attack_range,
		"range_type": equipment.range_type,
		"damage_type": equipment.damage_type,
	}


func _resolve_primary_attack_slot(equipment_slot: String = "") -> String:
	if equipment_slot == "paired" and get_active_off_hand_equipment() != null:
		return "paired"
	if equipment_slot in ["weapon", "weapon_alt", "main", "off"]:
		return "weapon" if get_active_weapon_equipment() != null else "unarmed"
	if get_active_weapon_equipment() != null:
		return "weapon"

	return "unarmed"


func _get_attribute_damage_bonus(context: Dictionary = {}) -> int:
	var equipment: EquipmentData = null
	var equipment_value = context.get("equipment")
	if equipment_value is EquipmentData:
		equipment = equipment_value as EquipmentData
	var unit = context.get("unit")
	if unit != null and unit.has_method("get_strength") and unit.has_method("get_agility") and unit.has_method("get_intelligence"):
		match _resolve_damage_type(context, equipment):
			CardEnums.DamageType.AGILITY:
				return _attribute_to_damage_bonus(int(unit.get_agility()))
			CardEnums.DamageType.INTELLIGENCE:
				return _attribute_to_damage_bonus(int(unit.get_intelligence()))
			_:
				return _attribute_to_damage_bonus(int(unit.get_strength()))
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


func _attribute_to_damage_bonus(attribute_value: int) -> int:
	return CharacterAttributeRules.get_damage_bonus(attribute_value)


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


func get_curse(curse_id: String) -> CurseInstance:
	for curse in curse_instances:
		if curse != null and curse.get_curse_id() == curse_id:
			return curse
	return null


func acquire_curse(definition: CurseDefinition) -> CurseInstance:
	if definition == null or not definition.is_valid_definition():
		return null
	var existing := get_curse(definition.curse_id)
	if existing != null:
		existing.deepen()
		return existing
	var instance := CurseInstance.new()
	instance.definition = definition
	curse_instances.append(instance)
	return instance


func get_active_curses() -> Array[CurseInstance]:
	var result: Array[CurseInstance] = []
	for curse in curse_instances:
		if curse != null and curse.is_active_in_curse_zone():
			result.append(curse)
	return result


func create_industry_cards() -> Array[CardData]:
	var result: Array[CardData] = []
	for curse in curse_instances:
		if curse == null or curse.state != CurseInstance.State.INDUSTRY or curse.definition == null:
			continue
		var template := curse.definition.industry_card
		if template == null:
			continue
		var card := template.duplicate(true) as CardData
		if card == null:
			continue
		card.bound_curse_instance = curse
		result.append(card)
	return result


func get_curse_load_limit() -> int:
	var result := maxi(0, base_curse_load_limit + curse_load_limit_bonus)
	for equipment in get_equipped_items():
		if equipment != null:
			result += equipment.curse_load_limit_bonus
	var universal_love := get_curse("universal_love")
	if universal_love != null and universal_love.state == CurseInstance.State.FRUIT and not universal_love.sealed:
		result += 2 * universal_love.depth
	var gospel := get_curse("gospel")
	if gospel != null and gospel.state != CurseInstance.State.INDUSTRY and not gospel.sealed:
		result += gospel.depth * (2 if gospel.state == CurseInstance.State.FRUIT else 1)
	return result


func get_curse_load() -> int:
	var result := 0
	for curse in curse_instances:
		if curse != null and not (curse.get_curse_id() == "counterfeit" and curse.state == CurseInstance.State.FRUIT and distortion_progress >= 2):
			result += curse.get_load_cost()
	return result


func is_curse_overloaded() -> bool:
	return get_curse_load() > get_curse_load_limit()


func get_next_distortion_threshold() -> int:
	var milestone_index := get_next_unclaimed_distortion_milestone()
	if milestone_index < 0:
		return int(DistortionCatalog.MILESTONES[DistortionCatalog.MILESTONES.size() - 1]) + 3
	return get_effective_distortion_threshold(milestone_index)


func get_next_unclaimed_distortion_milestone() -> int:
	for milestone_index in range(DistortionCatalog.MILESTONES.size()):
		if not claimed_distortion_milestones.has(milestone_index):
			return milestone_index
	return -1


func get_effective_distortion_threshold(milestone_index: int) -> int:
	if milestone_index < 0 or milestone_index >= DistortionCatalog.MILESTONES.size():
		return -1
	var threshold := int(DistortionCatalog.MILESTONES[milestone_index])
	if milestone_index != get_next_unclaimed_distortion_milestone():
		return threshold
	var counterfeit := get_curse("counterfeit")
	if counterfeit != null and counterfeit.state == CurseInstance.State.REPORT and not counterfeit.sealed:
		threshold += counterfeit.depth
	return threshold


func get_pending_distortion_milestone() -> int:
	var milestone_index := get_next_unclaimed_distortion_milestone()
	if milestone_index < 0:
		return -1
	return milestone_index if distortion_progress >= get_effective_distortion_threshold(milestone_index) else -1


func has_pending_distortion_reward() -> bool:
	return get_pending_distortion_milestone() >= 0


func apply_distortion_reward(reward_id: String) -> bool:
	var milestone_index := get_pending_distortion_milestone()
	if milestone_index < 0:
		return false
	if reward_id == DistortionCatalog.GRACE_ID:
		if distortion_grace_count >= DistortionCatalog.MILESTONES.size():
			return false
		var previous_max_health := get_max_health()
		strength_bonus += 1
		agility_bonus += 1
		intelligence_bonus += 1
		distortion_grace_count += 1
		current_health += maxi(0, get_max_health() - previous_max_health)
	else:
		var available_for_tier := (
			milestone_index < 2 and reward_id in DistortionCatalog.LOW_FIELDS
		) or (
			milestone_index >= 2 and reward_id in DistortionCatalog.HIGH_FIELDS
		)
		if selected_distortion_fields.has(reward_id) or not available_for_tier:
			return false
		selected_distortion_fields.append(reward_id)
	claimed_distortion_milestones.append(milestone_index)
	_normalize_distortion_state()
	return true


func seal_curse(curse: CurseInstance, run_state: PartyRunState, resolves_overload: bool = false) -> bool:
	if curse == null or curse not in curse_instances or curse.state == CurseInstance.State.INDUSTRY:
		return false
	if not sealed_curse_id.is_empty() or run_state == null or not run_state.pay_ritual(2, resolves_overload):
		return false
	curse.sealed = true
	sealed_curse_id = curse.get_curse_id()
	return true


func unseal_curse() -> bool:
	if sealed_curse_id.is_empty():
		return false
	var curse := get_curse(sealed_curse_id)
	if curse != null:
		curse.sealed = false
	sealed_curse_id = ""
	return true


func transfer_curse_to(curse: CurseInstance, target: CharacterState, run_state: PartyRunState, free_transfer: bool = false, resolves_overload: bool = false) -> bool:
	if curse == null or target == null or curse not in curse_instances or curse.state == CurseInstance.State.INDUSTRY:
		return false
	if target.get_curse(curse.get_curse_id()) != null:
		return false
	var universal_love := target.get_curse("universal_love")
	var love_transfer := universal_love != null and universal_love.state == CurseInstance.State.FRUIT and not universal_love.sealed
	if not free_transfer and not love_transfer:
		if run_state == null or not run_state.pay_ritual(1, resolves_overload):
			return false
	curse_instances.erase(curse)
	if sealed_curse_id == curse.get_curse_id():
		sealed_curse_id = ""
		curse.sealed = false
	target.curse_instances.append(curse)
	return true


func process_curse_battle_result(victory: bool) -> Array[CurseInstance]:
	var transformed: Array[CurseInstance] = []
	if not victory:
		return transformed
	for curse in curse_instances:
		if curse != null and curse.add_maturity(1):
			distortion_progress += 1
			transformed.append(curse)
	return transformed


func commit_curse_state_to(target: CharacterState) -> void:
	if target == null:
		return
	target.curse_instances.clear()
	for curse in curse_instances:
		if curse != null:
			target.curse_instances.append(curse.duplicate(true) as CurseInstance)
	target.base_curse_load_limit = base_curse_load_limit
	target.curse_load_limit_bonus = curse_load_limit_bonus
	target.sealed_curse_id = sealed_curse_id
	target.distortion_progress = distortion_progress
	target.selected_distortion_fields = selected_distortion_fields.duplicate()
	target.claimed_distortion_milestones = claimed_distortion_milestones.duplicate()
	target.distortion_grace_count = distortion_grace_count
	target.persistent_max_health_modifier = persistent_max_health_modifier
	target.adventure_damage_bonus = adventure_damage_bonus


func _normalize_curses() -> void:
	var seen: Dictionary = {}
	var normalized: Array[CurseInstance] = []
	for curse in curse_instances:
		if curse == null or curse.definition == null or curse.get_curse_id().is_empty():
			continue
		curse.depth = clampi(curse.depth, 1, 3)
		curse.maturity = maxi(0, curse.maturity)
		if seen.has(curse.get_curse_id()):
			var existing := seen[curse.get_curse_id()] as CurseInstance
			if existing != null:
				existing.deepen()
			continue
		seen[curse.get_curse_id()] = curse
		normalized.append(curse)
	curse_instances.assign(normalized)
	if not sealed_curse_id.is_empty():
		var sealed := get_curse(sealed_curse_id)
		if sealed == null or sealed.state == CurseInstance.State.INDUSTRY:
			sealed_curse_id = ""
		else:
			sealed.sealed = true
	_normalize_distortion_state()


func _normalize_distortion_state() -> void:
	var normalized_fields := PackedStringArray()
	for field_id in selected_distortion_fields:
		if (field_id in DistortionCatalog.LOW_FIELDS or field_id in DistortionCatalog.HIGH_FIELDS) \
			and not normalized_fields.has(field_id):
			normalized_fields.append(field_id)
	selected_distortion_fields = normalized_fields
	var normalized_milestones := PackedInt32Array()
	for milestone_index in claimed_distortion_milestones:
		if milestone_index >= 0 and milestone_index < DistortionCatalog.MILESTONES.size() \
			and not normalized_milestones.has(milestone_index):
			normalized_milestones.append(milestone_index)
	normalized_milestones.sort()
	claimed_distortion_milestones = normalized_milestones
	distortion_grace_count = clampi(distortion_grace_count, 0, DistortionCatalog.MILESTONES.size())
