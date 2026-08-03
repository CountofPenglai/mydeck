extends EquipmentEffect
class_name MountainCleaverEffect

const STARTUP_USED := "mountain_startup_used"
const BOOST_TURN := "mountain_boost_turn"

@export_range(0, 99, 1) var startup_damage_bonus: int = 2
@export_range(0, 12, 1) var startup_range_bonus: int = 1


func get_damage_bonus(
	owner: BattleUnitState,
	_root: EquipmentData,
	component: EquipmentData,
	runtime: EquipmentRuntimeState,
	context: Dictionary = {}
) -> int:
	if context.get("equipment") != component or not _boost_is_active(owner, runtime):
		return 0
	return startup_damage_bonus


func modify_attack_range(
	owner: BattleUnitState,
	_root: EquipmentData,
	_component: EquipmentData,
	runtime: EquipmentRuntimeState,
	current_range: int,
	_context: Dictionary = {}
) -> int:
	return current_range + startup_range_bonus if _boost_is_active(owner, runtime) else current_range


func on_battle_started(
	_owner: BattleUnitState,
	_root: EquipmentData,
	_component: EquipmentData,
	runtime: EquipmentRuntimeState,
	_context: Dictionary = {}
) -> void:
	_reset_for_switch(runtime)


func on_switched_out(
	_owner: BattleUnitState,
	_root: EquipmentData,
	_component: EquipmentData,
	runtime: EquipmentRuntimeState,
	_context: Dictionary = {}
) -> void:
	_clear_temporary_bonus(runtime)


func on_switched_in(
	_owner: BattleUnitState,
	_root: EquipmentData,
	_component: EquipmentData,
	runtime: EquipmentRuntimeState,
	_context: Dictionary = {}
) -> void:
	_reset_for_switch(runtime)


func has_activated_action(
	_owner: BattleUnitState,
	_root: EquipmentData,
	_component: EquipmentData,
	_runtime: EquipmentRuntimeState,
	_context: Dictionary = {}
) -> bool:
	return true


func get_action_label(
	_owner: BattleUnitState,
	_root: EquipmentData,
	_component: EquipmentData,
	_runtime: EquipmentRuntimeState,
	_context: Dictionary = {}
) -> String:
	return "启动：本回合伤害加值 +%d、范围 +%d" % [startup_damage_bonus, startup_range_bonus]


func can_activate(
	owner: BattleUnitState,
	_root: EquipmentData,
	_component: EquipmentData,
	runtime: EquipmentRuntimeState,
	_context: Dictionary = {}
) -> bool:
	return owner != null and runtime != null and not runtime.get_flag(STARTUP_USED)


func activate(
	owner: BattleUnitState,
	root: EquipmentData,
	component: EquipmentData,
	runtime: EquipmentRuntimeState,
	context: Dictionary = {}
) -> bool:
	if not can_activate(owner, root, component, runtime, context):
		return false
	runtime.set_flag(STARTUP_USED, true)
	runtime.set_counter(BOOST_TURN, owner.turn_serial)
	return true


func get_runtime_summary(
	owner: BattleUnitState,
	_root: EquipmentData,
	_component: EquipmentData,
	runtime: EquipmentRuntimeState,
	_context: Dictionary = {}
) -> String:
	if _boost_is_active(owner, runtime):
		return "砍山刀启动：伤害加值 +%d，范围 +%d（本回合）" % [startup_damage_bonus, startup_range_bonus]
	if runtime != null and runtime.get_flag(STARTUP_USED):
		return "砍山刀启动：已使用（切换后刷新）"
	return ""


func _boost_is_active(owner: BattleUnitState, runtime: EquipmentRuntimeState) -> bool:
	return owner != null and runtime != null and runtime.get_counter(BOOST_TURN, -1) == owner.turn_serial


func _reset_for_switch(runtime: EquipmentRuntimeState) -> void:
	if runtime == null:
		return
	runtime.set_flag(STARTUP_USED, false)
	_clear_temporary_bonus(runtime)


func _clear_temporary_bonus(runtime: EquipmentRuntimeState) -> void:
	if runtime != null:
		runtime.set_counter(BOOST_TURN, -1)
