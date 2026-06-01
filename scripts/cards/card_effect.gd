extends Resource
class_name CardEffect

func can_play(_context: Dictionary = {}) -> bool:
	return true


func get_valid_targets(_context: Dictionary = {}) -> Array:
	return []


func play(_context: Dictionary = {}, _targets: Array = []) -> void:
	pass
