extends RefCounted
class_name EquipmentRuntimeState

var equipment: EquipmentData
var counters: Dictionary = {}
var flags: Dictionary = {}
var data: Dictionary = {}


func get_counter(key: String, default_value: int = 0) -> int:
	return int(counters.get(key, default_value))


func set_counter(key: String, value: int) -> void:
	counters[key] = value


func add_counter(key: String, amount: int, maximum: int = -1) -> int:
	var value := maxi(0, get_counter(key) + amount)
	if maximum >= 0:
		value = mini(value, maximum)
	set_counter(key, value)
	return value


func get_flag(key: String, default_value: bool = false) -> bool:
	return bool(flags.get(key, default_value))


func set_flag(key: String, value: bool) -> void:
	flags[key] = value


func get_data(key: String, default_value: Variant = null) -> Variant:
	return data.get(key, default_value)


func set_data(key: String, value: Variant) -> void:
	data[key] = value
