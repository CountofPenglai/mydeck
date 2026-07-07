extends StatusEffect
class_name OneShotDamageBonusStatus

@export var bonus_amount: int = 2


func _init() -> void:
	status_id = "one_shot_damage_bonus"
	display_name = "一次性伤害加值"


func get_damage_bonus(unit: BattleUnitState, context: Dictionary = {}) -> int:
	if unit == null or stacks <= 0:
		return 0

	return bonus_amount


func on_turn_end(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	stacks = 0
