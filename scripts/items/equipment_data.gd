extends ItemData
class_name EquipmentData

enum EquipCategory {
	ONE_HAND,
	TWO_HAND,
	OFF_HAND,
}

enum EquipSlot {
	WEAPON,
	ARMOR,
	ACCESSORY,
}

enum WeaponRangeType {
	MELEE,
	RANGED,
}

enum FaceSwitchMode {
	NONE,
	MANUAL,
	TRIGGERED,
}

@export_group("Combat")
@export var power: int = 1
@export var attack_range: float = 80.0
@export var range_type: int = WeaponRangeType.MELEE
@export_enum("力量", "敏捷", "智力") var damage_type: int = CardEnums.DamageType.STRENGTH
@export var damage_bonus: int = 0
@export var damage_reduction: int = 0

@export_group("Use Rules")
@export_enum("武器", "防具", "饰品") var equip_slot: int = EquipSlot.WEAPON
@export_enum("单手", "双手", "副手") var equip_category: int = EquipCategory.ONE_HAND
@export var allowed_classes: PackedInt32Array = []
@export_enum("普通", "稀有", "史诗", "传说") var rarity: int = CardEnums.Rarity.COMMON

@export_group("Tags")
@export var subcategories: PackedStringArray = []

@export_group("Double Face")
@export var back_face: EquipmentData
@export_enum("无", "手动", "触发") var face_switch_mode: int = FaceSwitchMode.NONE

@export_group("Effects")
@export var passive_effects: Array[Resource] = []
@export var trigger_effects: Array[Resource] = []
@export var activated_effects: Array[Resource] = []

func has_tag(tag: String) -> bool:
	if tag.is_empty():
		return false

	return subcategories.has(tag)


func is_available_to_class(card_class: int) -> bool:
	return allowed_classes.is_empty() or allowed_classes.has(card_class)


func can_equip_main_hand() -> bool:
	return is_weapon()


func can_equip_off_hand() -> bool:
	return is_weapon()


func is_weapon() -> bool:
	return equip_slot == EquipSlot.WEAPON


func is_armor() -> bool:
	return equip_slot == EquipSlot.ARMOR


func is_accessory() -> bool:
	return equip_slot == EquipSlot.ACCESSORY


func is_two_handed() -> bool:
	return equip_category == EquipCategory.TWO_HAND


func has_back_face() -> bool:
	return back_face != null


func get_face(face_index: int) -> EquipmentData:
	if face_index == 1 and back_face != null:
		return back_face

	return self


func can_switch_face() -> bool:
	return back_face != null and face_switch_mode != FaceSwitchMode.NONE


func get_range_type_label() -> String:
	match range_type:
		WeaponRangeType.MELEE:
			return "近战"
		WeaponRangeType.RANGED:
			return "远程"
		_:
			return "未知"


func get_damage_type_label() -> String:
	return CardEnums.damage_type_label(damage_type)


func get_equip_slot_label() -> String:
	match equip_slot:
		EquipSlot.WEAPON:
			return "武器"
		EquipSlot.ARMOR:
			return "防具"
		EquipSlot.ACCESSORY:
			return "饰品"
		_:
			return "未知"


func get_equip_category_label() -> String:
	match equip_category:
		EquipCategory.ONE_HAND:
			return "单手"
		EquipCategory.TWO_HAND:
			return "双手"
		EquipCategory.OFF_HAND:
			return "副手"
		_:
			return "未知"


func get_rarity_label() -> String:
	return CardEnums.rarity_label(rarity)


func get_passive_effects(_context: Dictionary = {}) -> Array[Resource]:
	return passive_effects


func queue_trigger_effects(_context: Dictionary = {}) -> void:
	pass


func activate_effect(_context: Dictionary = {}) -> bool:
	return false
