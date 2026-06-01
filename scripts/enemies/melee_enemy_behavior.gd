extends EnemyBehavior
class_name MeleeEnemyBehavior

enum State {
	APPROACH,
	ATTACK,
}

@export var state: int = State.APPROACH

func choose_action(context: Dictionary = {}, enemy_state = null) -> Dictionary:
	var controller = context.get("controller")
	var unit = enemy_state
	if controller == null or unit == null:
		return {}

	while unit.current_ap > 0 and unit.is_alive():
		var target := controller.get_nearest_opponent(unit)
		if target == null:
			break

		var card := controller.find_playable_card_against(unit, target)
		if card != null:
			state = State.ATTACK
			if not controller.play_card(unit, card, [target]):
				break
			continue

		if unit.distance_to(target) <= unit.get_attack_range():
			state = State.ATTACK
			if not controller.basic_attack(unit, target):
				break
			continue

		state = State.APPROACH
		if not _move_toward_attack_range(controller, unit, target):
			break

	return {"state": state}


func _move_toward_attack_range(controller: BattleController, unit: BattleUnitState, target: BattleUnitState) -> bool:
	var direction := target.position - unit.position
	if direction.length() <= 0.001:
		return false

	direction = direction.normalized()
	var desired_center_distance := unit.radius + target.radius + maxf(0.0, unit.get_attack_range() - 4.0)
	var desired_position := target.position - direction * desired_center_distance
	var max_move := unit.current_ap * unit.get_move_distance_per_ap(controller.config)

	if unit.position.distance_to(desired_position) > max_move:
		desired_position = unit.position + direction * max_move

	desired_position = controller.clamp_to_map(desired_position)
	return controller.move_unit_to(unit, desired_position)
