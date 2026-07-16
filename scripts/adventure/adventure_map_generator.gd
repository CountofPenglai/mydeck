extends RefCounted
class_name AdventureMapGenerator

const AXIS_Y := 3
const START_CELL := Vector2i(0, AXIS_Y)
const BOSS_CELL := Vector2i(10, AXIS_Y)
const CARDINAL_DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]


func generate(run_seed: int, floor_index: int, definition: AdventureDefinition = null) -> AdventureFloorState:
	var resolved_definition := definition if definition != null else AdventureDefinition.new()
	for attempt in range(100):
		var rng := RandomNumberGenerator.new()
		rng.seed = derive_seed(run_seed, "map", floor_index * 100 + attempt)
		var floor := _generate_attempt(rng, floor_index, resolved_definition)
		if floor != null and validate(floor).is_empty():
			return floor
	return _build_fallback_floor(run_seed, floor_index, resolved_definition)


func validate(floor: AdventureFloorState) -> PackedStringArray:
	var errors := PackedStringArray()
	if floor == null:
		errors.append("floor is null")
		return errors
	if floor.rooms.size() < 18 or floor.rooms.size() > 24:
		errors.append("room count outside 18-24")
	var start := floor.get_room_at(START_CELL)
	var boss := floor.get_room_at(BOSS_CELL)
	if start == null or start.room_type != AdventureEnums.RoomType.START:
		errors.append("missing start room")
	if boss == null or boss.room_type != AdventureEnums.RoomType.BOSS_BATTLE:
		errors.append("missing boss room")
	if start != null and boss != null and floor.graph_distance(start.room_id, boss.room_id) != 10:
		errors.append("start-to-boss shortest path must be 10")
	var counts := {}
	var main_shelters := 0
	var branch_shelters := 0
	var edge_count := 0
	for room in floor.rooms:
		if room == null:
			errors.append("null room")
			continue
		counts[room.room_type] = int(counts.get(room.room_type, 0)) + 1
		edge_count += room.neighbor_ids.size()
		if room.room_type == AdventureEnums.RoomType.SHELTER:
			if room.cell.y == AXIS_Y:
				main_shelters += 1
			else:
				branch_shelters += 1
		for neighbor_id in room.neighbor_ids:
			var neighbor := floor.get_room(neighbor_id)
			if neighbor == null or not neighbor.neighbor_ids.has(room.room_id):
				errors.append("edge is not bidirectional")
		if start != null and floor.graph_distance(start.room_id, room.room_id) < 0:
			errors.append("map is not fully connected")
	edge_count /= 2
	var cycle_count := edge_count - floor.rooms.size() + 1
	if cycle_count < 2 or cycle_count > 3:
		errors.append("expected two or three loop edges")
	if int(counts.get(AdventureEnums.RoomType.ELITE_BATTLE, 0)) != 2:
		errors.append("expected two elite rooms")
	if main_shelters != 1 or branch_shelters != 1:
		errors.append("shelters must be split between axis and branch")
	if boss != null:
		for neighbor_id in boss.neighbor_ids:
			var neighbor := floor.get_room(neighbor_id)
			if neighbor != null and neighbor.room_type == AdventureEnums.RoomType.SHELTER:
				errors.append("boss cannot be adjacent to shelter")
	var elite_rooms: Array[AdventureRoomState] = []
	for room in floor.rooms:
		if room != null and room.room_type == AdventureEnums.RoomType.ELITE_BATTLE:
			elite_rooms.append(room)
	if elite_rooms.size() == 2 and start != null:
		if floor.graph_distance(start.room_id, elite_rooms[0].room_id) < 4 or floor.graph_distance(start.room_id, elite_rooms[1].room_id) < 4:
			errors.append("elite room is too close to start")
		if floor.graph_distance(elite_rooms[0].room_id, elite_rooms[1].room_id) < 3:
			errors.append("elite rooms are too close")
		if elite_rooms[0].cell.y == AXIS_Y and elite_rooms[1].cell.y == AXIS_Y:
			errors.append("at least one elite must be on a branch")
	if int(counts.get(AdventureEnums.RoomType.SHOP, 0)) != 1:
		errors.append("expected one shop")
	if int(counts.get(AdventureEnums.RoomType.NORMAL_BATTLE, 0)) < 7 or int(counts.get(AdventureEnums.RoomType.NORMAL_BATTLE, 0)) > 10:
		errors.append("normal battle quota invalid")
	if int(counts.get(AdventureEnums.RoomType.EVENT, 0)) < 4 or int(counts.get(AdventureEnums.RoomType.EVENT, 0)) > 7:
		errors.append("event quota invalid")
	for x in range(9):
		var all_combat := true
		for offset in range(3):
			var axis_room := floor.get_room_at(Vector2i(x + offset, AXIS_Y))
			if axis_room == null or not axis_room.is_combat_room():
				all_combat = false
				break
		if all_combat:
			errors.append("three consecutive axis combat rooms")
			break
	return errors


