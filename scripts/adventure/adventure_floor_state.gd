extends Resource
class_name AdventureFloorState

@export var floor_index: int = 0
@export var floor_seed: int = 0
@export var grid_size: Vector2i = Vector2i(8, 6)
@export var rooms: Array[AdventureRoomState] = []
@export var current_room_id: String = ""
@export var danger: int = 0
@export var triggered_thresholds: PackedInt32Array = []

@export var normal_battle_victories: int = 0


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
	for neighbor_cell in AdventureHexGeometry.neighbors(source.cell):
		var neighbor := get_room_at(neighbor_cell)
		if neighbor != null:
			result.append(neighbor)
	return result


func are_connected(first_id: String, second_id: String) -> bool:
	var first := get_room(first_id)
	var second := get_room(second_id)
	return first != null and second != null and AdventureHexGeometry.distance(first.cell, second.cell) == 1


func graph_distance(first_id: String, second_id: String) -> int:
	if get_room(first_id) == null or get_room(second_id) == null:
		return -1
	if first_id == second_id:
		return 0
	var distances := {first_id: 0}
	var pending: Array[String] = [first_id]
	while not pending.is_empty():
		var current_id: String = pending.pop_front()
		var next_distance := int(distances[current_id]) + 1
		for neighbor in get_adjacent_rooms(current_id):
			if distances.has(neighbor.room_id):
				continue
			if neighbor.room_id == second_id:
				return next_distance
			distances[neighbor.room_id] = next_distance
			pending.append(neighbor.room_id)
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
		"danger": danger,
		"triggered_thresholds": Array(triggered_thresholds),
		"normal_battle_victories": normal_battle_victories,
	}


static func from_dict(data: Dictionary) -> AdventureFloorState:
	var result := AdventureFloorState.new()
	result.floor_index = int(data.get("floor_index", 0))
	result.floor_seed = int(data.get("floor_seed", 0))
	var grid_data: Array = data.get("grid_size", [8, 6]) as Array
	if grid_data.size() >= 2:
		result.grid_size = Vector2i(int(grid_data[0]), int(grid_data[1]))
	for room_data in data.get("rooms", []):
		if room_data is Dictionary:
			result.rooms.append(AdventureRoomState.from_dict(room_data))
	result.current_room_id = str(data.get("current_room_id", ""))
	result.danger = int(data.get("danger", 0))
	result.triggered_thresholds = PackedInt32Array(data.get("triggered_thresholds", []))
	result.normal_battle_victories = int(data.get("normal_battle_victories", 0))
	return result
