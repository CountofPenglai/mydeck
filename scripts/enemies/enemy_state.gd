extends Resource
class_name EnemyState

@export var enemy_data: EnemyData
@export var current_health: int = -1
@export_range(1, 99, 1) var level: int = 1
@export var deck: Array[CardStack] = []
@export var extra_ap_bonus: int = 0
@export var strength_bonus: int = 0
@export var agility_bonus: int = 0
@export var intelligence_bonus: int = 0
@export var flat_damage_bonus: int = 0
@export var damage_reduction: int = 0
const MAX_HEALTH_PER_STRENGTH := 3
const HEALTH_GROWTH_PER_STRENGTH_LEVEL := 1
const DAMAGE_PER_ATTRIBUTE := 1

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

	var level_growth := maxi(0, level - 1) * get_strength() * HEALTH_GROWTH_PER_STRENGTH_LEVEL
	return enemy_data.base_max_health + get_strength() * MAX_HEALTH_PER_STRENGTH + level_growth


func get_attack() -> int:
	var profile := build_strike_profile_object()
	return profile.primary_power + profile.damage_bonus


func get_damage_bonus(context: Dictionary = {}) -> int:
	var bonus := flat_damage_bonus
	match _resolve_damage_type(context):
		CardEnums.DamageType.AGILITY:
			bonus += get_agility() * DAMAGE_PER_ATTRIBUTE
		CardEnums.DamageType.INTELLIGENCE:
			bonus += get_intelligence() * DAMAGE_PER_ATTRIBUTE
		_:
			bonus += get_strength() * DAMAGE_PER_ATTRIBUTE

	return bonus


func get_damage_reduction() -> int:
	return maxi(0, damage_reduction)


func build_strike_profile_object(_equipment_slot: String = "", context: Dictionary = {}) -> StrikeProfile:
	var profile := StrikeProfile.new()
	profile.primary_slot = "innate"
	profile.primary_equipment = null
	profile.primary_range_type = EquipmentData.WeaponRangeType.MELEE
	profile.primary_damage_type = _resolve_damage_type(context)
	profile.add_offhand = false
	profile.offhand_equipment = null
	profile.offhand_power = 0
	var power := 1
	var attack_range := 80.0
	if enemy_data != null:
		power = enemy_data.innate_power
		attack_range = enemy_data.base_attack_range

	profile.primary_power = power
	profile.primary_range = attack_range
	var damage_context := context.duplicate()
	damage_context["resolved_damage_type"] = profile.primary_damage_type
	profile.damage_bonus = get_damage_bonus(damage_context)
	return profile


func get_agility() -> int:
	if enemy_data == null:
		return 0

	return enemy_data.base_agility + agility_bonus


func get_strength() -> int:
	if enemy_data == null:
		return 0

	return enemy_data.base_strength + strength_bonus


func get_intelligence() -> int:
	if enemy_data == null:
		return 0

	return enemy_data.base_intelligence + intelligence_bonus


func get_collision_radius() -> float:
	if enemy_data == null:
		return 0.0

	return enemy_data.collision_radius


func get_attack_range(_equipment_slot: String = "") -> float:
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


func _get_context_card(context: Dictionary = {}) -> CardData:
	var card = context.get("card")
	if card is CardData:
		return card as CardData

	var source = context.get("source")
	if source is CardData:
		return source as CardData

	return null


func _resolve_damage_type(context: Dictionary = {}) -> int:
	if context.has("resolved_damage_type"):
		return int(context.get("resolved_damage_type"))

	var card := _get_context_card(context)
	if card != null and card.damage_type != CardEnums.DamageType.WEAPON:
		return card.damage_type
	if enemy_data != null:
		return enemy_data.innate_damage_type

	return CardEnums.DamageType.STRENGTH
