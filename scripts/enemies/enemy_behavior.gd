extends Resource
class_name EnemyBehavior

@export var behavior_label: String = "未配置"

func on_turn_start(_context: Dictionary = {}, _enemy_state = null) -> void:
	pass


func choose_action(_context: Dictionary = {}, _enemy_state = null) -> Dictionary:
	return {}


func on_turn_end(_context: Dictionary = {}, _enemy_state = null) -> void:
	pass


func lock_intent(_context: Dictionary = {}, _enemy_state = null) -> void:
	pass


func get_display_name() -> String:
	return behavior_label
