extends Resource
class_name ResourcePoolData

@export var pool_name: String = "资源"
@export var max_value: int = 0
@export var initial_value: int = 0

func clamped_initial_value() -> int:
	return clampi(initial_value, 0, max_value)
