extends RefCounted
class_name AdventureMapPresentation


static func for_room(floor: AdventureFloorState, room: AdventureRoomState, selected_room_id: String) -> Dictionary:
	var revealed := room.content_revealed
	var current := floor != null and room.room_id == floor.current_room_id
	var reachable := floor != null and current == false and not AdventureTravelService.plan(floor, room.room_id).is_empty()
	var back_type := room.back_type
	return {
		"room_id": room.room_id,
		"back_type": back_type,
		"revealed": revealed,
		"symbol_path": _symbol_path(back_type if not revealed else _front_symbol_type(room)),
		"title": _title(room, revealed),
		"selected": room.room_id == selected_room_id,
		"current": current,
		"reachable": reachable,
		"visited": room.visited,
		"completed": room.completed,
		# A face-down hex may show only a mark that has already been earned by scouting.
		"high_value": room.high_value_marked and not revealed,
	}


static func _front_symbol_type(room: AdventureRoomState) -> int:
	match room.room_type:
		AdventureEnums.RoomType.START:
			return AdventureEnums.BackType.START
		AdventureEnums.RoomType.NORMAL_BATTLE:
			return AdventureEnums.BackType.BATTLE
		AdventureEnums.RoomType.ELITE_BATTLE:
			return AdventureEnums.BackType.ELITE
		AdventureEnums.RoomType.BOSS_BATTLE:
			return AdventureEnums.BackType.BOSS
		AdventureEnums.RoomType.SHELTER:
			return AdventureEnums.BackType.CAMP
		AdventureEnums.RoomType.SHOP:
			return AdventureEnums.BackType.SHOP
		_:
			return AdventureEnums.BackType.MYSTERY


static func _title(room: AdventureRoomState, revealed: bool) -> String:
	if not revealed:
		return AdventureEnums.back_type_label(room.back_type)
	return room.get_display_name()


static func _symbol_path(back_type: int) -> String:
	var names := {
		AdventureEnums.BackType.START: "start",
		AdventureEnums.BackType.MYSTERY: "mystery",
		AdventureEnums.BackType.BATTLE: "battle",
		AdventureEnums.BackType.ELITE: "elite",
		AdventureEnums.BackType.CAMP: "camp",
		AdventureEnums.BackType.SHOP: "shop",
		AdventureEnums.BackType.BOSS: "boss",
	}
	return "res://assets/art/adventure/hex_tiles/symbols/%s.svg" % str(names.get(back_type, "mystery"))
