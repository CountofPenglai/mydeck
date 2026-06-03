extends Resource
class_name CardData

@export_group("Display")
@export var card_name: String = "未命名卡牌"
@export_multiline var description: String = ""
@export var artwork: Texture2D

@export_group("Gameplay")
@export_enum("普通", "稀有", "史诗", "传说") var rarity: int = CardEnums.Rarity.COMMON
@export_enum("中立", "战士", "法师", "游侠", "德鲁伊", "术士") var card_class: int = CardEnums.CardClass.NEUTRAL
@export_enum("无需目标", "单体", "多目标", "指定范围", "自身", "全体") var target_type: int = CardEnums.TargetType.NONE
@export_range(0, 99, 1) var ap_cost: int = 2
@export_enum("标准", "附赠") var play_timing: int = CardEnums.PlayTiming.NORMAL
@export var range_modifier: float = 0.0
@export var override_range: bool = false
@export var card_range: float = 160.0
@export var effect: CardEffect

func can_play(context: Dictionary = {}) -> bool:
	if effect == null:
		return true

	return effect.can_play(context)


func get_valid_targets(context: Dictionary = {}) -> Array:
	if effect == null:
		return []

	return effect.get_valid_targets(context)


func play(context: Dictionary = {}, targets: Array = []) -> void:
	if effect == null:
		return

	effect.play(context, targets)


func requires_weapon_choice(context: Dictionary = {}) -> bool:
	if effect == null:
		return false

	return effect.requires_weapon_choice(context)


func get_rarity_label() -> String:
	return CardEnums.rarity_label(rarity)


func get_class_label() -> String:
	return CardEnums.class_label(card_class)


func get_target_label() -> String:
	return CardEnums.target_label(target_type)


func get_action_label() -> String:
	return CardEnums.action_label(target_type)


func get_play_timing_label() -> String:
	return CardEnums.play_timing_label(play_timing)


func get_effective_range(user = null, weapon_slot: String = "") -> float:
	if override_range:
		return card_range

	var base_range := 0.0
	if user != null and user.has_method("get_attack_range"):
		base_range = user.get_attack_range(weapon_slot)

	return maxf(0.0, base_range + range_modifier)
