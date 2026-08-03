extends Resource
class_name CardEffect

@export var effect_priority: int = 0
@export var uses_strike: bool = false

func can_play(_context: Dictionary = {}) -> bool:
	return true


func can_pay_play_cost(_context: Dictionary = {}) -> bool:
	return true


func pay_play_cost(_context: Dictionary = {}) -> bool:
	return true


func get_valid_targets(_context: Dictionary = {}) -> Array:
	return []


func provides_area_target_cells() -> bool:
	return false


func get_area_target_cells(_context: Dictionary = {}) -> Array[Vector2i]:
	return []


func provides_landing_target_cells() -> bool:
	return false


func get_landing_target_cells(_context: Dictionary = {}, _targets: Array = []) -> Array[Vector2i]:
	return []


func get_target_type_for_mode(_context: Dictionary = {}, _play_mode: int = CardEnums.CardPlayMode.NORMAL, default_target_type: int = CardEnums.TargetType.NONE) -> int:
	return default_target_type


func modify_effective_range(_user, _equipment_slot: String, current_range: int) -> int:
	return current_range


func is_unit_target_allowed(context: Dictionary = {}, target: BattleUnitState = null) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and target != null and target.faction != user.faction


func is_object_target_allowed(_context: Dictionary = {}, target: BattleObjectState = null) -> bool:
	return uses_strike and target != null and target.can_be_damaged()


func play_on_object(context: Dictionary = {}, target: BattleObjectState = null) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if not uses_strike or controller == null or user == null or card == null \
			or target == null or not target.can_be_damaged():
		return
	controller.perform_object_strike_with_modifier(
		user,
		target,
		card,
		0,
		card.card_name,
		str(context.get("equipment_slot", ""))
	)


func are_targets_valid(_context: Dictionary = {}, _targets: Array = [], _write_log: bool = true) -> bool:
	return true


func play(_context: Dictionary = {}, _targets: Array = []) -> void:
	pass


func on_zone_owner_card_ap_cost_paid(_owner: BattleUnitState, _zone_card: CardData, _played_card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_zone_owner_after_card_played(_owner: BattleUnitState, _zone_card: CardData, _played_card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_zone_owner_turn_end(_owner: BattleUnitState, _zone_card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_zone_owner_card_drawn(_owner: BattleUnitState, _zone_card: CardData, _drawn_card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_self_drawn(_owner: BattleUnitState, _card: CardData, _context: Dictionary = {}) -> void:
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


func on_zone_owner_equipment_switched(_owner: BattleUnitState, _zone_card: CardData, _switch_result: Dictionary, _context: Dictionary = {}) -> void:
	pass


func on_zone_owner_armor_changed(_owner: BattleUnitState, _zone_card: CardData, _previous: int, _current: int, _context: Dictionary = {}) -> void:
	pass


func get_zone_owner_damage_reduction(_owner: BattleUnitState, _zone_card: CardData, _context: Dictionary = {}) -> int:
	return 0


func requires_weapon_choice(_context: Dictionary = {}) -> bool:
	return uses_strike


func requires_inventory_weapon_choice(_context: Dictionary = {}) -> bool:
	return false


func get_inventory_weapon_choices(_context: Dictionary = {}) -> Array[EquipmentData]:
	return []


func get_inventory_weapon_choice_prompt(_context: Dictionary = {}) -> String:
	return "选择要切换的武器"


func requires_draw_pile_choice(_context: Dictionary = {}) -> bool:
	return false


func requires_ordered_discard_choice(_context: Dictionary = {}) -> bool:
	return false


func requires_curse_choice(_context: Dictionary = {}) -> bool:
	return false


func get_curse_choice_options(_context: Dictionary = {}) -> Array[CurseInstance]:
	return []


func get_curse_choice_prompt(_context: Dictionary = {}) -> String:
	return "选择一张诅咒"


func requires_ranger_recipe_choice(_context: Dictionary = {}) -> bool:
	return false


func get_ranger_recipe_options(_context: Dictionary = {}) -> Array[Dictionary]:
	return []


func can_activate_from_discard(_context: Dictionary = {}) -> bool:
	return false


func get_discard_action_label(_context: Dictionary = {}) -> String:
	return ""


func activate_from_discard(_context: Dictionary = {}) -> bool:
	return false


func get_ordered_discard_choice_cards(_context: Dictionary = {}) -> Array[CardData]:
	return []


func get_ordered_discard_choice_max_count(_context: Dictionary = {}) -> int:
	return 0


func get_ordered_discard_choice_min_count(_context: Dictionary = {}) -> int:
	return 0


func get_ordered_discard_choice_prompt(_context: Dictionary = {}) -> String:
	return "选择弃牌堆牌"


func can_activate_from_exile(_context: Dictionary = {}) -> bool:
	return false


func get_exile_action_label(_context: Dictionary = {}) -> String:
	return ""


func activate_from_exile(_context: Dictionary = {}) -> void:
	pass


func can_activate_from_enchant(_context: Dictionary = {}) -> bool:
	return false


func get_enchant_action_label(_context: Dictionary = {}) -> String:
	return ""


func activate_from_enchant(_context: Dictionary = {}) -> void:
	pass
