extends Node

var exit_code := 0


func _ready() -> void:
	_test_required_48_cell_contract()
	_test_validator_rejects_invalid_shape_positions_and_content()
	if exit_code != 0:
		print("ADVENTURE_HEX_MAP_CHECK: FAIL")
		get_tree().quit(exit_code)
		return
	_test_generated_maps_are_valid_for_all_sizes_and_chapters()
	if exit_code == 0:
		print("ADVENTURE_HEX_MAP_CHECK: PASS")
	else:
		print("ADVENTURE_HEX_MAP_CHECK: FAIL")
	get_tree().quit(exit_code)


func _test_required_48_cell_contract() -> void:
	var definition := AdventureDefinition.new()
	definition.min_rooms = 48
	definition.max_rooms = 48
	var floor := AdventureMapGenerator.new().generate(20260921, 0, definition)
	_expect(floor.rooms.size() == 48, "48-cell definition must generate exactly 48 rooms")
	_expect(AdventureMapValidator.validate(floor).is_empty(), "48-cell floor must satisfy the hex-map validator")
	_expect(floor.rooms.size() >= 2 and floor.rooms[0] != floor.rooms[1], "each room must be a distinct state object")
	var clone := AdventureFloorState.from_dict(floor.to_dict())
	if clone.rooms.is_empty() or floor.rooms.is_empty():
		_fail("room serialization must retain rooms")
		return
	clone.rooms[0].content_revealed = not floor.rooms[0].content_revealed
	_expect(clone.rooms[0].content_revealed != floor.rooms[0].content_revealed, "floor serialization must deep-copy room state")


func _test_generated_maps_are_valid_for_all_sizes_and_chapters() -> void:
	var seed_bounds := _seed_bounds()
	for target_size in range(40, 56):
		for floor_index in [0, 1]:
			for seed_offset in range(seed_bounds.x, seed_bounds.y):
				var definition := AdventureDefinition.new()
				definition.min_rooms = target_size
				definition.max_rooms = target_size
				var floor := AdventureMapGenerator.new().generate(20260921 + seed_offset, floor_index, definition)
				_expect(floor.rooms.size() == target_size, "%d-cell floor %d seed %d has an exact room count" % [target_size, floor_index, seed_offset])
				_expect(AdventureMapValidator.validate(floor).is_empty(), "%d-cell floor %d seed %d validates" % [target_size, floor_index, seed_offset])
				_expect(_has_unique_ids_and_cells(floor), "%d-cell floor %d seed %d has unique IDs and cells" % [target_size, floor_index, seed_offset])
				_expect(_is_fully_connected(floor), "%d-cell floor %d seed %d is fully connected" % [target_size, floor_index, seed_offset])
				_expect(_count_actual_shops(floor) == 2, "%d-cell floor %d seed %d has two shops" % [target_size, floor_index, seed_offset])
				_expect(_count_high_value(floor) >= 3, "%d-cell floor %d seed %d has at least three high-value rooms" % [target_size, floor_index, seed_offset])


func _test_validator_rejects_invalid_shape_positions_and_content() -> void:
	var definition := AdventureDefinition.new()
	definition.min_rooms = 48
	definition.max_rooms = 48
	var floor := AdventureMapGenerator.new().generate(20260921, 0, definition)

	var invalid_shape := AdventureFloorState.from_dict(floor.to_dict())
	invalid_shape.grid_size = Vector2i(7, invalid_shape.grid_size.y)
	_expect(not AdventureMapValidator.validate(invalid_shape).is_empty(), "validator must reject a non-eight-column shape")

	var invalid_start := AdventureFloorState.from_dict(floor.to_dict())
	var start := _room_with_back(invalid_start, AdventureEnums.BackType.START)
	var adjacent := invalid_start.get_room_at(Vector2i(0, 1))
	_swap_cells(start, adjacent)
	_expect(not AdventureMapValidator.validate(invalid_start).is_empty(), "validator must reject a start outside cell 0,0")

	var invalid_boss := AdventureFloorState.from_dict(floor.to_dict())
	var boss := _room_with_back(invalid_boss, AdventureEnums.BackType.BOSS)
	var near_start := invalid_boss.get_room_at(Vector2i(1, 0))
	_swap_cells(boss, near_start)
	_expect(not AdventureMapValidator.validate(invalid_boss).is_empty(), "validator must reject a boss outside the diagonal candidate area")

	var invalid_shop := AdventureFloorState.from_dict(floor.to_dict())
	var visible_shop := _room_with_back(invalid_shop, AdventureEnums.BackType.SHOP)
	var edge_room := invalid_shop.get_room_at(Vector2i(0, 1))
	_swap_cells(visible_shop, edge_room)
	_expect(not AdventureMapValidator.validate(invalid_shop).is_empty(), "validator must reject a visible shop outside the central candidate area")

	var invalid_content := AdventureFloorState.from_dict(floor.to_dict())
	var hidden_shop := _hidden_shop(invalid_content)
	hidden_shop.content_id = "shop_visible"
	_expect(not AdventureMapValidator.validate(invalid_content).is_empty(), "validator must reject a hidden shop with visible-shop content")

	var invalid_back_type := AdventureFloorState.from_dict(floor.to_dict())
	var mystery := _room_with_back(invalid_back_type, AdventureEnums.BackType.MYSTERY)
	mystery.room_type = AdventureEnums.RoomType.ELITE_BATTLE
	_expect(not AdventureMapValidator.validate(invalid_back_type).is_empty(), "validator must reject a mystery with an incompatible actual type")


func _has_unique_ids_and_cells(floor: AdventureFloorState) -> bool:
	var ids := {}
	var cells := {}
	for room in floor.rooms:
		if room == null or room.room_id.is_empty() or ids.has(room.room_id) or cells.has(room.cell):
			return false
		ids[room.room_id] = true
		cells[room.cell] = true
	return true


func _is_fully_connected(floor: AdventureFloorState) -> bool:
	if floor.rooms.is_empty():
		return false
	var first_id := floor.rooms[0].room_id
	for room in floor.rooms:
		if floor.graph_distance(first_id, room.room_id) < 0:
			return false
	return true


func _count_actual_shops(floor: AdventureFloorState) -> int:
	var count := 0
	for room in floor.rooms:
		if room.room_type == AdventureEnums.RoomType.SHOP:
			count += 1
	return count


func _count_high_value(floor: AdventureFloorState) -> int:
	var count := 0
	for room in floor.rooms:
		if room.high_value:
			count += 1
	return count


func _room_with_back(floor: AdventureFloorState, back_type: int) -> AdventureRoomState:
	for room in floor.rooms:
		if room.back_type == back_type:
			return room
	return null


func _hidden_shop(floor: AdventureFloorState) -> AdventureRoomState:
	for room in floor.rooms:
		if room.back_type == AdventureEnums.BackType.MYSTERY and room.room_type == AdventureEnums.RoomType.SHOP:
			return room
	return null


func _swap_cells(first: AdventureRoomState, second: AdventureRoomState) -> void:
	var cell := first.cell
	first.cell = second.cell
	second.cell = cell


func _seed_bounds() -> Vector2i:
	var start := 0
	var end := 100
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed-start="):
			start = int(argument.trim_prefix("--seed-start="))
		elif argument.begins_with("--seed-end="):
			end = int(argument.trim_prefix("--seed-end="))
	return Vector2i(clampi(start, 0, 100), clampi(end, start, 100))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	exit_code = 1
	push_error("ADVENTURE_HEX_MAP_CHECK: %s" % message)
