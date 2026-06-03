extends StatusEffect
class_name WeaponSwitchOnBlockStatus

func _init() -> void:
	status_id = "weapon_switch_on_block"
	display_name = "防御架势"


func on_block_spent(unit: BattleUnitState, context: Dictionary = {}) -> void:
	if unit == null or stacks <= 0:
		return

	var controller = context.get("controller")
	if controller != null and controller.has_method("switch_weapon_from_inventory"):
		controller.switch_weapon_from_inventory(unit)

	stacks = 0
