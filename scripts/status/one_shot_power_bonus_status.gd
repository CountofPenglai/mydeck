extends StatusEffect
class_name OneShotPowerBonusStatus

@export var bonus_amount: int = 2


func _init() -> void:
	status_id = "one_shot_power_bonus"
	display_name = "One-shot power bonus"


func get_strike_power_bonus(unit: BattleUnitState, context: Dictionary = {}) -> int:
	if unit == null or stacks <= 0:
		return 0

	if bool(context.get("consume_one_shot_power_bonus", false)):
		stacks = maxi(0, stacks - 1)

	return bonus_amount


func on_turn_end(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	stacks = 0
