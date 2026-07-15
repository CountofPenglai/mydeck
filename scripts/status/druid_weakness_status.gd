extends StatusEffect
class_name DruidWeaknessStatus

var expires_on_turn_serial: int = -1


func _init() -> void:
	status_id = "druid_weakness"
	display_name = "虚弱"


func get_damage_bonus(unit: BattleUnitState, _context: Dictionary = {}) -> int:
	if unit != null and expires_on_turn_serial >= 0 and unit.turn_serial >= expires_on_turn_serial:
		stacks = 0
		return 0
	return -stacks


func on_turn_start(unit: BattleUnitState, _context: Dictionary = {}) -> void:
	if unit != null and expires_on_turn_serial >= 0 and unit.turn_serial >= expires_on_turn_serial:
		stacks = 0
