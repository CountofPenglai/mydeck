extends Resource
class_name EnemyData

@export_group("Display")
@export var enemy_name: String = "未命名敌人"
@export_enum("爪牙", "普通", "精英", "首领") var enemy_rank: int = EnemyEnums.EnemyRank.NORMAL
@export var portrait: Texture2D
@export var battle_sprite: Texture2D

@export_group("Base Stats")
@export var base_max_health: int = 20
@export var innate_base_damage: int = 3
@export_enum("力量", "敏捷", "智力") var innate_damage_type: int = CardEnums.DamageType.STRENGTH
@export var base_strength: int = 0
@export var base_agility: int = 4
@export var base_intelligence: int = 0
@export_range(0, 12, 1) var base_attack_range: int = 1
@export var battle_token_radius: float = 24.0

@export_group("Deck and Behavior")
@export var deck_rule: EnemyDeckRule
@export var behavior: EnemyBehavior

func get_rank_label() -> String:
	return EnemyEnums.rank_label(enemy_rank)


func get_behavior_label() -> String:
	if behavior == null:
		return "未配置"

	return behavior.get_display_name()
