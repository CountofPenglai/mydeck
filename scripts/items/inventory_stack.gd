extends Resource
class_name InventoryStack

@export var item_data: ItemData
@export_range(1, 99, 1) var count: int = 1
@export var stack_id: String = ""


func ensure_stack_id(fallback_id: String) -> String:
	if stack_id.is_empty():
		stack_id = fallback_id
	return stack_id

func get_display_name() -> String:
	if item_data == null:
		return "空物品"

	return "%s x%d" % [item_data.item_name, count]
