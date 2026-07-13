extends StatusEffect
class_name DruidTurnDamageBonusStatus


func _init() -> void:
	status_id = "druid_turn_damage_bonus"
	display_name = "血木伤害加值"


func get_damage_bonus(_unit: BattleUnitState, _context: Dictionary = {}) -> int:
	return maxi(0, stacks)


func on_turn_start(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	stacks = 0
