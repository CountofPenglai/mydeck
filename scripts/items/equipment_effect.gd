extends Resource
class_name EquipmentEffect

@export var effect_priority: int = 0


func get_damage_bonus(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> int:
	return 0


func get_damage_reduction(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> int:
	return 0


func modify_attribute(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _attribute: String, current_value: int, _context: Dictionary = {}) -> int:
	return current_value


func modify_resonance_cost(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _card: CardData, current_cost: int, _context: Dictionary = {}) -> int:
	return current_cost


func modify_strike_profile(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _profile: StrikeProfile, _context: Dictionary = {}) -> void:
	pass


func modify_outgoing_damage(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _damage_context: DamageContext) -> void:
	pass


func grants_flying(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	return false


func get_alternate_range_origins(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> Array[Vector2i]:
	return []


func get_card_duplicate_targets(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _card: CardData, _targets: Array, _context: Dictionary = {}) -> Array:
	return []


func get_additional_occupied_cells(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> Array[Vector2i]:
	return []


func modify_attack_range(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, current_range: int, _context: Dictionary = {}) -> int:
	return current_range


func modify_move_distance_per_ap(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, current_distance: int, _context: Dictionary = {}) -> int:
	return current_distance


func get_next_move_distance_bonus(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> int:
	return 0


func modify_ranger_element_collection(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, current_amount: int, _context: Dictionary = {}) -> int:
	return current_amount


func modify_ranger_ambush_multiplier(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, current_multiplier: float, _context: Dictionary = {}) -> float:
	return current_multiplier


func can_use_attack_mode(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _equipment_slot: String, _context: Dictionary = {}) -> bool:
	return true


func is_battle_setup_ready(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	return true


func receives_inactive_runtime_event(_event_name: String) -> bool:
	return false


func preserves_block_on_turn_start(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	return false


func get_runtime_summary(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> String:
	return ""


func on_turn_start(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	pass


func on_unit_turn_started(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _started_unit: BattleUnitState, _context: Dictionary = {}) -> void:
	pass


func on_turn_end(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	pass


func on_battle_started(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	pass


func on_card_drawn(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_card_discarded(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_after_strike(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	pass


func on_before_strike(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	pass


func on_movement_completed(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	pass


func on_ranger_combo_milestone(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _threshold: int, _context: Dictionary = {}) -> void:
	pass


func on_ranger_stealth_entered(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	pass


func on_ranger_stealth_cancelled(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	pass


func on_ranger_elements_collected(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _added: int, _context: Dictionary = {}) -> void:
	pass


func on_ranger_payload_completed(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	pass


func consume_preloaded_payload_after_strike(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> int:
	return 0


func on_after_card_played(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _card: CardData, _context: Dictionary = {}) -> void:
	pass


func on_after_damage_dealt(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	pass


func on_after_damage_taken(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	pass


func on_mana_gained(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _amount: int, _context: Dictionary = {}) -> void:
	pass


func on_mana_paid(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _amount: int, _context: Dictionary = {}) -> void:
	pass


func on_druid_form_changed(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _was_transformed: bool, _is_transformed: bool, _context: Dictionary = {}) -> void:
	pass


func try_replace_druid_form_change(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _target_transformed: bool, _context: Dictionary = {}) -> Dictionary:
	return {}


func can_replace_druid_form_change(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _target_transformed: bool, _context: Dictionary = {}) -> bool:
	return false


func on_druid_form_exiting(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _was_transformed: bool, _context: Dictionary = {}) -> void:
	pass


func on_druid_form_change_requested(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _target_transformed: bool, _context: Dictionary = {}) -> void:
	pass


func on_druid_form_entered(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _is_transformed: bool, _context: Dictionary = {}) -> void:
	pass


func modify_druid_card_enters_mana_after_play(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _card: CardData, current_value: bool, _context: Dictionary = {}) -> bool:
	return current_value


func on_before_switch_out(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	pass


func on_switched_out(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	pass


func on_switched_in(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	pass


func has_activated_action(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	return false


func get_activated_actions(owner: BattleUnitState, root: EquipmentData, component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> Array[Dictionary]:
	if str(context.get("phase", "battle")) == "deployment":
		return []
	if not has_activated_action(owner, root, component, runtime, context):
		return []
	return [{
		"action_id": "default",
		"label": get_action_label(owner, root, component, runtime, context),
		"momentum_cost": get_action_momentum_cost(owner, root, component, runtime, context),
		"ap_cost": get_action_ap_cost(owner, root, component, runtime, context),
		"enabled": can_activate(owner, root, component, runtime, context),
	}]


func get_action_label(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> String:
	return ""


func get_action_momentum_cost(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> int:
	return 0


func get_action_ap_cost(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> int:
	return 0


func can_activate(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	return true


func activate(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	return false
