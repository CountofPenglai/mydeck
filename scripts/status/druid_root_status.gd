extends StatusEffect
class_name DruidRootStatus


func _init() -> void:
	status_id = "druid_root"
	display_name = "根系"
	stacks = 1


func add_stacks(_amount: int) -> void:
	stacks = 1
