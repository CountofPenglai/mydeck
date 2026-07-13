extends StatusEffect
class_name RangerGainMultiplierStatus

enum GainKind {
	HEALING,
	ARMOR,
}

@export var gain_kind: int = GainKind.HEALING
@export var multiplier: float = 0.5
var remaining_turn_ends: int = 1


func _init() -> void:
	status_id = "ranger_gain_multiplier"
	display_name = "恢复受阻"


func modify_healing_received(_unit: BattleUnitState, current_amount: int, _context: Dictionary = {}) -> int:
	if gain_kind != GainKind.HEALING:
		return current_amount
	return floori(float(current_amount) * multiplier)


func modify_armor_gain(_unit: BattleUnitState, current_amount: int, _context: Dictionary = {}) -> int:
	if gain_kind != GainKind.ARMOR:
		return current_amount
	return floori(float(current_amount) * multiplier)


func on_turn_end(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	remaining_turn_ends -= 1
	if remaining_turn_ends <= 0:
		stacks = 0
