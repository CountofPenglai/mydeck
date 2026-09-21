extends Node
var failures := 0
var danger_service: Script
var reveal_service: Script
var travel_service: Script

func _ready() -> void:
	for path in ["adventure_danger_service", "adventure_reveal_service", "adventure_travel_service"]:
		_check(ResourceLoader.exists("res://scripts/adventure/"+path+".gd"), path+" missing")
	if failures:
		get_tree().quit(1)
		return
	danger_service = load("res://scripts/adventure/adventure_danger_service.gd")
	reveal_service = load("res://scripts/adventure/adventure_reveal_service.gd")
	travel_service = load("res://scripts/adventure/adventure_travel_service.gd")
	_test_danger()
	_test_reveal()
	_test_travel()
	print("HEX_DANGER_TRAVEL: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func _floor():
	var result = AdventureFloorState.new()
	result.floor_seed = 73
	result.current_room_id = "a"
	for i in range(7):
		var room = AdventureRoomState.from_dict({
			"id": String.chr(97+i), "cell": [i,0],
			"type": AdventureEnums.RoomType.EVENT, "high_value": true,
			"visited": i == 0, "content_revealed": i == 0, "completed": i == 0,
		})
		result.rooms.append(room)
	return result

func _test_danger() -> void:
	for row in [[0,0],[5,0],[6,10],[11,10],[12,20],[17,20],[18,40],[23,40],[24,60],[99,60]]:
		_check(danger_service.bonus_percent(row[0]) == row[1], "danger multiplier boundary")
	var floor = _floor()
	floor.danger = 5
	danger_service.advance(floor, "b")
	_check(floor.danger == 6 and _marks(floor) == 1, "first threshold grants one")
	_check(not floor.get_room("a").high_value_marked and not floor.get_room("b").high_value_marked, "exclude revealed and entering tiles")
	for i in range(6):
		danger_service.advance(floor, "b")
	_check(floor.danger == 12 and _marks(floor) == 3, "second threshold adds two")
	var restored = AdventureFloorState.from_dict(floor.to_dict())
	danger_service.advance(restored, "b")
	_check(_marks(restored) == 3, "restore never repeats marks")
	var scarce = _floor()
	for room in scarce.rooms:
		room.high_value = false
	scarce.danger = 5
	danger_service.advance(scarce, "b")
	scarce.rooms[2].high_value = true
	danger_service.advance(scarce, "b")
	_check(_marks(scarce) == 0, "no deferred compensation")

func _test_reveal() -> void:
	var floor = _floor()
	_check(reveal_service.get_candidates(floor, "a", 3).size() == 3, "radius3 independent of explored paths")
	for ids in [["b","b"], ["b","c","d"], ["b","missing"], ["e"], ["a"], []]:
		_check(not reveal_service.reveal(floor, _strings(ids)), "invalid scout selection rejected atomically")
		_check(not floor.get_room("b").content_revealed, "invalid batch no partial reveal")
	_check(reveal_service.reveal(floor, _strings(["b","d"])), "valid up to two")
	_check(floor.danger == 0 and floor.current_room_id == "a", "scout no danger/movement")
	_check(not floor.get_room("d").visited, "scout not exploration")

func _test_travel() -> void:
	var floor = _floor()
	_check(travel_service.plan(floor, "b") == _strings(["b"]), "adjacent new tile allowed")
	_check(travel_service.plan(floor, "c").is_empty(), "cannot cross unexplored intermediate")
	floor.get_room("b").visited = true
	_check(travel_service.plan(floor, "c") == _strings(["b","c"]), "explored intermediate allowed")
	floor.get_room("c").content_revealed = true
	_check(travel_service.plan(floor, "d").is_empty(), "scouted intermediate still unexplored")
	_check(travel_service.plan(floor, "missing").is_empty(), "invalid destination")
	_check(travel_service.plan(floor, "a").is_empty(), "current tile no travel")

func _marks(floor) -> int:
	var total := 0
	for room in floor.rooms:
		if room.high_value_marked:
			total += 1
	return total

func _strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	return result

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("HEX_DANGER_TRAVEL: "+message)
