extends StatusEffect
class_name RangerTurnDamageBonusStatus


func _init() -> void:
	status_id = "ranger_turn_damage_bonus"
	display_name = "连击伤害加值"


func get_damage_bonus(_unit: BattleUnitState, _context: Dictionary = {}) -> int:
	return stacks


func on_turn_end(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	stacks = 0
