extends RefCounted
class_name AdventureEncounterContent

## Freeze encounters at generation. Traversal, scouting and reloads do not draw.
static func populate(floor: AdventureFloorState) -> void:
	if floor == null or floor.get_current_room() == null:
		return
	var start: AdventureRoomState = null
	for room in floor.rooms:
		if room.room_type == AdventureEnums.RoomType.START:
			start = room
			break
	if start == null:
		return
	var ordered: Array[AdventureRoomState] = floor.rooms.duplicate()
	ordered.sort_custom(func(a: AdventureRoomState, b: AdventureRoomState):
		var da := BattleHexGrid.distance(start.cell, a.cell)
		var db := BattleHexGrid.distance(start.cell, b.cell)
		return a.room_id < b.room_id if da == db else da < db
	)
	var ordinary_index := 0
	for room in ordered:
		var tier := ordinary_tier(ordinary_index)
		var key := "encounter"
		if room.room_type == AdventureEnums.RoomType.NORMAL_BATTLE:
			ordinary_index += 1
		elif room.room_type == AdventureEnums.RoomType.ELITE_BATTLE:
			tier = AdventureEnums.EncounterTier.ELITE
		elif room.room_type == AdventureEnums.RoomType.BOSS_BATTLE:
			tier = AdventureEnums.EncounterTier.BOSS
		elif room.room_type == AdventureEnums.RoomType.EVENT and AdventureEventVariantService.CARD_ONLY_EVENTS.has(room.content_id):
			key = "danger_encounter"
		else:
			continue
		if room.runtime_data.has(key):
			continue
		var seed := AdventureMapGenerator.derive_seed(floor.floor_seed, key, room.room_id.hash())
		var encounter := EnemyCatalogRouter.pick_encounter(EnemyCatalogRouter.chapter_for_floor(floor.floor_index), tier, seed)
		var fixed := encounter.duplicate(true)
		fixed["tier"] = tier
		fixed["seed"] = seed
		room.runtime_data[key] = fixed

static func ordinary_tier(index: int) -> int:
	if index < 2:
		return AdventureEnums.EncounterTier.WEAK
	if index < 4:
		return AdventureEnums.EncounterTier.MIXED
	return AdventureEnums.EncounterTier.STRONG

static func get_encounter(room: AdventureRoomState, dangerous_event: bool = false) -> Dictionary:
	return (room.runtime_data.get("danger_encounter" if dangerous_event else "encounter", {}) as Dictionary).duplicate(true)
