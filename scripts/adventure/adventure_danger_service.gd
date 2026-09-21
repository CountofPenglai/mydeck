extends RefCounted
class_name AdventureDangerService

static func bonus_percent(danger: int) -> int:
	if danger >= 24: return 60
	if danger >= 18: return 40
	if danger >= 12: return 20
	if danger >= 6: return 10
	return 0

## Caller persists this mutation together with the triggering travel/restock.
static func advance(floor: AdventureFloorState, excluded_tile_id: String) -> Dictionary:
	var before: int = floor.danger
	floor.danger += 1
	var marked: Array[String] = []
	for threshold in [6, 12]:
		if floor.danger < threshold or floor.triggered_thresholds.has(threshold):
			continue
		floor.triggered_thresholds.append(threshold)
		var candidates: Array[AdventureRoomState] = []
		for room in floor.rooms:
			if room == null or room.room_id == excluded_tile_id or room.content_revealed or room.visited or room.high_value_marked:
				continue
			if room.high_value and room.room_type != AdventureEnums.RoomType.BOSS_BATTLE:
				candidates.append(room)
		candidates.sort_custom(func(a: AdventureRoomState, b: AdventureRoomState): return a.room_id < b.room_id)
		var rng := RandomNumberGenerator.new()
		rng.seed = AdventureMapGenerator.derive_seed(floor.floor_seed, "high_value_marks", threshold)
		var count := 1 if threshold == 6 else 2
		for i in range(mini(count, candidates.size())):
			var chosen: AdventureRoomState = candidates.pop_at(rng.randi_range(0, candidates.size() - 1))
			chosen.high_value_marked = true
			marked.append(chosen.room_id)
	return {"before": before, "after": floor.danger, "marked_ids": marked}
