extends EquipmentEffect
class_name MountainCleaverEffect


func on_turn_start(owner: BattleUnitState, _root: EquipmentData, _component: EquipmentData, _runtime: EquipmentRuntimeState, context: Dictionary = {}) -> void:
	if owner == null:
		return
	var controller := context.get("controller") as BattleController
	if owner.consume_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE, 1):
		if controller != null:
			controller._emit_log("%s 为砍山刀支付了 1 点势。" % owner.get_display_name())
		return
	if controller != null:
		controller.switch_weapon_from_inventory(owner)
