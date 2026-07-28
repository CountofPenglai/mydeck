extends StatusEffect
class_name RangerBurnStatus

@export_range(1, 99, 1) var damage_per_turn: int = 1
@export_range(1, 9, 1) var remaining_turns: int = 2


func _init() -> void:
	status_id = "ranger_burn"
	is_corruptible_counter = true
	display_name = "灼烧"


func on_turn_start(unit: BattleUnitState, context: Dictionary = {}) -> void:
	if unit == null or remaining_turns <= 0:
		stacks = 0
		return
	var controller: BattleController = context.get("controller") as BattleController
	if controller != null:
		controller.apply_damage(null, unit, damage_per_turn, "灼烧", {"environmental": true})
	remaining_turns -= 1
	if remaining_turns <= 0:
		stacks = 0
