extends RefCounted
class_name AdventureTravelService

## Returns steps excluding the origin. Only the final tile may be unexplored.
static func plan(floor: AdventureFloorState, target_id: String) -> Array[String]:
	var empty: Array[String] = []
	if floor == null or floor.get_current_room() == null or floor.get_room(target_id) == null or target_id == floor.current_room_id:
		return empty
	var pending: Array[String] = [floor.current_room_id]
	var previous: Dictionary = {floor.current_room_id: ""}
	var cursor := 0
	while cursor < pending.size():
		var current := pending[cursor]
		cursor += 1
		for neighbor in floor.get_adjacent_rooms(current):
			if previous.has(neighbor.room_id):
				continue
			if neighbor.room_id != target_id and not neighbor.visited:
				continue
			previous[neighbor.room_id] = current
			if neighbor.room_id == target_id:
				return _reconstruct(previous, floor.current_room_id, target_id)
			pending.append(neighbor.room_id)
	return empty

static func _reconstruct(previous: Dictionary, origin_id: String, target_id: String) -> Array[String]:
	var result: Array[String] = []
	var current := target_id
	while current != origin_id:
		result.push_front(current)
		current = str(previous[current])
	return result
