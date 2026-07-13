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


func modify_incoming_damage(_unit: BattleUnitState, _damage_context: DamageContext) -> void:
	pass


func get_damage_bonus(_unit: BattleUnitState, _context: Dictionary = {}) -> int:
	return 0


func get_damage_reduction(_unit: BattleUnitState, _context: Dictionary = {}) -> int:
	return 0


func modify_card_ap_cost(_unit: BattleUnitState, _card: CardData, current_cost: int, _context: Dictionary = {}) -> int:
	return current_cost


func on_card_ap_cost_paid(_unit: BattleUnitState, _card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_card_drawn(_unit: BattleUnitState, _card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_card_discarded(_unit: BattleUnitState, _card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_card_entered_special_zone(_unit: BattleUnitState, _card: CardData, _zone_name: String, _context: Dictionary = {}) -> void:
	pass


func on_after_damage_dealt(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	pass


func on_after_damage_taken(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	pass


func on_after_heal_given(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	pass


func on_after_heal_received(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	pass


func on_after_strike(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	pass


func on_mana_gained(_unit: BattleUnitState, _amount: int, _context: Dictionary = {}) -> void:
	pass


func on_armor_changed(_unit: BattleUnitState, _previous: int, _current: int, _context: Dictionary = {}) -> void:
	pass


func modify_move_distance_per_ap(_unit: BattleUnitState, current_distance: int, _context: Dictionary = {}) -> int:
	return current_distance


func modify_move_ap_cost(_unit: BattleUnitState, current_cost: int, _context: Dictionary = {}) -> int:
	return current_cost


func on_move_ap_cost_paid(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	pass


func on_turn_end(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	pass


func should_remove() -> bool:
	return stacks <= 0
