extends Resource
class_name StatusEffect

@export var status_id: String = ""
@export var display_name: String = ""
@export var effect_priority: int = 0
@export_range(0, 99, 1) var stacks: int = 1

func add_stacks(amount: int) -> void:
	stacks = maxi(0, stacks + amount)


func on_turn_start(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	pass


func should_remove() -> bool:
	return stacks <= 0
