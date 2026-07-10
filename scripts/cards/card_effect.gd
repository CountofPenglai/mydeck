extends Resource
class_name CardEffect

@export var effect_priority: int = 0
@export var uses_strike: bool = false

func can_play(_context: Dictionary = {}) -> bool:
	return true


func get_valid_targets(_context: Dictionary = {}) -> Array:
	return []


func get_target_type_for_mode(_context: Dictionary = {}, _play_mode: int = CardEnums.CardPlayMode.NORMAL, default_target_type: int = CardEnums.TargetType.NONE) -> int:
	return default_target_type


func are_targets_valid(_context: Dictionary = {}, _targets: Array = [], _write_log: bool = true) -> bool:
	return true


func play(_context: Dictionary = {}, _targets: Array = []) -> void:
	pass


func on_zone_owner_card_ap_cost_paid(_owner: BattleUnitState, _zone_card: CardData, _played_card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_zone_owner_card_drawn(_owner: BattleUnitState, _zone_card: CardData, _drawn_card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_zone_owner_card_discarded(_owner: BattleUnitState, _zone_card: CardData, _discarded_card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_zone_card_entered_special_zone(_owner: BattleUnitState, _zone_card: CardData, _entered_card: CardData, _zone_name: String, _context: Dictionary = {}) -> void:
	pass


func on_zone_owner_after_damage_dealt(_owner: BattleUnitState, _zone_card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_zone_owner_after_damage_taken(_owner: BattleUnitState, _zone_card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_zone_owner_after_heal_given(_owner: BattleUnitState, _zone_card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_zone_owner_after_heal_received(_owner: BattleUnitState, _zone_card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_zone_owner_after_strike(_owner: BattleUnitState, _zone_card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_zone_owner_mana_gained(_owner: BattleUnitState, _zone_card: CardData, _amount: int, _context: Dictionary = {}) -> void:
	pass


func requires_weapon_choice(_context: Dictionary = {}) -> bool:
	return uses_strike


func requires_draw_pile_choice(_context: Dictionary = {}) -> bool:
	return false


func requires_ordered_discard_choice(_context: Dictionary = {}) -> bool:
	return false


func get_ordered_discard_choice_cards(_context: Dictionary = {}) -> Array[CardData]:
	return []


func get_ordered_discard_choice_max_count(_context: Dictionary = {}) -> int:
	return 0


func get_ordered_discard_choice_prompt(_context: Dictionary = {}) -> String:
	return "选择弃牌堆牌"


func can_activate_from_exile(_context: Dictionary = {}) -> bool:
	return false


func get_exile_action_label(_context: Dictionary = {}) -> String:
	return ""


func activate_from_exile(_context: Dictionary = {}) -> void:
	pass
