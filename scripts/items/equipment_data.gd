extends ItemData
class_name EquipmentData

@export var equipment_tag: String = "装备"
@export var equipment_tags: PackedStringArray = []

func has_tag(tag: String) -> bool:
	if tag.is_empty():
		return false
	if equipment_tag == tag:
		return true

	return equipment_tags.has(tag)
