extends RefCounted
class_name BattlePathfinder

const BattleHexGrid = preload("res://scripts/battle/battle_hex_grid.gd")
const BattleSurfaceState = preload("res://scripts/battle/battle_surface_state.gd")


static func find_path(map_data: BattleMapData, surfaces: BattleSurfaceState, start: Vector2i, goal: Vector2i, is_clear: Callable, ignore_elemental_surface_penalties: bool = false) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if map_data == null or not map_data.is_valid_cell(start) or not map_data.is_valid_cell(goal):
		return empty
	if start == goal:
		return [start]
	var frontier: Array[Vector2i] = [start]
	var costs: Dictionary = {start: 0}
	var came_from: Dictionary = {}
	while not frontier.is_empty():
		var current := _take_lowest(frontier, costs)
		if current == goal:
			break
		if current != start and surfaces != null and surfaces.stops_movement_on_entry(current) and not ignore_elemental_surface_penalties:
			continue
		for neighbor in BattleHexGrid.neighbors(current):
			if not map_data.is_valid_cell(neighbor):
				continue
			if is_clear.is_valid() and not bool(is_clear.call(neighbor)):
				continue
			var step_cost := _movement_cost(surfaces, neighbor, ignore_elemental_surface_penalties)
			var next_cost := int(costs.get(current, 0)) + step_cost
			if costs.has(neighbor) and int(costs[neighbor]) <= next_cost:
				continue
			costs[neighbor] = next_cost
			came_from[neighbor] = current
			if not frontier.has(neighbor):
				frontier.append(neighbor)
	if not came_from.has(goal):
		return empty
	var path: Array[Vector2i] = [goal]
	var cursor := goal
	while cursor != start:
		cursor = came_from[cursor]
		path.push_front(cursor)
	return path


static func get_path_cost(path: Array[Vector2i], surfaces: BattleSurfaceState, ignore_elemental_surface_penalties: bool = false) -> int:
	var cost := 0
	for index in range(1, path.size()):
		cost += _movement_cost(surfaces, path[index], ignore_elemental_surface_penalties)
	return cost


static func find_reachable_costs(map_data: BattleMapData, surfaces: BattleSurfaceState, start: Vector2i, is_clear: Callable, ignore_elemental_surface_penalties: bool = false) -> Dictionary:
	var costs: Dictionary = {}
	if map_data == null or not map_data.is_valid_cell(start):
		return costs
	var pending: Array[Vector2i] = [start]
	var pending_index := 0
	costs[start] = 0
	while pending_index < pending.size():
		var current := pending[pending_index]
		pending_index += 1
		if current != start and surfaces != null and surfaces.stops_movement_on_entry(current) and not ignore_elemental_surface_penalties:
			continue
		for neighbor in BattleHexGrid.neighbors(current):
			if not map_data.is_valid_cell(neighbor):
				continue
			if is_clear.is_valid() and not bool(is_clear.call(neighbor)):
				continue
			var step_cost := _movement_cost(surfaces, neighbor, ignore_elemental_surface_penalties)
			var next_cost := int(costs[current]) + step_cost
			if costs.has(neighbor) and int(costs[neighbor]) <= next_cost:
				continue
			costs[neighbor] = next_cost
			pending.append(neighbor)
	return costs


static func _take_lowest(frontier: Array[Vector2i], costs: Dictionary) -> Vector2i:
	var best_index := 0
	var best_cost := int(costs.get(frontier[0], 2147483647))
	for index in range(1, frontier.size()):
		var candidate_cost := int(costs.get(frontier[index], 2147483647))
		if candidate_cost < best_cost:
			best_index = index
			best_cost = candidate_cost
	return frontier.pop_at(best_index)


static func _movement_cost(surfaces: BattleSurfaceState, cell: Vector2i, ignore_elemental_surface_penalties: bool) -> int:
	if surfaces == null:
		return 1
	if ignore_elemental_surface_penalties and surfaces.get_ground_effect(cell) == BattleSurfaceState.Element.POISON_BOG:
		return 1
	return surfaces.get_movement_cost(cell)
