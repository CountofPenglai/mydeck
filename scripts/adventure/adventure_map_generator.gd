extends RefCounted
class_name AdventureMapGenerator

const COLUMN_COUNT := 8


func generate(run_seed: int, floor_index: int, definition: AdventureDefinition = null) -> AdventureFloorState:
	var resolved_definition := definition if definition != null else AdventureDefinition.new()
	var target_count := _target_room_count(resolved_definition, run_seed, floor_index)
	var floor := AdventureFloorState.new()
	floor.floor_index = floor_index
	floor.floor_seed = derive_seed(run_seed, "hex_map", floor_index)
	floor.grid_size = Vector2i(COLUMN_COUNT, int(ceili(float(target_count) / float(COLUMN_COUNT))))
	for cell in _build_cells(target_count):
		var room := AdventureRoomState.new()
		room.room_id = "hex_%02d" % floor.rooms.size()
		room.cell = cell
		floor.rooms.append(room)
	var rng := RandomNumberGenerator.new()
	rng.seed = floor.floor_seed
	var start := floor.get_room_at(Vector2i.ZERO)
	var boss := _choose_boss(floor, start, rng)
	var visible_shop := _choose_visible_shop(floor, start, boss, rng)
	if start == null or boss == null or visible_shop == null:
		push_error("Adventure map role candidates did not satisfy the hex-map constraints")
		return floor
	AdventureContentAllocator.assign_roles(floor, start, boss, visible_shop, rng)
	start.visited = true
	start.completed = true
	start.content_revealed = true
	floor.current_room_id = start.room_id
	AdventureEncounterContent.populate(floor)
	return floor


static func derive_seed(base_seed: int, domain: String, index: int = 0) -> int:
	var value := ("%d:%s:%d" % [base_seed, domain, index]).hash()
	return value if value != 0 else 1


func _target_room_count(definition: AdventureDefinition, run_seed: int, floor_index: int) -> int:
	var minimum := mini(definition.min_rooms, definition.max_rooms)
	var maximum := maxi(definition.min_rooms, definition.max_rooms)
	if minimum < 40 or maximum > 55:
		push_error("Adventure map room count must remain within 40-55")
		return 48
	if minimum == maximum:
		return minimum
	var rng := RandomNumberGenerator.new()
	rng.seed = derive_seed(run_seed, "hex_map_size", floor_index)
	return rng.randi_range(minimum, maximum)


func _build_cells(target_count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for index in range(target_count):
		cells.append(Vector2i(index % COLUMN_COUNT, index / COLUMN_COUNT))
	return cells


func _choose_boss(floor: AdventureFloorState, start: AdventureRoomState, rng: RandomNumberGenerator) -> AdventureRoomState:
	var far_corner := Vector2i(COLUMN_COUNT - 1, floor.grid_size.y - 1)
	var candidates: Array[AdventureRoomState] = []
	for room in floor.rooms:
		var route_distance := AdventureHexGeometry.distance(start.cell, room.cell)
		if AdventureHexGeometry.distance(room.cell, far_corner) <= 1 and route_distance >= 8 and route_distance <= 12:
			candidates.append(room)
	if candidates.is_empty():
		push_error("No boss candidate satisfies the far-corner and route constraints")
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _choose_visible_shop(floor: AdventureFloorState, start: AdventureRoomState, boss: AdventureRoomState, rng: RandomNumberGenerator) -> AdventureRoomState:
	var center := Vector2i(COLUMN_COUNT / 2, floor.grid_size.y / 2)
	var candidates: Array[AdventureRoomState] = []
	for room in floor.rooms:
		if room != start and room != boss and AdventureHexGeometry.distance(room.cell, center) <= 1:
			candidates.append(room)
	if candidates.is_empty():
		push_error("No visible-shop candidate satisfies the central-area constraint")
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]
