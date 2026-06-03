extends RefCounted
class_name BattleTargeting

var controller: BattleController


func setup(new_controller: BattleController) -> void:
	controller = new_controller


func get_units_by_filter(source: BattleUnitState, filter: int) -> Array[BattleUnitState]:
	var result: Array[BattleUnitState] = []
	if controller == null or source == null:
		return result

	for unit in controller.units:
		if unit == null or unit == source or not unit.is_deployed or not unit.is_alive():
			continue
		if filter == BattleController.UnitFilter.ALL:
			result.append(unit)
		elif filter == BattleController.UnitFilter.OPPONENTS and unit.faction != source.faction:
			result.append(unit)
		elif filter == BattleController.UnitFilter.ALLIES and unit.faction == source.faction:
			result.append(unit)

	return result


func get_units_in_swept_circle(source: BattleUnitState, start_position: Vector2, end_position: Vector2, sweep_radius: float, filter: int) -> Array[BattleUnitState]:
	var hits: Array[BattleUnitState] = []
	for unit in get_units_by_filter(source, filter):
		var hit_radius := sweep_radius + unit.radius
		if segment_intersects_circle(start_position, end_position, unit.position, hit_radius):
			hits.append(unit)

	hits.sort_custom(func(a: BattleUnitState, b: BattleUnitState) -> bool:
		return path_progress(start_position, end_position, a.position) < path_progress(start_position, end_position, b.position)
	)
	return hits


func is_unit_position_clear(unit: BattleUnitState, position: Vector2, write_log: bool = false) -> bool:
	if controller == null:
		return false
	for other in controller.units:
		if other == unit or not other.is_deployed or not other.is_alive():
			continue
		if position.distance_to(other.position) < unit.radius + other.radius:
			if write_log:
				controller._emit_log("目标位置与 %s 重叠。" % other.get_display_name())
			return false
	return true


func find_clear_endpoint_along_segment(unit: BattleUnitState, start_position: Vector2, end_position: Vector2) -> Vector2:
	if is_unit_position_clear(unit, end_position, false):
		return end_position

	var segment := end_position - start_position
	var length := segment.length()
	if length <= 0.001:
		return start_position

	var direction := segment / length
	var step := maxf(4.0, unit.radius * 0.25)
	var distance := length
	while distance > 0.0:
		distance = maxf(0.0, distance - step)
		var candidate := start_position + direction * distance
		if controller.map_data.contains_map_position(candidate) and is_unit_position_clear(unit, candidate, false):
			return candidate

	return start_position


func segment_intersects_circle(start_position: Vector2, end_position: Vector2, circle_center: Vector2, circle_radius: float) -> bool:
	if start_position.distance_to(circle_center) <= circle_radius:
		return true
	if end_position.distance_to(circle_center) <= circle_radius:
		return true

	var segment := end_position - start_position
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return false

	var t := clampf((circle_center - start_position).dot(segment) / length_squared, 0.0, 1.0)
	var closest := start_position + segment * t
	return closest.distance_to(circle_center) <= circle_radius


func path_progress(start_position: Vector2, end_position: Vector2, point: Vector2) -> float:
	var segment := end_position - start_position
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return 0.0
	return clampf((point - start_position).dot(segment) / length_squared, 0.0, 1.0)

