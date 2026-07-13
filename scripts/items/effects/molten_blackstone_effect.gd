extends EquipmentEffect
class_name MoltenBlackstoneEffect

@export var switch_damage_bonus: int = 5
@export var switch_armor: int = 4

const PERMANENT_DAMAGE_BONUS := "molten_permanent_damage_bonus"


func get_runtime_summary(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> String:
	return "永久伤害加值 +%d" % runtime.get_counter(PERMANENT_DAMAGE_BONUS)


func get_damage_bonus(_owner: BattleUnitState, _root: EquipmentData, component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> int:
	return runtime.get_counter(PERMANENT_DAMAGE_BONUS) if context.get("equipment") == component else 0


func get_damage_reduction(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> int:
	return 1


func preserves_block_on_turn_start(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	return true


func on_switched_in(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	runtime.add_counter(PERMANENT_DAMAGE_BONUS, switch_damage_bonus)
	owner.gain_armor(switch_armor, context)


func on_after_strike(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	if runtime.get_counter(PERMANENT_DAMAGE_BONUS) > 0:
		runtime.add_counter(PERMANENT_DAMAGE_BONUS, -1)


func has_activated_action(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	return true


func get_action_label(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> String:
	return "备战 2：获得 1 层抵挡"


func get_action_momentum_cost(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> int:
	return 2


func activate(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	var block := BlockStatus.new()
	block.stacks = 1
	owner.add_status(block)
	return true
