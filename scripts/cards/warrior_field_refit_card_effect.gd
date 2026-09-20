extends CardEffect
class_name WarriorFieldRefitCardEffect

@export_range(1, 99, 1) var draw_count: int = 1


func can_play(context: Dictionary = {}) -> bool:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	return controller != null and controller.can_switch_prepared_weapon(user)


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	if controller == null or user == null or not bool(controller.switch_prepared_weapon(user).get("success", false)):
		return
	user.draw_cards(draw_count, controller.rng, context)
