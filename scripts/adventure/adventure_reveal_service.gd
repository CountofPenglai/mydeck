extends RefCounted
class_name AdventureRevealService

static func get_candidates(floor: AdventureFloorState, origin_id: String, radius: int) -> Array[String]:
	var result: Array[String] = []
	if floor == null or radius < 0:
		return result
	var origin := floor.get_room(origin_id)
	if origin == null:
		return result
	for room in floor.rooms:
		if room != null and not room.content_revealed and BattleHexGrid.distance(origin.cell, room.cell) <= radius:
			result.append(room.room_id)
	return result

## Validate the complete selection before mutating any room.
static func reveal(floor: AdventureFloorState, ids: Array[String], radius: int = 3, limit: int = 2) -> bool:
	if floor == null or ids.is_empty() or limit < 1 or ids.size() > limit:
		return false
	var legal := get_candidates(floor, floor.current_room_id, radius)
	var unique: Dictionary = {}
	for id in ids:
		if unique.has(id) or not legal.has(id):
			return false
		unique[id] = true
	for id in ids:
		floor.get_room(id).content_revealed = true
	return true
