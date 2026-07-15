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


func get_units_along_hex_line(source: BattleUnitState, start_cell: Vector2i, end_cell: Vector2i, filter: int) -> Array[BattleUnitState]:
	var hits: Array[BattleUnitState] = []
	if controller == null or controller.map_data == null:
		return hits
	var path := controller.map_data.get_line(start_cell, end_cell)
	for unit in get_units_by_filter(source, filter):
		for path_cell in path:
			if path_cell == unit.cell:
				hits.append(unit)
				break
	hits.sort_custom(func(a: BattleUnitState, b: BattleUnitState) -> bool:
		return _path_index(path, a.cell) < _path_index(path, b.cell)
	)
	return hits


func get_units_in_range(source: BattleUnitState, range_distance: int, filter: int) -> Array[BattleUnitState]:
	var query := BattleRangeTargetQuery.create_from_source(source, range_distance, filter)
	return query.find_units(controller)


func get_units_in_attack_range(source: BattleUnitState, range_bonus: int = 0, filter: int = BattleController.UnitFilter.OPPONENTS, equipment_slot: String = "") -> Array[BattleUnitState]:
	if source == null:
		return []
	var result: Array[BattleUnitState] = []
	var attack_range := maxi(0, source.get_attack_range(equipment_slot) + range_bonus)
	for unit in get_units_by_filter(source, filter):
		if source.get_range_distance_to(unit, {"controller": controller, "equipment_slot": equipment_slot}) <= attack_range:
			result.append(unit)
	result.sort_custom(func(a: BattleUnitState, b: BattleUnitState) -> bool:
		var left := source.get_range_distance_to(a, {"controller": controller, "equipment_slot": equipment_slot})
		var right := source.get_range_distance_to(b, {"controller": controller, "equipment_slot": equipment_slot})
		return left < right or (left == right and a.unit_id < b.unit_id)
	)
	return result


func is_unit_cell_clear(unit: BattleUnitState, target_cell: Vector2i, write_log: bool = false) -> bool:
	if controller == null or controller.map_data == null:
		return false
	if unit != null and target_cell != unit.cell and unit.get_occupied_cells().has(target_cell):
		if write_log:
			controller._emit_log("目标格已被自身的另一身体占据。")
		return false
	for other in controller.units:
		if other == unit or not other.is_deployed or not other.is_alive():
			continue
		if other.get_occupied_cells().has(target_cell):
			if write_log:
				controller._emit_log("目标格已被 %s 占据。" % other.get_display_name())
			return false
	return true


func is_unit_inside_map_bounds(unit: BattleUnitState, cell: Vector2i, write_log: bool = false) -> bool:
	if controller == null or controller.map_data == null or unit == null:
		return false
	if controller.map_data.is_valid_cell(cell):
		return true
	if write_log:
		controller._emit_log("目标格超出地图边界。")
	return false


func find_clear_endpoint_along_hex_line(unit: BattleUnitState, start_cell: Vector2i, end_cell: Vector2i) -> Vector2i:
	if controller == null or controller.map_data == null:
		return start_cell
	var path := controller.map_data.get_line(start_cell, end_cell)
	path.reverse()
	for cell in path:
		if is_unit_cell_clear(unit, cell, false):
			return cell
	return start_cell


func _path_index(path: Array[Vector2i], cell: Vector2i) -> int:
	var index := path.find(cell)
	return index if index >= 0 else 2147483647
