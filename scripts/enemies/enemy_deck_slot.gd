extends Resource
class_name EnemyDeckSlot

@export var slot_label: String = "怪物牌"
@export_range(0, 20, 1) var pick_count: int = 1
@export var entries: Array[EnemyCardPoolEntry] = []


func get_valid_entries() -> Array[EnemyCardPoolEntry]:
	var result: Array[EnemyCardPoolEntry] = []
	for entry in entries:
		if entry != null and entry.is_valid():
			result.append(entry)
	return result

