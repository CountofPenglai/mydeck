extends EquipmentEffect
class_name ClockworkGearEffect

@export var maximum_dynamic_bonus: int = 2

const LAST_STRIKE_TURN := "clockwork_last_strike_turn"
const PREPARE_AVAILABLE := "clockwork_prepare_available"


func get_damage_bonus(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, context: Dictionary = {}) -> int:
	var controller := context.get("controller") as BattleController
	if controller == null or controller.current_unit != owner:
		return 0
	return mini(maximum_dynamic_bonus, owner.get_class_resource_value(BattleController.WARRIOR_MOMENTUM_RESOURCE))


func get_damage_reduction(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, context: Dictionary = {}) -> int:
	var controller := context.get("controller") as BattleController
	if controller != null and controller.current_unit == owner:
		return 0
	return mini(maximum_dynamic_bonus, owner.get_class_resource_value(BattleController.WARRIOR_MOMENTUM_RESOURCE))


func on_switched_in(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	runtime.set_flag(PREPARE_AVAILABLE, true)


func on_after_strike(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	if runtime.get_counter(LAST_STRIKE_TURN, -1) == owner.turn_serial:
		return
	runtime.set_counter(LAST_STRIKE_TURN, owner.turn_serial)
	owner.gain_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE, 1)


func on_before_switch_out(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	owner.gain_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE, 1)


func has_activated_action(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	return runtime.get_flag(PREPARE_AVAILABLE)


func get_action_label(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> String:
	return "备战 1（每次切入限一次）：下一张牌 AP -1"


func get_action_momentum_cost(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> int:
	return 1


func activate(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	if not runtime.get_flag(PREPARE_AVAILABLE):
		return false
	runtime.set_flag(PREPARE_AVAILABLE, false)
	var discount := NextCardApDiscountStatus.new()
	discount.stacks = 1
	owner.add_status(discount)
	return true
