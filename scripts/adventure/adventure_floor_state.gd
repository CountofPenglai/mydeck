extends Resource
class_name AdventureFloorState

@export var floor_index: int = 0
@export var floor_seed: int = 0
@export var grid_size: Vector2i = Vector2i(11, 7)
@export var rooms: Array[AdventureRoomState] = []
@export var current_room_id: String = "r_00"
@export var normal_battle_victories: int = 0
@export var ambush_chance: int = 0
@export var watch_protection: bool = false


func get_room(room_id: String) -> AdventureRoomState:
	for room in rooms:
		if room != null and room.room_id == room_id:
			return room
	return null


func get_room_at(cell: Vector2i) -> AdventureRoomState:
	for room in rooms:
		if room != null and room.cell == cell:
			return room
	return null


func get_current_room() -> AdventureRoomState:
	return get_room(current_room_id)


func get_adjacent_rooms(room_id: String = "") -> Array[AdventureRoomState]:
	var source := get_room(current_room_id if room_id.is_empty() else room_id)
	var result: Array[AdventureRoomState] = []
	if source == null:
		return result
	for neighbor_id in source.neighbor_ids:
		var neighbor := get_room(neighbor_id)
		if neighbor != null:
			result.append(neighbor)
	return result


func are_connected(first_id: String, second_id: String) -> bool:
	var first := get_room(first_id)
	return first != null and first.neighbor_ids.has(second_id)


func graph_distance(first_id: String, second_id: String) -> int:
	if first_id == second_id:
		return 0
	var pending: Array[String] = [first_id]
	var distances := {first_id: 0}
	while not pending.is_empty():
		var room_id: String = pending.pop_front()
		var room := get_room(room_id)
		if room == null:
			continue
		for neighbor_id in room.neighbor_ids:
			if distances.has(neighbor_id):
				continue
			var distance := int(distances[room_id]) + 1
			if neighbor_id == second_id:
				return distance
			distances[neighbor_id] = distance
			pending.append(neighbor_id)
	return -1


func to_dict() -> Dictionary:
	var room_data: Array[Dictionary] = []
	for room in rooms:
		if room != null:
			room_data.append(room.to_dict())
	return {
		"floor_index": floor_index,
		"floor_seed": floor_seed,
		"grid_size": [grid_size.x, grid_size.y],
		"rooms": room_data,
		"current_room_id": current_room_id,
		"normal_battle_victories": normal_battle_victories,
		"ambush_chance": ambush_chance,
		"watch_protection": watch_protection,
	}


static func from_dict(data: Dictionary) -> AdventureFloorState:
	var result := AdventureFloorState.new()
	result.floor_index = int(data.get("floor_index", 0))
	result.floor_seed = int(data.get("floor_seed", 0))
	var grid_data: Array = data.get("grid_size", [11, 7]) as Array
	if grid_data.size() >= 2:
		result.grid_size = Vector2i(int(grid_data[0]), int(grid_data[1]))
	for room_data in data.get("rooms", []):
		if room_data is Dictionary:
			result.rooms.append(AdventureRoomState.from_dict(room_data))
	result.current_room_id = str(data.get("current_room_id", "r_00"))
	result.normal_battle_victories = int(data.get("normal_battle_victories", 0))
	result.ambush_chance = int(data.get("ambush_chance", 0))
	result.watch_protection = bool(data.get("watch_protection", false))
	return result
