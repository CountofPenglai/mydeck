extends RefCounted
class_name BattleRangeTargetQuery

var source: BattleUnitState
var origin: Vector2 = Vector2.ZERO
var origin_radius: float = 0.0
var range_distance: float = 0.0
var unit_filter: int = BattleController.UnitFilter.OPPONENTS
var sort_by_distance: bool = true


static func create_from_source(new_source: BattleUnitState, new_range_distance: float, new_filter: int = BattleController.UnitFilter.OPPONENTS) -> BattleRangeTargetQuery:
	var query := BattleRangeTargetQuery.new()
	query.source = new_source
	if new_source != null:
		query.origin = new_source.position
		query.origin_radius = new_source.radius
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
		if get_surface_distance_to(unit) <= range_distance + 0.001:
			result.append(unit)

	if sort_by_distance:
		result.sort_custom(func(a: BattleUnitState, b: BattleUnitState) -> bool:
			return get_surface_distance_to(a) < get_surface_distance_to(b)
		)

	return result


func get_surface_distance_to(unit: BattleUnitState) -> float:
	if unit == null:
		return INF

	return maxf(0.0, origin.distance_to(unit.position) - origin_radius - unit.radius)
