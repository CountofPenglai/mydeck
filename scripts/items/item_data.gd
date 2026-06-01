extends Resource
class_name ItemData

@export_group("Display")
@export var item_name: String = "未命名物品"
@export_multiline var description: String = ""
@export var icon: Texture2D

@export_group("Stack")
@export_range(1, 99, 1) var max_stack: int = 1

func get_display_name() -> String:
	return item_name