static func derive_seed(base_seed: int, domain: String, index: int = 0) -> int:
	var value := ("%d:%s:%d" % [base_seed, domain, index]).hash()
	return value if value != 0 else 1


func _generate_attempt(rng: RandomNumberGenerator, floor_index: int, definition: AdventureDefinition) -> AdventureFloorState:
	var floor := AdventureFloorState.new()
	floor.floor_index = floor_index
	floor.floor_seed = int(rng.seed)
	floor.grid_size = definition.grid_size
	var by_cell := {}
	for x in range(11):
		var room := _create_room(floor.rooms.size(), Vector2i(x, AXIS_Y))
		floor.rooms.append(room)
		by_cell[room.cell] = room
		if x > 0:
			_connect_rooms(floor.rooms[x - 1], room)
	var target_count := rng.randi_range(definition.min_rooms, definition.max_rooms)
	while floor.rooms.size() < target_count:
		var candidates: Array[Dictionary] = []
		for source in floor.rooms:
			if source == null or source.cell in [START_CELL, BOSS_CELL]:
				continue
			if source.cell.y == AXIS_Y and source.cell.x in [1, 9]:
				continue
			for direction in CARDINAL_DIRECTIONS:
				var candidate_cell := source.cell + direction
				if candidate_cell.x < 1 or candidate_cell.x > 9 or candidate_cell.y < 0 or candidate_cell.y >= floor.grid_size.y:
					continue
				if candidate_cell.y == AXIS_Y or by_cell.has(candidate_cell):
					continue
				candidates.append({"source": source, "cell": candidate_cell})
		if candidates.is_empty():
			return null
		var selected: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
		var new_room := _create_room(floor.rooms.size(), selected["cell"] as Vector2i)
		floor.rooms.append(new_room)
		by_cell[new_room.cell] = new_room
		_connect_rooms(selected["source"] as AdventureRoomState, new_room)
	var loop_target := rng.randi_range(definition.loop_edge_min, definition.loop_edge_max)
	_add_safe_loop_edges(floor, by_cell, rng, loop_target)
	if not _assign_room_types(floor, rng):
		return null
	var start := floor.get_room_at(START_CELL)
	start.visited = true
	start.completed = true
	start.content_revealed = true
	floor.current_room_id = start.room_id
	_assign_content_ids(floor, rng)
	return floor


func _create_room(index: int, cell: Vector2i) -> AdventureRoomState:
	var room := AdventureRoomState.new()
	room.room_id = "r_%02d" % index
	room.cell = cell
	return room


func _connect_rooms(first: AdventureRoomState, second: AdventureRoomState) -> void:
	first.connect_to(second.room_id)
	second.connect_to(first.room_id)


func _disconnect_rooms(first: AdventureRoomState, second: AdventureRoomState) -> void:
	var first_index := first.neighbor_ids.find(second.room_id)
	if first_index >= 0:
		first.neighbor_ids.remove_at(first_index)
	var second_index := second.neighbor_ids.find(first.room_id)
	if second_index >= 0:
		second.neighbor_ids.remove_at(second_index)


