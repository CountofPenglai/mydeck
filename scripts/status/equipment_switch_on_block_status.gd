extends StatusEffect
class_name EquipmentSwitchOnBlockStatus

func _init() -> void:
	status_id = "equipment_switch_on_block"
	display_name = "防御架势"


func on_block_spent(unit: BattleUnitState, context = null) -> void:
	if unit == null or stacks <= 0:
		return

	var controller = null
	if context is DamageContext:
		controller = context.controller
	elif context is Dictionary:
		controller = context.get("controller")
	if controller != null and controller.has_method("switch_prepared_weapon"):
		controller.switch_prepared_weapon(unit)

	stacks = 0
