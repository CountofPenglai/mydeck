extends EquipmentEffect
class_name IronRockPairEffect

@export var switch_damage: int = 3

const LAST_STRIKE_TURN := "iron_rock_last_strike_turn"


func on_switched_in(owner: BattleUnitState, _root: EquipmentData, component: EquipmentData, _runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	if component == null or component != owner.character_state.get_active_main_hand_equipment():
		return
	var controller := context.get("controller") as BattleController
	if controller == null:
		return
	var damage := switch_damage + owner.get_damage_bonus({
		"controller": controller,
		"source": component,
		"equipment": component,
		"resolved_damage_type": CardEnums.DamageType.STRENGTH,
	})
	for target in controller.get_units_in_range(owner, component.attack_range, BattleController.UnitFilter.OPPONENTS):
		controller.apply_damage(owner, target, damage, "斩铁切入")


func on_after_strike(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	runtime.set_counter(LAST_STRIKE_TURN, owner.turn_serial)


func on_turn_end(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	if runtime.get_counter(LAST_STRIKE_TURN, -1) != owner.turn_serial:
		owner.gain_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE, 1)
