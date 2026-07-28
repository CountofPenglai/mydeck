extends RefCounted
class_name CharacterAttributeRules

const ATTRIBUTE_POINTS_PER_DAMAGE_BONUS := 2


static func get_damage_bonus(attribute_value: int) -> int:
	var normalized_value := maxi(0, attribute_value)
	return floori(float(normalized_value) / float(ATTRIBUTE_POINTS_PER_DAMAGE_BONUS))
