extends StatusEffect
class_name RangerNextDaggerMultiplierStatus

@export_range(1.0, 5.0, 0.1) var damage_multiplier: float = 1.5


func _init() -> void:
	status_id = "ranger_next_dagger_multiplier"
	display_name = "交错猎步：匕首强化"


func on_turn_end(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	stacks = 0
