extends StatusEffect
class_name OneShotDamageBonusStatus

@export var bonus_amount: int = 2


func _init() -> void:
	status_id = "one_shot_damage_bonus"
	display_name = "一次性伤害加值"


func get_damage_bonus(unit: BattleUnitState, context: Dictionary = {}) -> int:
	if unit == null or stacks <= 0:
		return 0

	if bool(context.get("consume_one_shot_damage_bonus", false)):
		stacks = maxi(0, stacks - 1)

	return bonus_amount
