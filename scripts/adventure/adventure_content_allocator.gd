extends RefCounted
class_name AdventureContentAllocator

const BASE_BACK_QUOTAS := {
	AdventureEnums.BackType.BATTLE: 18,
	AdventureEnums.BackType.ELITE: 5,
	AdventureEnums.BackType.CAMP: 5,
	AdventureEnums.BackType.MYSTERY: 17,
}
const EVENT_CONTENT_IDS := [
	"fallen_altar",
	"hermit_house",
	"adventurer_remains",
	"the_fall",
	"cursed_wanderer",
	"sealed_chapel",
	"creation_ascetic",
	"alchemy_lesson",
	"nature_blessing",
	"trapped_arcanist",
	"master_forging",
	"chaos_gate",
]


static func back_quotas(room_count: int) -> Dictionary:
	var quotas := {
		AdventureEnums.BackType.START: 1,
		AdventureEnums.BackType.BOSS: 1,
		AdventureEnums.BackType.SHOP: 1,
	}
	var remaining := room_count - 3
	var assigned := 0
	var fractions: Array[Dictionary] = []
	for back_type in BASE_BACK_QUOTAS:
		var exact := float(int(BASE_BACK_QUOTAS[back_type])) * float(remaining) / 45.0
		var count := int(floori(exact))
		quotas[back_type] = count
		assigned += count
		fractions.append({"type": back_type, "fraction": exact - float(count)})
	while assigned < remaining:
		fractions.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
			if is_equal_approx(float(first["fraction"]), float(second["fraction"])):
				return int(first["type"]) < int(second["type"])
			return float(first["fraction"]) > float(second["fraction"])
		)
		var selected_type := int(fractions[0]["type"])
		quotas[selected_type] = int(quotas[selected_type]) + 1
		assigned += 1
	return quotas


static func assign_roles(floor: AdventureFloorState, start: AdventureRoomState, boss: AdventureRoomState, visible_shop: AdventureRoomState, rng: RandomNumberGenerator) -> void:
	var quotas := back_quotas(floor.rooms.size())
	_set_role(start, AdventureEnums.BackType.START)
	_set_role(boss, AdventureEnums.BackType.BOSS)
	_set_role(visible_shop, AdventureEnums.BackType.SHOP)
	var available: Array[AdventureRoomState] = []
	for room in floor.rooms:
		if room != start and room != boss and room != visible_shop:
			available.append(room)
	_take_rooms(available, int(quotas[AdventureEnums.BackType.BATTLE]), AdventureEnums.BackType.BATTLE, rng)
	_take_rooms(available, int(quotas[AdventureEnums.BackType.ELITE]), AdventureEnums.BackType.ELITE, rng)
	_take_rooms(available, int(quotas[AdventureEnums.BackType.CAMP]), AdventureEnums.BackType.CAMP, rng)
	for room in available:
		_set_role(room, AdventureEnums.BackType.MYSTERY)
	_assign_hidden_types(floor, rng)
	_assign_fixed_content(floor, rng)


static func _take_rooms(available: Array[AdventureRoomState], count: int, back_type: int, rng: RandomNumberGenerator) -> void:
	var selected: Array[AdventureRoomState] = []
	for ignored in range(count):
		var candidates: Array[AdventureRoomState] = available.duplicate()
		_shuffle(candidates, rng)
		var choice: AdventureRoomState = candidates[0]
		for candidate in candidates:
			var separated := true
			for prior in selected:
				if AdventureHexGeometry.distance(candidate.cell, prior.cell) < 2:
					separated = false
					break
			if separated:
				choice = candidate
				break
		available.erase(choice)
		selected.append(choice)
		_set_role(choice, back_type)


static func _set_role(room: AdventureRoomState, back_type: int) -> void:
	room.back_type = back_type
	room.high_value = false
	match back_type:
		AdventureEnums.BackType.START:
			room.room_type = AdventureEnums.RoomType.START
		AdventureEnums.BackType.BATTLE:
			room.room_type = AdventureEnums.RoomType.NORMAL_BATTLE
		AdventureEnums.BackType.ELITE:
			room.room_type = AdventureEnums.RoomType.ELITE_BATTLE
			room.high_value = true
		AdventureEnums.BackType.CAMP:
			room.room_type = AdventureEnums.RoomType.SHELTER
		AdventureEnums.BackType.SHOP:
			room.room_type = AdventureEnums.RoomType.SHOP
			room.high_value = true
		AdventureEnums.BackType.BOSS:
			room.room_type = AdventureEnums.RoomType.BOSS_BATTLE
		_:
			room.room_type = AdventureEnums.RoomType.EVENT


static func _assign_hidden_types(floor: AdventureFloorState, rng: RandomNumberGenerator) -> void:
	var mysteries: Array[AdventureRoomState] = []
	for room in floor.rooms:
		if room.back_type == AdventureEnums.BackType.MYSTERY:
			mysteries.append(room)
	_shuffle(mysteries, rng)
	var hidden_shop: AdventureRoomState = mysteries.pop_back()
	hidden_shop.room_type = AdventureEnums.RoomType.SHOP
	hidden_shop.high_value = true
	var event_count := int(roundi(float(mysteries.size()) * 0.75))
	for index in range(mysteries.size()):
		mysteries[index].room_type = AdventureEnums.RoomType.EVENT if index < event_count else AdventureEnums.RoomType.NORMAL_BATTLE


static func _assign_fixed_content(floor: AdventureFloorState, rng: RandomNumberGenerator) -> void:
	var event_ids := EVENT_CONTENT_IDS.duplicate()
	_shuffle(event_ids, rng)
	var event_index := 0
	var camp_index := 0
	for room in floor.rooms:
		match room.room_type:
			AdventureEnums.RoomType.START:
				room.content_id = "start"
			AdventureEnums.RoomType.BOSS_BATTLE:
				room.content_id = "boss_chapter_%d" % floor.floor_index
			AdventureEnums.RoomType.NORMAL_BATTLE:
				room.content_id = "normal_chapter_%d_%s" % [floor.floor_index, room.room_id]
			AdventureEnums.RoomType.ELITE_BATTLE:
				room.content_id = "elite_chapter_%d_%s" % [floor.floor_index, room.room_id]
			AdventureEnums.RoomType.SHELTER:
				room.shelter_type = camp_index % 3
				room.content_id = "camp_%d" % room.shelter_type
				camp_index += 1
			AdventureEnums.RoomType.SHOP:
				room.content_id = "shop_visible" if room.back_type == AdventureEnums.BackType.SHOP else "shop_hidden"
			AdventureEnums.RoomType.EVENT:
				room.content_id = str(event_ids[event_index % event_ids.size()])
				room.high_value = room.content_id == "the_fall"
				event_index += 1


static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temporary = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary
