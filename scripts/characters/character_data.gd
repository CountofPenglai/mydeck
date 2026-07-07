extends Resource
class_name CharacterData

@export_group("Display")
@export var character_name: String = "未命名角色"
@export_enum("中立", "战士", "法师", "游侠", "德鲁伊", "术士") var character_class: int = CardEnums.CardClass.WARRIOR
@export var portrait: Texture2D
@export var battle_sprite: Texture2D

@export_group("Base Stats")
@export var base_max_health: int = 30
@export var base_strength: int = 0
@export var base_agility: int = 5
@export var base_intelligence: int = 0
@export var base_attack_range: float = 70.0
@export var collision_radius: float = 24.0

@export_group("Class Resources")
@export var default_resource_pools: Array[ResourcePoolData] = []

func get_class_label() -> String:
	return CardEnums.class_label(character_class)


func get_resource_pool_definitions() -> Array[ResourcePoolData]:
	if not default_resource_pools.is_empty():
		return default_resource_pools

	return CharacterClassDefaults.get_resource_pools(character_class)
