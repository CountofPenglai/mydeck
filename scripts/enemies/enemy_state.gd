extends Resource
class_name EnemyState

@export var enemy_data: EnemyData
@export var current_health: int = -1
@export_range(1, 99, 1) var level: int = 1
@export_range(1, 1000, 1) var max_health_percent: int = 100
@export var fixed_max_health_override: int = -1
@export var danger_bonus_percent: int = 0
@export var danger_damage_bonus_percent: int = 0
@export var danger_snapshot_seed: int = 0
@export var danger_mutation_fields: PackedStringArray = []
@export var deck: Array[CardStack] = []
@export var extra_ap_bonus: int = 0
@export var strength_bonus: int = 0
@export var agility_bonus: int = 0
@export var intelligence_bonus: int = 0
@export var flat_damage_bonus: int = 0
@export var damage_reduction: int = 0
@export var active_weapon_index: int = 0
var runtime_state: Dictionary = {}
var intent_plan := EnemyIntentPlan.new()
var seen_card_names: PackedStringArray = []
const MAX_HEALTH_PER_STRENGTH := 3
const HEALTH_GROWTH_PER_STRENGTH_LEVEL := 1

func ensure_initialized(seed: int = -1) -> void:
	if enemy_data == null:
		return

	if current_health < 0:
		current_health = get_max_health()

	if deck.is_empty():
		generate_deck(seed)
	if intent_plan == null:
		intent_plan = EnemyIntentPlan.new()


func generate_deck(seed: int = -1) -> void:
	deck.clear()

	if enemy_data == null or enemy_data.deck_rule == null:
		return

	deck = enemy_data.deck_rule.generate_deck(seed)


func get_enemy_name() -> String:
	if enemy_data == null:
		return "未绑定敌人"
	if enemy_data.archetype_id == &"hungry_fish" and bool(runtime_state.get("reversed", false)):
		return "逆位鱼人"

	return enemy_data.enemy_name


func get_rank_label() -> String:
	if enemy_data == null:
		return "-"

	return enemy_data.get_rank_label()


func get_max_health() -> int:
	return get_max_health_with_danger(danger_bonus_percent)


## Shared by runtime health and the read-only pre-battle danger assignment.
func get_max_health_with_danger(bonus_percent: int) -> int:
	if enemy_data == null:
		return 0

	var base_health: int
	if runtime_state.has("max_health_override"):
		base_health = int(runtime_state.max_health_override)
	elif fixed_max_health_override > 0:
		base_health = fixed_max_health_override
	else:
		var level_growth := maxi(0, level - 1) * get_strength() * HEALTH_GROWTH_PER_STRENGTH_LEVEL
		base_health = enemy_data.base_max_health + get_strength() * MAX_HEALTH_PER_STRENGTH + level_growth \
			+ int(runtime_state.get("max_health_bonus", 0))
	var scaled := ceili(float(base_health) * float(max_health_percent) * float(100 + bonus_percent) / 10000.0)
	return maxi(1, scaled + int(runtime_state.get("danger_unscaled_health_bonus", 0)))


func get_attack() -> int:
	var profile := build_strike_profile_object()
	return profile.primary_base_damage + profile.primary_damage_bonus


func get_damage_bonus(context: Dictionary = {}) -> int:
	var bonus := flat_damage_bonus
	match _resolve_damage_type(context):
		CardEnums.DamageType.AGILITY:
			bonus += CharacterAttributeRules.get_damage_bonus(get_agility())
		CardEnums.DamageType.INTELLIGENCE:
			bonus += CharacterAttributeRules.get_damage_bonus(get_intelligence())
		_:
			bonus += CharacterAttributeRules.get_damage_bonus(get_strength())

	return bonus


func get_damage_reduction() -> int:
	return maxi(0, damage_reduction)


func build_strike_profile_object(_equipment_slot: String = "", context: Dictionary = {}) -> StrikeProfile:
	var profile := StrikeProfile.new()
	var weapon := get_weapon_for_slot(_equipment_slot)
	profile.primary_slot = "weapon" if _equipment_slot.is_empty() else _equipment_slot
	profile.primary_equipment = weapon
	profile.primary_range_type = EquipmentData.WeaponRangeType.MELEE
	profile.primary_damage_type = _resolve_damage_type(context)
	profile.add_offhand = false
	profile.offhand_equipment = null
	profile.offhand_base_damage = 0
	profile.offhand_damage_bonus = 0
	var base_damage := 1
	var attack_range := 1
	if weapon != null:
		base_damage = weapon.base_damage
		attack_range = weapon.attack_range
		profile.primary_range_type = weapon.range_type
		profile.primary_damage_type = weapon.damage_type
	elif enemy_data != null:
		base_damage = enemy_data.innate_base_damage
		attack_range = enemy_data.base_attack_range
	base_damage = int(runtime_state.get("base_damage_override", base_damage))
	attack_range = int(runtime_state.get("range_override", attack_range))

	profile.primary_base_damage = base_damage
	profile.primary_range = attack_range
	var damage_context := context.duplicate()
	damage_context["resolved_damage_type"] = profile.primary_damage_type
	profile.primary_damage_bonus = get_damage_bonus(damage_context)
	return profile


func get_agility() -> int:
	if enemy_data == null:
		return 0

	return enemy_data.base_agility + agility_bonus


func get_strength() -> int:
	if enemy_data == null:
		return 0

	return int(runtime_state.get("strength_override", enemy_data.base_strength)) + strength_bonus


func get_intelligence() -> int:
	if enemy_data == null:
		return 0

	return int(runtime_state.get("intelligence_override", enemy_data.base_intelligence)) + intelligence_bonus


func get_battle_token_radius() -> float:
	if enemy_data == null:
		return 0.0

	return enemy_data.battle_token_radius


func get_attack_range(_equipment_slot: String = "") -> int:
	var weapon := get_weapon_for_slot(_equipment_slot)
	if weapon != null:
		return int(runtime_state.get("range_override", weapon.attack_range))
	return int(runtime_state.get("range_override", enemy_data.base_attack_range if enemy_data != null else 0))


func get_active_weapon() -> EquipmentData:
	if enemy_data == null:
		return null
	if active_weapon_index == 1 and enemy_data.reserve_weapon_equipment != null:
		return enemy_data.reserve_weapon_equipment
	return enemy_data.weapon_equipment


func get_weapon_for_slot(slot: String) -> EquipmentData:
	if slot == "reserve" and enemy_data != null:
		return enemy_data.reserve_weapon_equipment
	return get_active_weapon()


func can_switch_weapon() -> bool:
	return enemy_data != null and enemy_data.reserve_weapon_equipment != null


func switch_weapon() -> bool:
	if not can_switch_weapon():
		return false
	active_weapon_index = 1 - active_weapon_index
	return true


func get_class_profile() -> int:
	return enemy_data.class_profile if enemy_data != null else CardEnums.CardClass.NEUTRAL


func remember_seen_card(card: CardData) -> void:
	if card != null and not seen_card_names.has(card.card_name):
		seen_card_names.append(card.card_name)


func reset_battle_runtime() -> void:
	active_weapon_index = 0
	runtime_state.clear()
	seen_card_names.clear()
	intent_plan.clear()


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
