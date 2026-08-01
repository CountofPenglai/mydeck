extends StatusEffect
class_name EnemyTurnDamageBonusStatus


func _init() -> void:
	status_id = "enemy_turn_damage_bonus"
	display_name = "本回合伤害加值"


func get_damage_bonus(_unit: BattleUnitState, _context: Dictionary = {}) -> int:
	return stacks


func on_turn_end(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	stacks = 0
