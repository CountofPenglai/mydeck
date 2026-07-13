extends EquipmentEffect
class_name CeremonialSwordShieldEffect

@export var next_card_damage_bonus: int = 1


func on_card_drawn(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _card: CardData, _context: Dictionary = {}) -> void:
	owner.gain_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE, 1)


func on_switched_in(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> void:
	var block := BlockStatus.new()
	block.stacks = 1
	owner.add_status(block)


func preserves_block_on_turn_start(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	return true


func has_activated_action(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	return true


func get_action_label(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> String:
	return "备战 1：下一张牌伤害加值 +%d" % next_card_damage_bonus


func get_action_momentum_cost(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> int:
	return 1


func activate(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> bool:
	owner.gain_next_card_damage_bonus(next_card_damage_bonus)
	return true
