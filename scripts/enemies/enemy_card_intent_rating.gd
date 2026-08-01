extends Resource
class_name EnemyCardIntentRating

@export_enum("接近", "防御", "攻击", "功能", "施咒", "逃离", "收割") var category: int = EnemyIntentCategory.Type.UTILITY
@export_range(-100, 100, 1) var base_score: int = 10
@export_range(0, 100, 1) var damage_value: int = 0
@export_range(0, 100, 1) var defense_value: int = 0
@export_range(0, 100, 1) var healing_value: int = 0
@export_range(0, 20, 1) var draw_value: int = 0
@export_range(0, 20, 1) var movement_value: int = 0
@export_range(0, 20, 1) var control_value: int = 0
@export_range(0, 20, 1) var curse_value: int = 0
@export_range(0, 20, 1) var utility_value: int = 0
@export var required_tags: PackedStringArray = []
@export var preferred_tags: PackedStringArray = []
@export var provided_tags: PackedStringArray = []
@export_range(-100, 100, 1) var combo_bonus: int = 0
@export var target_preference: int = -1


func is_valid() -> bool:
	return EnemyIntentCategory.is_valid(category)