func _add_safe_loop_edges(floor: AdventureFloorState, by_cell: Dictionary, rng: RandomNumberGenerator, target: int) -> void:
	var candidates: Array[Dictionary] = []
	for room in floor.rooms:
		for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
			var other := by_cell.get(room.cell + direction) as AdventureRoomState
			if other != null and not room.neighbor_ids.has(other.room_id):
				candidates.append({"first": room, "second": other})
	_shuffle(candidates, rng)
	var added := 0
	for candidate in candidates:
		var first := candidate["first"] as AdventureRoomState
		var second := candidate["second"] as AdventureRoomState
		_connect_rooms(first, second)
		var start := floor.get_room_at(START_CELL)
		var boss := floor.get_room_at(BOSS_CELL)
		if floor.graph_distance(start.room_id, boss.room_id) == 10:
			added += 1
			if added >= target:
				return
		else:
			_disconnect_rooms(first, second)


func _assign_room_types(floor: AdventureFloorState, rng: RandomNumberGenerator) -> bool:
	var start := floor.get_room_at(START_CELL)
	var boss := floor.get_room_at(BOSS_CELL)
	start.room_type = AdventureEnums.RoomType.START
	boss.room_type = AdventureEnums.RoomType.BOSS_BATTLE
	var available: Array[AdventureRoomState] = []
	for room in floor.rooms:
		if room != start and room != boss:
			available.append(room)
	var main_candidates: Array[AdventureRoomState] = []
	for room in available:
		if room.cell.y == AXIS_Y and room.cell.x >= 4 and room.cell.x <= 6:
			main_candidates.append(room)
	var main_shelter := _take_random(main_candidates, available, rng)
	var branch_candidates: Array[AdventureRoomState] = []
	for room in available:
		if room.cell.y != AXIS_Y:
			branch_candidates.append(room)
	var branch_shelter := _take_random(branch_candidates, available, rng)
	if main_shelter == null or branch_shelter == null:
		return false
	main_shelter.room_type = AdventureEnums.RoomType.SHELTER
	branch_shelter.room_type = AdventureEnums.RoomType.SHELTER
	main_shelter.shelter_type = rng.randi_range(0, 2)
	branch_shelter.shelter_type = (main_shelter.shelter_type + rng.randi_range(1, 2)) % 3
	var first_elite_candidates: Array[AdventureRoomState] = []
	for room in available:
		if room.cell.y != AXIS_Y and floor.graph_distance(start.room_id, room.room_id) >= 4:
			first_elite_candidates.append(room)
	var first_elite := _take_random(first_elite_candidates, available, rng)
	if first_elite == null:
		return false
	first_elite.room_type = AdventureEnums.RoomType.ELITE_BATTLE
	var second_elite_candidates: Array[AdventureRoomState] = []
	for room in available:
		if floor.graph_distance(start.room_id, room.room_id) >= 4 and floor.graph_distance(first_elite.room_id, room.room_id) >= 3:
			second_elite_candidates.append(room)
	var second_elite := _take_random(second_elite_candidates, available, rng)
	if second_elite == null:
		return false
	second_elite.room_type = AdventureEnums.RoomType.ELITE_BATTLE
	var shop_candidates: Array[AdventureRoomState] = []
	for room in available:
		var distance := floor.graph_distance(start.room_id, room.room_id)
		if distance >= 3 and distance <= 8:
			shop_candidates.append(room)
	var shop := _take_random(shop_candidates, available, rng)
	if shop == null:
		return false
	shop.room_type = AdventureEnums.RoomType.SHOP
	_shuffle(available, rng)
	var normal_count := clampi(floor.rooms.size() - 11, 7, 10)
	for index in range(available.size()):
		available[index].room_type = AdventureEnums.RoomType.NORMAL_BATTLE if index < normal_count else AdventureEnums.RoomType.EVENT
	return not _has_three_axis_combats(floor)


