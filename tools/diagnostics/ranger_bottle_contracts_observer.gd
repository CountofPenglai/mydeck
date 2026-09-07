extends EquipmentEffect
class_name RangerBottleContractsObserver

var collection_modifier_calls := 0
var collection_notifications := 0
var collected_amount := 0
var after_damage_calls := 0
var after_strike_calls := 0
var weapon_strike_metadata_calls := 0

func modify_ranger_element_collection(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, current_amount: int, _context: Dictionary = {}) -> int:
	collection_modifier_calls += 1
	return current_amount * 2

func modify_outgoing_damage(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, damage_context: DamageContext) -> void:
	if bool(damage_context.metadata.get("strike", false)):
		weapon_strike_metadata_calls += 1

func on_ranger_elements_collected(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, added: int, _context: Dictionary = {}) -> void:
	collection_notifications += 1
	collected_amount += added

func on_after_damage_dealt(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	after_damage_calls += 1

func on_after_strike(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	after_strike_calls += 1
