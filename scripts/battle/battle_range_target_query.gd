extends RefCounted
class_name BattleRangeTargetQuery

const BattleHexGrid = preload("res://scripts/battle/battle_hex_grid.gd")

var source: BattleUnitState
var origin_cell: Vector2i = BattleHexGrid.INVALID_CELL
var range_distance: int = 0
var unit_filter: int = BattleController.UnitFilter.OPPONENTS
var sort_by_distance: bool = true


static func create_from_source(new_source: BattleUnitState, new_range_distance: int, new_filter: int = BattleController.UnitFilter.OPPONENTS) -> BattleRangeTargetQuery:
	var query := BattleRangeTargetQuery.new()
	query.source = new_source
	if new_source != null:
		query.origin_cell = new_source.cell
	query.range_distance = new_range_distance
	query.unit_filter = new_filter
	return query


func find_units(controller: BattleController) -> Array[BattleUnitState]:
	var result: Array[BattleUnitState] = []
	if controller == null or source == null:
		return result

	for unit in controller.get_units_by_filter(source, unit_filter):
		if unit == null or not unit.is_alive() or not unit.is_deployed:
			continue
		if get_cell_distance_to(unit) <= range_distance:
			result.append(unit)

	if sort_by_distance:
		result.sort_custom(func(a: BattleUnitState, b: BattleUnitState) -> bool:
			var distance_a := get_cell_distance_to(a)
			var distance_b := get_cell_distance_to(b)
			if distance_a == distance_b:
				return a.unit_id < b.unit_id
			return distance_a < distance_b
		)

	return result


func get_cell_distance_to(unit: BattleUnitState) -> int:
	if unit == null:
		return 2147483647

	return BattleHexGrid.distance(origin_cell, unit.cell)
