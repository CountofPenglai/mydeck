extends Resource
class_name CurseEffect

@export var effect_priority: int = 0


func on_battle_started(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> void:
	pass


func on_draw_phase_before(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> void:
	pass


func on_before_reshuffle(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> void:
	pass


func on_turn_start(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> void:
	pass


func on_action_phase_started(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> void:
	pass


func on_card_drawn(_owner: BattleUnitState, _curse: CurseInstance, _card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_draw_action_completed(_owner: BattleUnitState, _curse: CurseInstance, _drawn_cards: Array[CardData], _context: Dictionary = {}) -> void:
	pass


func on_card_play_submitted(_owner: BattleUnitState, _curse: CurseInstance, _card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_after_card_played(_owner: BattleUnitState, _curse: CurseInstance, _card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_card_discarded(_owner: BattleUnitState, _curse: CurseInstance, _card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_movement_completed(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> void:
	pass


func on_after_damage_dealt(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> void:
	pass


func on_after_damage_taken(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> void:
	pass


func on_after_life_lost(_owner: BattleUnitState, _curse: CurseInstance, _amount: int, _context: Dictionary = {}) -> void:
	pass


func on_kill(_owner: BattleUnitState, _curse: CurseInstance, _target: BattleUnitState, _context: Dictionary = {}) -> void:
	pass


func on_death(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> void:
	pass


func on_turn_end(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> void:
	pass


func on_battle_finished(_owner: BattleUnitState, _curse: CurseInstance, _victory: bool, _context: Dictionary = {}) -> void:
	pass


func modify_healing_received(_owner: BattleUnitState, _curse: CurseInstance, amount: int, _context: Dictionary = {}) -> int:
	return amount


func modify_damage_bonus(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> int:
	return 0


func modify_damage_reduction(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> int:
	return 0


func modify_move_ap_cost(_owner: BattleUnitState, _curse: CurseInstance, current_cost: int, _context: Dictionary = {}) -> int:
	return current_cost


func modify_incoming_damage(_owner: BattleUnitState, _curse: CurseInstance, _damage_context: DamageContext) -> void:
	pass


func get_lethal_health_floor(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> int:
	return 0


func can_be_friendly_target(_owner: BattleUnitState, _curse: CurseInstance, _source: BattleUnitState, _context: Dictionary = {}) -> bool:
	return true


func should_exile_discarded_card(_owner: BattleUnitState, _curse: CurseInstance, _card: CardData, _context: Dictionary = {}) -> bool:
	return false


func can_auto_reshuffle(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> bool:
	return true


func get_alternate_range_origins(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> Array[Vector2i]:
	return []


func should_counter_card(_owner: BattleUnitState, _curse: CurseInstance, _source: BattleUnitState, _card: CardData, _context: Dictionary = {}) -> bool:
	return false


func get_damage_redirect(_owner: BattleUnitState, _curse: CurseInstance, _original_target: BattleUnitState, _context: Dictionary = {}) -> Dictionary:
	return {}


func can_intercept_report(_owner: BattleUnitState, _curse: CurseInstance, _new_owner: BattleUnitState, _incoming: CurseInstance, _context: Dictionary = {}) -> bool:
	return false


func can_use_action_category(_owner: BattleUnitState, _curse: CurseInstance, _category: int, _context: Dictionary = {}) -> bool:
	return true


func on_action_category_used(_owner: BattleUnitState, _curse: CurseInstance, _category: int, _context: Dictionary = {}) -> void:
	pass


func has_pending_choice(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> bool:
	return false


func get_active_actions(_owner: BattleUnitState, _curse: CurseInstance, _context: Dictionary = {}) -> Array[Dictionary]:
	return []


func can_activate_action(_owner: BattleUnitState, _curse: CurseInstance, _action_id: String, _context: Dictionary = {}) -> bool:
	return false


func activate_action(_owner: BattleUnitState, _curse: CurseInstance, _action_id: String, _context: Dictionary = {}) -> bool:
	return false
