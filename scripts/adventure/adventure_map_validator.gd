extends RefCounted
class_name AdventureMapValidator

const COLUMN_COUNT := 8


static func validate(floor: AdventureFloorState) -> PackedStringArray:
	var errors := PackedStringArray()
	if floor == null:
		errors.append("floor is null")
		return errors
	if floor.rooms.size() < 40 or floor.rooms.size() > 55:
		errors.append("room count outside 40-55")
	_validate_shape(floor, errors)
	var ids := {}
	var cells := {}
	var counts := {}
	var actual_shops := 0
	var hidden_shops := 0
	var high_value := 0
	for room in floor.rooms:
		if room == null:
			errors.append("null room")
			continue
		if room.room_id.is_empty() or ids.has(room.room_id):
			errors.append("duplicate or empty room id")
		ids[room.room_id] = true
		if cells.has(room.cell):
			errors.append("duplicate room cell")
		cells[room.cell] = true
		if room.content_id.is_empty():
			errors.append("room content is not fixed")
		counts[room.back_type] = int(counts.get(room.back_type, 0)) + 1
		if room.room_type == AdventureEnums.RoomType.SHOP:
			actual_shops += 1
			if room.back_type == AdventureEnums.BackType.MYSTERY:
				hidden_shops += 1
		if room.high_value:
			high_value += 1
		_validate_back_and_content(room, errors)
	var quotas := AdventureContentAllocator.back_quotas(floor.rooms.size())
	for back_type in quotas:
		if int(counts.get(back_type, 0)) != int(quotas[back_type]):
			errors.append("back-type quota mismatch")
	if actual_shops != 2 or hidden_shops != 1:
		errors.append("expected one visible and one hidden actual shop")
	if high_value < 3:
		errors.append("expected at least three high-value rooms")
	var start := _single_room(floor, AdventureEnums.BackType.START)
	var boss := _single_room(floor, AdventureEnums.BackType.BOSS)
	var visible_shop := _single_room(floor, AdventureEnums.BackType.SHOP)
	_validate_role_positions(floor, start, boss, visible_shop, errors)
	if start != null and boss != null:
		var route_distance := floor.graph_distance(start.room_id, boss.room_id)
		if route_distance < 8 or route_distance > 12:
			errors.append("start-to-boss distance outside 8-12")
		if not _is_connected(floor, start.room_id):
			errors.append("map is not fully connected")
	if start != null and floor.current_room_id != start.room_id:
		errors.append("current room must start at start")
	return errors


static func _validate_shape(floor: AdventureFloorState, errors: PackedStringArray) -> void:
	var expected_rows := int(ceili(float(floor.rooms.size()) / float(COLUMN_COUNT)))
	if floor.grid_size != Vector2i(COLUMN_COUNT, expected_rows):
		errors.append("shape must be eight columns with calculated rows")
		return
	for index in range(floor.rooms.size()):
		var expected_cell := Vector2i(index % COLUMN_COUNT, index / COLUMN_COUNT)
		if floor.get_room_at(expected_cell) == null:
			errors.append("shape must have contiguous rows and a contiguous final row")
			return


static func _validate_role_positions(floor: AdventureFloorState, start: AdventureRoomState, boss: AdventureRoomState, visible_shop: AdventureRoomState, errors: PackedStringArray) -> void:
	if start == null or boss == null or visible_shop == null:
		errors.append("missing start, boss, or visible shop")
		return
	if start.cell != Vector2i.ZERO:
		errors.append("start must occupy cell 0,0")
	var far_corner := Vector2i(COLUMN_COUNT - 1, floor.grid_size.y - 1)
	if AdventureHexGeometry.distance(boss.cell, far_corner) > 1:
		errors.append("boss must occupy the far-corner candidate area")
	var center := Vector2i(COLUMN_COUNT / 2, floor.grid_size.y / 2)
	if AdventureHexGeometry.distance(visible_shop.cell, center) > 1:
		errors.append("visible shop must occupy the central candidate area")


static func _validate_back_and_content(room: AdventureRoomState, errors: PackedStringArray) -> void:
	match room.back_type:
		AdventureEnums.BackType.START:
			if room.room_type != AdventureEnums.RoomType.START or room.content_id != "start":
				errors.append("start back must match start content")
		AdventureEnums.BackType.BOSS:
			if room.room_type != AdventureEnums.RoomType.BOSS_BATTLE or not room.content_id.begins_with("boss_chapter_"):
				errors.append("boss back must match boss content")
		AdventureEnums.BackType.BATTLE:
			if room.room_type != AdventureEnums.RoomType.NORMAL_BATTLE or not room.content_id.begins_with("normal_chapter_"):
				errors.append("battle back must match normal encounter content")
		AdventureEnums.BackType.ELITE:
			if room.room_type != AdventureEnums.RoomType.ELITE_BATTLE or not room.content_id.begins_with("elite_chapter_"):
				errors.append("elite back must match elite encounter content")
		AdventureEnums.BackType.CAMP:
			if room.room_type != AdventureEnums.RoomType.SHELTER or not room.content_id.begins_with("camp_"):
				errors.append("camp back must match camp content")
		AdventureEnums.BackType.SHOP:
			if room.room_type != AdventureEnums.RoomType.SHOP or room.content_id != "shop_visible":
				errors.append("visible shop back must match visible shop content")
		AdventureEnums.BackType.MYSTERY:
			if room.room_type == AdventureEnums.RoomType.SHOP:
				if room.content_id != "shop_hidden":
					errors.append("hidden shop must retain mystery back and hidden content")
			elif room.room_type == AdventureEnums.RoomType.EVENT:
				if not AdventureContentAllocator.EVENT_CONTENT_IDS.has(room.content_id):
					errors.append("mystery event content is invalid")
			elif room.room_type != AdventureEnums.RoomType.NORMAL_BATTLE or not room.content_id.begins_with("normal_chapter_"):
				errors.append("mystery back has incompatible actual type")
		_:
			errors.append("unknown back type")


static func _single_room(floor: AdventureFloorState, back_type: int) -> AdventureRoomState:
	for room in floor.rooms:
		if room != null and room.back_type == back_type:
			return room
	return null


static func _is_connected(floor: AdventureFloorState, source_id: String) -> bool:
	var visited := {source_id: true}
	var pending: Array[String] = [source_id]
	while not pending.is_empty():
		var current_id: String = pending.pop_front()
		for neighbor in floor.get_adjacent_rooms(current_id):
			if not visited.has(neighbor.room_id):
				visited[neighbor.room_id] = true
				pending.append(neighbor.room_id)
	return visited.size() == floor.rooms.size()
