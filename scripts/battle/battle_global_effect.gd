extends Resource
class_name BattleGlobalEffect

@export var effect_name: String = "未命名全局效果"
@export_multiline var description: String = ""
@export var effect_priority: int = 0

func on_battle_setup(_context: Dictionary = {}) -> void:
	pass


func on_turn_start(_context: Dictionary = {}) -> void:
	pass


func on_turn_end(_context: Dictionary = {}) -> void:
	pass


func get_display_name() -> String:
	return effect_name
