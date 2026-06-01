extends EnemyBehavior
class_name RangedEnemyBehavior

enum State {
	REPOSITION,
	ATTACK,
}

@export var min_preferred_range: float = 180.0
@export var max_preferred_range: float = 260.0
@export var state: int = State.REPOSITION

func choose_action(context: Dictionary = {}, enemy_state = null) -> Dictionary:
	var controller = context.get("controller")
	var unit = enemy_state
	if controller == null or unit == null:
		return {}

	while unit.current_ap > 0 and unit.is_alive():
		var target := controller.get_nearest_opponent(unit)
		if target == null:
			break

		var distance := unit.distance_to(target)
		if distance < min_preferred_range or distance > max_preferred_range:
			state = State.REPOSITION
			if not _move_to_preferred_range(controller, unit, target, distance):
				break
			continue

		state = State.ATTACK
		var card := controller.find_playable_card_against(unit, target)
		if card != null:
			if not controller.play_card(unit, card, [target]):
				break
			continue

		if not controller.basic_attack(unit, target):
			break

	return {"state": state}


func _move_to_preferred_range(controller: BattleController, unit: BattleUnitState, target: BattleUnitState, distance: float) -> bool:
	var direction := unit.position - target.position
	if direction.length() <= 0.001:
		direction = Vector2.RIGHT
	else:
		direction = direction.normalized()

	var desired_surface_distance := max_preferred_range
	if distance > max_preferred_range:
		direction = -direction
		desired_surface_distance = max_preferred_range
	elif distance < min_preferred_range:
		desired_surface_distance = max_preferred_range

	var desired_center_distance := unit.radius + target.radius + desired_surface_distance
	var desired_position := target.position + direction * desired_center_distance
	var max_move := unit.current_ap * unit.get_move_distance_per_ap(controller.config)

	if unit.position.distance_to(desired_position) > max_move:
		var move_direction := (desired_position - unit.position).normalized()
		desired_position = unit.position + move_direction * max_move

	desired_position = controller.clamp_to_map(desired_position)
	return controller.move_unit_to(unit, desired_position)
