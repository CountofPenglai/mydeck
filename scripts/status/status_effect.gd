extends Resource
class_name StatusEffect

@export var status_id: String = ""
@export var display_name: String = ""
@export var effect_priority: int = 0
@export_range(0, 99, 1) var stacks: int = 1

func add_stacks(amount: int) -> void:
	stacks = maxi(0, stacks + amount)


func on_turn_start(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	pass


func on_before_damage(_unit: BattleUnitState, _damage_context: DamageContext) -> void:
	pass


func get_damage_bonus(_unit: BattleUnitState, _context: Dictionary = {}) -> int:
	return 0


func get_damage_reduction(_unit: BattleUnitState, _context: Dictionary = {}) -> int:
	return 0


func get_strike_power_bonus(_unit: BattleUnitState, _context: Dictionary = {}) -> int:
	return 0


func modify_card_ap_cost(_unit: BattleUnitState, _card: CardData, current_cost: int, _context: Dictionary = {}) -> int:
	return current_cost


func on_card_ap_cost_paid(_unit: BattleUnitState, _card: CardData, _context: Dictionary = {}) -> void:
	pass


func modify_move_distance_per_ap(_unit: BattleUnitState, current_distance: float, _context: Dictionary = {}) -> float:
	return current_distance


func modify_move_ap_cost(_unit: BattleUnitState, current_cost: int, _context: Dictionary = {}) -> int:
	return current_cost


func on_move_ap_cost_paid(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	pass


func on_turn_end(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	pass


func should_remove() -> bool:
	return stacks <= 0
