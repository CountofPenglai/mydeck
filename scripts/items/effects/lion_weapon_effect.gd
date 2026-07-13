extends EquipmentEffect
class_name LionWeaponEffect

@export var inverted_face: bool = false
@export var next_card_damage_bonus: int = 3

const FLIP_AVAILABLE := "lion_flip_available"


func on_switched_in(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	if not inverted_face:
		runtime.set_flag(FLIP_AVAILABLE, true)


func on_after_strike(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	runtime.set_flag(FLIP_AVAILABLE, false)
	if not inverted_face:
		owner.gain_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE, 1)
		return
	owner.gain_armor(int(context.get("actual_damage", 0)), context)
	if owner.character_state != null:
		owner.character_state.weapon_face = 0


func has_activated_action(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	if owner == null or owner.character_state == null:
		return false
	if inverted_face:
		return owner.character_state.weapon_face == 1
	return owner.character_state.weapon_face == 0 and runtime.get_flag(FLIP_AVAILABLE)


func get_action_label(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> String:
	if inverted_face:
		return "备战 1：下一张牌伤害加值 +%d" % next_card_damage_bonus
	return "倒转为翼狮咆哮"


func get_action_momentum_cost(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> int:
	return 1 if inverted_face else 0


func activate(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	if inverted_face:
		owner.gain_next_card_damage_bonus(next_card_damage_bonus)
		return true
	if owner.character_state == null or not owner.character_state.switch_equipment_face("weapon"):
		return false
	runtime.set_flag(FLIP_AVAILABLE, false)
	return true
