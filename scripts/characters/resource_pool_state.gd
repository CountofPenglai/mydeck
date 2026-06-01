extends Resource
class_name ResourcePoolState

@export var pool_data: ResourcePoolData
@export var current_value: int = 0

func setup(data: ResourcePoolData) -> void:
	pool_data = data
	current_value = get_max_value()
	if pool_data != null:
		current_value = pool_data.clamped_initial_value()


func get_resource_name() -> String:
	if pool_data == null:
		return "资源"

	return pool_data.pool_name


func get_max_value() -> int:
	if pool_data == null:
		return 0

	return pool_data.max_value


func get_display_text() -> String:
	return "%s：%d/%d" % [get_resource_name(), current_value, get_max_value()]
