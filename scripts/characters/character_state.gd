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

func ensure_initialized() -> void:
	if character_data == null:
		return

	if main_hand_weapon != null and main_hand_weapon.is_two_handed():
		off_hand_weapon = null

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
	if character_data == null:
		return 0

	var attack := character_data.base_attack
	if main_hand_weapon != null:
		attack += main_hand_weapon.attack_bonus
	if off_hand_weapon != null and not (main_hand_weapon != null and main_hand_weapon.is_two_handed()):
		attack += off_hand_weapon.attack_bonus

	return attack


func get_speed() -> int:
	if character_data == null:
		return 0

	return character_data.base_speed


func get_attack_range() -> float:
	if character_data == null:
		return 0.0

	if main_hand_weapon != null:
		return main_hand_weapon.attack_range

	return character_data.base_attack_range


func has_equipment_tag(tag: String) -> bool:
	if main_hand_weapon != null and main_hand_weapon.has_tag(tag):
		return true
	if off_hand_weapon != null and not (main_hand_weapon != null and main_hand_weapon.is_two_handed()):
		return off_hand_weapon.has_tag(tag)

	return false


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
		return true

	if not weapon.can_equip_main_hand():
		return false

	main_hand_weapon = weapon
	if weapon.is_two_handed():
		off_hand_weapon = null

	return true


func equip_off_hand(weapon: WeaponData) -> bool:
	if weapon == null:
		off_hand_weapon = null
		return true

	if main_hand_weapon != null and main_hand_weapon.is_two_handed():
		return false

	if not weapon.can_equip_off_hand():
		return false

	off_hand_weapon = weapon
	return true


func get_main_hand_label() -> String:
	if main_hand_weapon == null:
		return "主手：无"

	return "主手：%s (+%d)" % [main_hand_weapon.item_name, main_hand_weapon.attack_bonus]


func get_off_hand_label() -> String:
	if main_hand_weapon != null and main_hand_weapon.is_two_handed():
		return "副手：被双手武器占用"

	if off_hand_weapon == null:
		return "副手：无"

	return "副手：%s (+%d)" % [off_hand_weapon.item_name, off_hand_weapon.attack_bonus]
