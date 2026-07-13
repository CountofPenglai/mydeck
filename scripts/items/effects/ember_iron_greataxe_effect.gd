extends EquipmentEffect
class_name EmberIronGreataxeEffect

@export var maximum_embers: int = 6

const EMBERS := "embers"


func get_runtime_summary(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _context: Dictionary = {}) -> String:
	return "余烬 %d/%d" % [runtime.get_counter(EMBERS), maximum_embers]


func on_card_discarded(_owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, _card: CardData, _context: Dictionary = {}) -> void:
	runtime.add_counter(EMBERS, 1, maximum_embers)


func on_switched_out(owner: BattleUnitState, root: EquipmentData, _component: EquipmentData, runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	var embers := runtime.get_counter(EMBERS)
	if embers <= 0:
		return
	runtime.set_counter(EMBERS, 0)
	var controller := context.get("controller") as BattleController
	if controller == null:
		return
	controller.enqueue_effect(
		Callable(self, "_resolve_burst"),
		[controller, owner, root, embers],
		effect_priority,
		"烬铁巨斧余烬爆发",
		context
	)


func _resolve_burst(controller: BattleController, owner: BattleUnitState, root: EquipmentData, embers: int) -> void:
	if controller == null or owner == null or embers <= 0:
		return
	var damage := embers + owner.get_damage_bonus({
		"controller": controller,
		"source": root,
		"equipment": root,
		"resolved_damage_type": CardEnums.DamageType.STRENGTH,
	})
	for target in controller.get_units_in_range(owner, root.attack_range, BattleController.UnitFilter.OPPONENTS):
		controller.apply_damage(owner, target, damage, "烬铁巨斧余烬")
	owner.gain_armor(embers, {"controller": controller, "reason": "ember_iron_greataxe"})
