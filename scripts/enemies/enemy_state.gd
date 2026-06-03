extends Resource
class_name EnemyState

@export var enemy_data: EnemyData
@export var current_health: int = -1
@export var deck: Array[CardStack] = []
@export var extra_ap_bonus: int = 0

func ensure_initialized(seed: int = -1) -> void:
	if enemy_data == null:
		return

	if current_health < 0:
		current_health = get_max_health()

	if deck.is_empty():
		generate_deck(seed)


func generate_deck(seed: int = -1) -> void:
	deck.clear()

	if enemy_data == null or enemy_data.deck_rule == null:
		return

	deck = enemy_data.deck_rule.generate_deck(seed)


func get_enemy_name() -> String:
	if enemy_data == null:
		return "未绑定敌人"

	return enemy_data.enemy_name


func get_rank_label() -> String:
	if enemy_data == null:
		return "-"

	return enemy_data.get_rank_label()


func get_max_health() -> int:
	if enemy_data == null:
		return 0

	return enemy_data.base_max_health


func get_attack() -> int:
	var profile := build_strike_profile()
	return int(profile.get("primary_power", 0)) + int(profile.get("damage_bonus", 0))


func get_damage_bonus(_context: Dictionary = {}) -> int:
	return 0


func build_strike_profile(_weapon_slot: String = "", context: Dictionary = {}) -> Dictionary:
	var power := 1
	var attack_range := 80.0
	if enemy_data != null:
		power = enemy_data.innate_power
		attack_range = enemy_data.base_attack_range

	return {
		"primary_slot": "innate",
		"primary_weapon": null,
		"primary_power": power,
		"primary_range": attack_range,
		"primary_weapon_type": WeaponData.WeaponType.MELEE,
		"damage_bonus": get_damage_bonus(context),
		"add_offhand": false,
		"offhand_weapon": null,
		"offhand_power": 0,
	}


func get_agility() -> int:
	if enemy_data == null:
		return 0

	return enemy_data.base_agility


func get_speed() -> int:
	return get_agility()


func get_collision_radius() -> float:
	if enemy_data == null:
		return 0.0

	return enemy_data.collision_radius


func get_attack_range(_weapon_slot: String = "") -> float:
	if enemy_data == null:
		return 0.0

	return enemy_data.base_attack_range


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


func get_behavior_label() -> String:
	if enemy_data == null:
		return "未配置"

	return enemy_data.get_behavior_label()
