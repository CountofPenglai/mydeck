extends Resource
class_name CardData

@export_group("Display")
@export var card_name: String = "未命名卡牌"
@export_multiline var description: String = ""
@export var artwork: Texture2D

@export_group("Gameplay")
@export_enum("普通", "稀有", "史诗", "传说") var rarity: int = CardEnums.Rarity.COMMON
@export_enum("中立", "战士", "法师", "游侠", "德鲁伊", "术士") var card_class: int = CardEnums.CardClass.NEUTRAL
@export_enum("攻击", "技能") var card_type: int = CardEnums.CardType.SKILL
@export_flags("Physical", "Magical") var card_tags: int = 0
@export_enum("力量", "敏捷", "智力", "武器") var damage_type: int = CardEnums.DamageType.STRENGTH
@export_enum("无需目标", "单体", "多目标", "指定范围", "自身", "全体") var target_type: int = CardEnums.TargetType.NONE
@export_range(0, 99, 1) var ap_cost: int = 2
@export_enum("标准", "附赠") var play_timing: int = CardEnums.PlayTiming.NORMAL
@export var range_modifier: float = 0.0
@export var override_range: bool = false
@export var card_range: float = 160.0
@export var effect: CardEffect

@export_group("Special Play")
@export var has_momentum: bool = false
@export var momentum_conditions: Array[Resource] = []
@export var has_combo: bool = false
@export var combo_conditions: Array[Resource] = []

@export_group("Druid")
@export var is_druid_dual_card: bool = false
@export var allow_upright_play: bool = true
@export var allow_inverted_play: bool = true
@export var inverted_name: String = ""
@export_multiline var inverted_description: String = ""
@export_range(0, 99, 1) var inverted_ap_cost: int = 2
@export_enum("无需目标", "单体", "多目标", "指定范围", "自身", "全体") var inverted_target_type: int = CardEnums.TargetType.NONE
@export var inverted_override_range: bool = false
@export var inverted_card_range: float = 160.0
@export var inverted_range_modifier: float = 0.0
@export_range(0, 99, 1) var resonance_cost: int = 0
@export var auto_pay_resonance: bool = true
@export var is_twin_spell: bool = false

func can_play(context: Dictionary = {}) -> bool:
	if effect == null:
		return true

	return effect.can_play(context)


func get_valid_targets(context: Dictionary = {}) -> Array:
	if effect == null:
		return []

	return effect.get_valid_targets(context)


func get_target_type_for_mode(play_mode: int = CardEnums.CardPlayMode.NORMAL, context: Dictionary = {}) -> int:
	if _is_inverted_context(context):
		return inverted_target_type
	if effect == null:
		return target_type

	return effect.get_target_type_for_mode(context, play_mode, target_type)


func is_unit_target_allowed(context: Dictionary = {}, target: BattleUnitState = null) -> bool:
	if effect != null:
		return effect.is_unit_target_allowed(context, target)
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and target != null and target.faction != user.faction


func are_targets_valid(context: Dictionary = {}, targets: Array = [], write_log: bool = true) -> bool:
	if effect == null:
		return true

	return effect.are_targets_valid(context, targets, write_log)


func play(context: Dictionary = {}, targets: Array = []) -> void:
	if effect == null:
		return

	effect.play(context, targets)


func requires_weapon_choice(context: Dictionary = {}) -> bool:
	if effect == null:
		return false

	return effect.requires_weapon_choice(context)


func requires_draw_pile_choice(context: Dictionary = {}) -> bool:
	if effect == null:
		return false

	return effect.requires_draw_pile_choice(context)


func requires_ordered_discard_choice(context: Dictionary = {}) -> bool:
	if effect == null:
		return false

	return effect.requires_ordered_discard_choice(context)


func get_ordered_discard_choice_cards(context: Dictionary = {}) -> Array[CardData]:
	if effect == null:
		return []

	return effect.get_ordered_discard_choice_cards(context)


func get_ordered_discard_choice_max_count(context: Dictionary = {}) -> int:
	if effect == null:
		return 0

	return effect.get_ordered_discard_choice_max_count(context)


func get_ordered_discard_choice_min_count(context: Dictionary = {}) -> int:
	if effect == null:
		return 0

	return effect.get_ordered_discard_choice_min_count(context)


func get_ordered_discard_choice_prompt(context: Dictionary = {}) -> String:
	if effect == null:
		return "选择弃牌堆牌"

	return effect.get_ordered_discard_choice_prompt(context)


func can_activate_from_exile(context: Dictionary = {}) -> bool:
	if effect == null:
		return false

	return effect.can_activate_from_exile(context)


func get_exile_action_label(context: Dictionary = {}) -> String:
	if effect == null:
		return ""

	return effect.get_exile_action_label(context)


func activate_from_exile(context: Dictionary = {}) -> void:
	if effect == null:
		return

	effect.activate_from_exile(context)