func _take_random(candidates: Array[AdventureRoomState], available: Array[AdventureRoomState], rng: RandomNumberGenerator) -> AdventureRoomState:
	if candidates.is_empty():
		return null
	var selected := candidates[rng.randi_range(0, candidates.size() - 1)]
	available.erase(selected)
	return selected


func _has_three_axis_combats(floor: AdventureFloorState) -> bool:
	for x in range(9):
		var all_combat := true
		for offset in range(3):
			var room := floor.get_room_at(Vector2i(x + offset, AXIS_Y))
			if room == null or not room.is_combat_room():
				all_combat = false
				break
		if all_combat:
			return true
	return false


func _assign_content_ids(floor: AdventureFloorState, rng: RandomNumberGenerator) -> void:
	var event_ids := [
		"hermit_house", "fallen_altar", "adventurer_remains", "the_fall", "cursed_wanderer",
		"sealed_chapel", "wilderness_merchant", "creation_ascetic", "alchemy_lesson",
		"nature_blessing", "trapped_arcanist", "master_forging", "chaos_gate",
	]
	_shuffle(event_ids, rng)
	var event_index := 0
	for room in floor.rooms:
		match room.room_type:
			AdventureEnums.RoomType.EVENT:
				room.content_id = str(event_ids[event_index % event_ids.size()])
				event_index += 1
			AdventureEnums.RoomType.SHELTER:
				room.content_id = "shelter_%d" % room.shelter_type
			AdventureEnums.RoomType.NORMAL_BATTLE:
				room.content_id = "normal_%d" % room.room_id.hash()
			AdventureEnums.RoomType.ELITE_BATTLE:
				room.content_id = "elite_%d" % room.room_id.hash()
			AdventureEnums.RoomType.BOSS_BATTLE:
				room.content_id = "boss_floor_%d" % floor.floor_index


func _build_fallback_floor(run_seed: int, floor_index: int, definition: AdventureDefinition) -> AdventureFloorState:
	var rng := RandomNumberGenerator.new()
	rng.seed = derive_seed(run_seed, "fallback", floor_index)
	var floor := AdventureFloorState.new()
	floor.floor_index = floor_index
	floor.floor_seed = int(rng.seed)
	floor.grid_size = definition.grid_size
	var cells: Array[Vector2i] = []
	for x in range(11):
		cells.append(Vector2i(x, AXIS_Y))
	for x in range(1, 6):
		cells.append(Vector2i(x, AXIS_Y - 1))
	for x in range(5, 9):
		cells.append(Vector2i(x, AXIS_Y + 1))
	for cell in cells:
		floor.rooms.append(_create_room(floor.rooms.size(), cell))
	for index in range(10):
		_connect_rooms(floor.rooms[index], floor.rooms[index + 1])
	for index in range(11, 15):
		_connect_rooms(floor.rooms[index], floor.rooms[index + 1])
	_connect_rooms(floor.get_room_at(Vector2i(1, AXIS_Y)), floor.get_room_at(Vector2i(1, AXIS_Y - 1)))
	_connect_rooms(floor.get_room_at(Vector2i(5, AXIS_Y)), floor.get_room_at(Vector2i(5, AXIS_Y - 1)))
	for index in range(16, 19):
		_connect_rooms(floor.rooms[index], floor.rooms[index + 1])
	_connect_rooms(floor.get_room_at(Vector2i(5, AXIS_Y)), floor.get_room_at(Vector2i(5, AXIS_Y + 1)))
	_connect_rooms(floor.get_room_at(Vector2i(8, AXIS_Y)), floor.get_room_at(Vector2i(8, AXIS_Y + 1)))
	_assign_room_types(floor, rng)
	var start := floor.get_room_at(START_CELL)
	start.visited = true
	start.completed = true
	start.content_revealed = true
	floor.current_room_id = start.room_id
	_assign_content_ids(floor, rng)
	return floor


func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temporary = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary
