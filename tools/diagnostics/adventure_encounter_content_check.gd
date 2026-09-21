extends Node
var failures := 0

func _ready() -> void:
	var path := "res://scripts/adventure/adventure_encounter_content.gd"
	if not ResourceLoader.exists(path):
		printerr("HEX_ENCOUNTER_CONTENT: fixed encounter allocation missing")
		get_tree().quit(1)
		return
	var content: Script = load(path)
	var floor := AdventureFloorState.new()
	floor.floor_seed = 67394
	floor.current_room_id = "start"
	for i in range(7):
		var room := AdventureRoomState.new()
		room.room_id = "start" if i == 0 else "room%d" % i
		room.cell = Vector2i(i,0)
		room.room_type = AdventureEnums.RoomType.START if i == 0 else AdventureEnums.RoomType.NORMAL_BATTLE
		floor.rooms.append(room)
	var event := AdventureRoomState.new()
	event.room_id = "event"
	event.cell = Vector2i(2,1)
	event.room_type = AdventureEnums.RoomType.EVENT
	event.content_id = "adventurer_remains"
	floor.rooms.append(event)
	content.populate(floor)
	for i in range(1,7):
		var encounter: Dictionary = floor.rooms[i].runtime_data.get("encounter", {})
		_check(not encounter.get("id","").is_empty() and not encounter.get("enemies",[]).is_empty(), "fixed real encounter")
		var expected_tier := AdventureEnums.EncounterTier.WEAK if i <= 2 else (AdventureEnums.EncounterTier.MIXED if i <= 4 else AdventureEnums.EncounterTier.STRONG)
		_check(encounter.get("tier", -1) == expected_tier, "preserve weak/mixed/strong progression in stable map order")
	var danger_encounter: Dictionary = event.runtime_data.get("danger_encounter",{})
	_check(not danger_encounter.is_empty() and danger_encounter.get("tier",-1) in [0,1,2], "placeholder ordinary encounter fixed early")
	var before := floor.to_dict()
	floor.danger = 24
	floor.rooms[1].content_revealed = true
	content.populate(floor)
	_check(floor.rooms[1].runtime_data == before.rooms[1].runtime_data, "reveal/danger never reroll enemies")
	var restored := AdventureFloorState.from_dict(floor.to_dict())
	content.populate(restored)
	_check(restored.rooms[1].runtime_data == floor.rooms[1].runtime_data, "save/load no reroll")
	print("HEX_ENCOUNTER_CONTENT: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("HEX_ENCOUNTER_CONTENT: "+message)
