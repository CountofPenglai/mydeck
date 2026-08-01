extends Resource
class_name EnemyCardPoolEntry

enum TargetPreference {
	NEAREST,
	LOWEST_HEALTH,
	HIGHEST_HEALTH,
	MOST_CLUSTERED,
	SELF,
	ALLY,
	OPPONENT,
}

@export var card: CardData
@export_range(1, 100, 1) var weight: int = 1
@export_range(1, 9, 1) var max_copies: int = 1
@export_range(-100, 100, 1) var base_score: int = 10
@export var target_preference: int = TargetPreference.NEAREST
@export var required_tags: PackedStringArray = []
@export var provided_tags: PackedStringArray = []
@export var combo_bonus: int = 0
@export var card_key: StringName
@export var intent_ratings: Array[EnemyCardIntentRating] = []


func is_valid() -> bool:
	return card != null and weight > 0 and max_copies > 0


func matches_card(candidate: CardData) -> bool:
	if card == null or candidate == null:
		return false
	if candidate == card:
		return true
	var expected_key := card_key if not card_key.is_empty() else StringName(card.card_name)
	return not expected_key.is_empty() and expected_key == StringName(candidate.card_name)


func get_intent_rating(category: int) -> EnemyCardIntentRating:
	for rating in intent_ratings:
		if rating != null and rating.category == category:
			return rating
	return null