func can_activate_from_enchant(context: Dictionary = {}) -> bool:
	if effect == null:
		return false

	return effect.can_activate_from_enchant(context)


func get_enchant_action_label(context: Dictionary = {}) -> String:
	if effect == null:
		return ""

	return effect.get_enchant_action_label(context)


func activate_from_enchant(context: Dictionary = {}) -> void:
	if effect == null:
		return

	effect.activate_from_enchant(context)


func is_attack_card() -> bool:
	return card_type == CardEnums.CardType.ATTACK


func has_card_tag(tag: int) -> bool:
	return (card_tags & tag) != 0


func is_physical_attack() -> bool:
	return is_attack_card() and has_card_tag(CardEnums.CardTag.PHYSICAL)


func is_magical_attack() -> bool:
	return is_attack_card() and has_card_tag(CardEnums.CardTag.MAGICAL)


func supports_play_mode(play_mode: int) -> bool:
	match play_mode:
		CardEnums.CardPlayMode.NORMAL:
			return true
		CardEnums.CardPlayMode.MOMENTUM:
			return has_momentum
		CardEnums.CardPlayMode.COMBO:
			return has_combo
		_:
			return false


func can_pay_special_conditions(context: Dictionary = {}, play_mode: int = CardEnums.CardPlayMode.NORMAL) -> bool:
	for condition in get_special_conditions(play_mode):
		if condition != null and not condition.can_pay(context):
			return false

	return true


func pay_special_conditions(context: Dictionary = {}, play_mode: int = CardEnums.CardPlayMode.NORMAL) -> bool:
	for condition in get_special_conditions(play_mode):
		if condition != null and not condition.pay(context):
			return false

	return true


func get_special_conditions(play_mode: int) -> Array[CardPlayCondition]:
	var source: Array[Resource] = []
	match play_mode:
		CardEnums.CardPlayMode.MOMENTUM:
			source = momentum_conditions
		CardEnums.CardPlayMode.COMBO:
			source = combo_conditions

	var result: Array[CardPlayCondition] = []
	for condition in source:
		if condition is CardPlayCondition:
			result.append(condition)

	return result


func get_special_condition_text(play_mode: int) -> String:
	var parts := PackedStringArray()
	for condition in get_special_conditions(play_mode):
		if condition != null:
			parts.append(condition.get_description())

	if parts.is_empty():
		return "无条件"

	return "，".join(parts)


func get_rarity_label() -> String:
	return CardEnums.rarity_label(rarity)


func get_class_label() -> String:
	return CardEnums.class_label(card_class)


func get_card_type_label() -> String:
	return CardEnums.card_type_label(card_type)


func get_damage_type_label() -> String:
	return CardEnums.damage_type_label(damage_type)


func get_target_label() -> String:
	return CardEnums.target_label(target_type)


func get_action_label() -> String:
	return CardEnums.action_label(target_type)


func get_play_timing_label() -> String:
	return CardEnums.play_timing_label(play_timing)


func get_effective_range(user = null, equipment_slot: String = "") -> float:
	var orientation := _resolve_druid_orientation(user, {})
	if orientation == CardEnums.DruidOrientation.INVERTED:
		if inverted_override_range:
			return inverted_card_range
		var inverted_base_range := 0.0
		if user != null and user.has_method("get_attack_range"):
			inverted_base_range = user.get_attack_range(equipment_slot)
		return maxf(0.0, inverted_base_range + inverted_range_modifier)

	if override_range:
		return card_range

	var base_range := 0.0
	if user != null and user.has_method("get_attack_range"):
		base_range = user.get_attack_range(equipment_slot)

	return maxf(0.0, base_range + range_modifier)


func get_ap_cost_for_context(context: Dictionary = {}) -> int:
	if _is_inverted_context(context):
		return inverted_ap_cost

	return ap_cost


func get_display_name_for_context(context: Dictionary = {}) -> String:
	if _is_inverted_context(context) and not inverted_name.is_empty():
		return inverted_name

	return card_name


func get_description_for_context(context: Dictionary = {}) -> String:
	if _is_inverted_context(context) and not inverted_description.is_empty():
		return inverted_description

	return description


func get_druid_orientation_label(context: Dictionary = {}) -> String:
	return CardEnums.druid_orientation_label(_resolve_druid_orientation(context.get("user"), context))


func _is_inverted_context(context: Dictionary = {}) -> bool:
	return _resolve_druid_orientation(context.get("user"), context) == CardEnums.DruidOrientation.INVERTED


func _resolve_druid_orientation(user = null, context: Dictionary = {}) -> int:
	if context.has("druid_orientation"):
		return int(context.get("druid_orientation"))
	if is_druid_dual_card and user != null and user.has_method("get_druid_card_orientation"):
		return int(user.get_druid_card_orientation(self))

	return CardEnums.DruidOrientation.UPRIGHT
