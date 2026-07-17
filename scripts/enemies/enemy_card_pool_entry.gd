extends Resource
class_name EnemyCardPoolEntry

enum TargetPreference {
	NEAREST,
	LOWEST_HEALTH,
	HIGHEST_HEALTH,
	MOST_CLUSTERED,
	SELF,
	ALLY,
}

@export var card: CardData
@export_range(1, 100, 1) var weight: int = 1
@export_range(1, 9, 1) var max_copies: int = 1
@export_range(-100, 100, 1) var base_score: int = 10
@export var target_preference: int = TargetPreference.NEAREST
@export var required_tags: PackedStringArray = []
@export var provided_tags: PackedStringArray = []
@export var combo_bonus: int = 0


func is_valid() -> bool:
	return card != null and weight > 0 and max_copies > 0

